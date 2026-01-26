//
//  GraphStore.swift
//  SwiftMem
//
//  Created on 12/7/24.
//  Production-ready SQLite storage for graph nodes and edges
//

import Foundation
import SQLite3

// MARK: - SQLite Constants

/// SQLITE_TRANSIENT tells SQLite to make its own copy of the string
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Deletion Mode

/// Strategy for deleting nodes and their relationships
public enum DeletionMode {
    /// Delete only the node, keep all edges (creates orphaned edges)
    case nodeOnly
    
    /// Delete node and all connected edges (incoming + outgoing)
    case cascade
    
    /// Delete node and only outgoing edges (FROM this node)
    case nodeAndOutgoing
    
    /// Delete node and only incoming edges (TO this node)
    case nodeAndIncoming
}

// MARK: - Graph Store

/// SQLite-based storage for graph nodes and edges
/// Thread-safe, versioned schema, supports batch operations
public actor GraphStore {
    
    // MARK: - Properties
    
    internal var db: OpaquePointer?
    private let dbPath: URL
    private let config: SwiftMemConfig
    
    // Current schema version
    private static let currentSchemaVersion = 3  // v3: Added embeddings table for vector persistence
    
    // MARK: - Initialization
    
    private init(config: SwiftMemConfig, dbPath: URL, db: OpaquePointer) {
        self.config = config
        self.dbPath = dbPath
        self.db = db
    }
    
    /// Create and initialize a GraphStore
    public static func create(config: SwiftMemConfig) async throws -> GraphStore {
        return try await create(config: config, filename: "swiftmem_graph.db")
    }
    
    /// Create and initialize a GraphStore with custom filename
    public static func create(config: SwiftMemConfig, filename: String) async throws -> GraphStore {
        // Database file path
        let dbPath = try config.storageLocation.url(filename: filename)
        
        // Open database
        var db: OpaquePointer?
        try openDatabase(at: dbPath, db: &db)
        
        guard let db = db else {
            throw SwiftMemError.storageError("Failed to create database")
        }
        
        // Create store
        let store = GraphStore(config: config, dbPath: dbPath, db: db)
        
        // Initialize schema
        try await store.initializeSchema()
        
        // Run migrations if needed
        try await store.migrate()
        
        return store
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Database Opening
    
    private static func openDatabase(at path: URL, db: inout OpaquePointer?) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        
        let result = sqlite3_open_v2(path.path, &db, flags, nil)
        
        // Defer foreign key constraint checks until transaction commit
        // This allows inserting relationships that reference nodes in the same transaction
        if result == SQLITE_OK, let db = db {
            // CRITICAL: Use DELETE journal mode instead of WAL to avoid conflicts with SwiftData
            sqlite3_exec(db, "PRAGMA journal_mode = DELETE;", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA defer_foreign_keys = ON;", nil, nil, nil)
        }
        
        guard result == SQLITE_OK else {
            let message = db != nil ? String(cString: sqlite3_errmsg(db)) : "Unknown error"
            throw SwiftMemError.storageError("Failed to open database: \(message)")
        }
        
        // Enable foreign keys
        guard let db = db else {
            throw SwiftMemError.storageError("Database pointer is null")
        }
        
        var error: UnsafeMutablePointer<Int8>?
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, &error)
        
        if let error = error {
            let message = String(cString: error)
            sqlite3_free(error)
            throw SwiftMemError.storageError("Failed to enable foreign keys: \(message)")
        }
    }
    
    // MARK: - Schema Initialization
    
    private func initializeSchema() async throws {
        let schemas = [
            // Schema version tracking
            """
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL
            );
            """,
            
            // Nodes table
            """
            CREATE TABLE IF NOT EXISTS nodes (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                type TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                conversation_date TEXT NOT NULL,
                event_date TEXT,
                metadata TEXT
            );
            """,
            
            // Edges table with foreign key constraints
            """
            CREATE TABLE IF NOT EXISTS edges (
                id TEXT PRIMARY KEY,
                from_node_id TEXT NOT NULL,
                to_node_id TEXT NOT NULL,
                relationship_type TEXT NOT NULL,
                weight REAL NOT NULL DEFAULT 1.0,
                created_at TEXT NOT NULL,
                metadata TEXT,
                FOREIGN KEY (from_node_id) REFERENCES nodes(id) ON DELETE CASCADE,
                FOREIGN KEY (to_node_id) REFERENCES nodes(id) ON DELETE CASCADE
            );
            """,
            
            // Embeddings table for vector persistence
            """
            CREATE TABLE IF NOT EXISTS embeddings (
                node_id TEXT PRIMARY KEY,
                vector BLOB NOT NULL,
                dimensions INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE
            );
            """,
            
            // Indexes for performance
            """
            CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(type);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_nodes_created_at ON nodes(created_at);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_nodes_updated_at ON nodes(updated_at);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_edges_from ON edges(from_node_id);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_edges_to ON edges(to_node_id);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_edges_relationship ON edges(relationship_type);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_edges_weight ON edges(weight);
            """
        ]
        
        for schema in schemas {
            try execute(schema)
        }
    }
    
    // MARK: - Migration
    
    private func migrate() async throws {
        let currentVersion = try await getSchemaVersion()
        
        if currentVersion < Self.currentSchemaVersion {
            // Run migrations from currentVersion to latest
            for version in (currentVersion + 1)...Self.currentSchemaVersion {
                try await runMigration(to: version)
            }
        }
    }
    
    private func getSchemaVersion() async throws -> Int {
        let query = "SELECT MAX(version) FROM schema_version;"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            // Table doesn't exist yet, version is 0
            return 0
        }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let version = sqlite3_column_int(statement, 0)
            return Int(version)
        }
        
        return 0
    }
    
    private func runMigration(to version: Int) async throws {
        switch version {
        case 2:
            // Add dual timestamp columns (check if they exist first)
            let hasConversationDate = try checkColumnExists(table: "nodes", column: "conversation_date")
            if !hasConversationDate {
                try execute("""
                ALTER TABLE nodes ADD COLUMN conversation_date TEXT;
                """)
                
                // Backfill conversation_date with created_at for existing rows
                try execute("""
                UPDATE nodes SET conversation_date = created_at WHERE conversation_date IS NULL;
                """)
            }
            
            let hasEventDate = try checkColumnExists(table: "nodes", column: "event_date")
            if !hasEventDate {
                try execute("""
                ALTER TABLE nodes ADD COLUMN event_date TEXT;
                """)
            }
            
        case 3:
            // Add embeddings table for vector persistence
            try execute("""
            CREATE TABLE IF NOT EXISTS embeddings (
                node_id TEXT PRIMARY KEY,
                vector BLOB NOT NULL,
                dimensions INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE
            );
            """)
            
        default:
            break
        }
        
        // Record migration
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let insertVersion = """
        INSERT INTO schema_version (version, applied_at)
        VALUES (\(version), '\(timestamp)');
        """
        
        try execute(insertVersion)
    }
    
    private func checkColumnExists(table: String, column: String) throws -> Bool {
        let sql = "PRAGMA table_info(\(table));"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(statement, 1) {
                let columnName = String(cString: namePtr)
                if columnName == column {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Node Operations
    
    /// Store a single node
    public func storeNode(_ node: Node) async throws {
        try await storeNodes([node])
    }
    
    /// Store multiple nodes in a single transaction (batch operation)
    public func storeNodes(_ nodes: [Node]) async throws {
        guard !nodes.isEmpty else { return }
        
        try execute("BEGIN TRANSACTION;")
        
        do {
            for node in nodes {
                let metadataJSON = try encodeMetadata(node.metadata)
                
                let sql = """
                INSERT OR REPLACE INTO nodes (id, content, type, created_at, updated_at, conversation_date, event_date, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """
                
                var statement: OpaquePointer?
                defer {
                    if statement != nil {
                        sqlite3_finalize(statement)
                    }
                }
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw SwiftMemError.storageError("Failed to prepare node insert: \(lastErrorMessage())")
                }
                
                // Keep strings alive by storing in variables
                let idStr = node.id.value.uuidString
                let typeStr = node.type.rawValue
                let createdStr = ISO8601DateFormatter().string(from: node.createdAt)
                let updatedStr = ISO8601DateFormatter().string(from: node.updatedAt)
                let conversationStr = ISO8601DateFormatter().string(from: node.conversationDate)
                let eventStr = node.eventDate.map { ISO8601DateFormatter().string(from: $0) }
                
                idStr.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
                node.content.withCString { sqlite3_bind_text(statement, 2, $0, -1, SQLITE_TRANSIENT) }
                typeStr.withCString { sqlite3_bind_text(statement, 3, $0, -1, SQLITE_TRANSIENT) }
                createdStr.withCString { sqlite3_bind_text(statement, 4, $0, -1, SQLITE_TRANSIENT) }
                updatedStr.withCString { sqlite3_bind_text(statement, 5, $0, -1, SQLITE_TRANSIENT) }
                conversationStr.withCString { sqlite3_bind_text(statement, 6, $0, -1, SQLITE_TRANSIENT) }
                
                if let eventStr = eventStr {
                    eventStr.withCString { sqlite3_bind_text(statement, 7, $0, -1, SQLITE_TRANSIENT) }
                } else {
                    sqlite3_bind_null(statement, 7)
                }
                
                metadataJSON.withCString { sqlite3_bind_text(statement, 8, $0, -1, SQLITE_TRANSIENT) }
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw SwiftMemError.storageError("Failed to insert node: \(lastErrorMessage())")
                }
            }
            
            try execute("COMMIT;")
        } catch {
            try execute("ROLLBACK;")
            throw error
        }
    }
    
    /// Retrieve a node by ID
    public func getNode(_ id: NodeID) async throws -> Node? {
        let sql = """
        SELECT id, content, type, created_at, updated_at, conversation_date, event_date, metadata
        FROM nodes WHERE id = ?;
        """
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare node select: \(lastErrorMessage())")
        }
        
        let idStr = id.value.uuidString
        idStr.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return try decodeNode(from: statement!)
        }
        
        return nil
    }
    
    /// Get all nodes matching a filter
    public func getNodes(
        type: MemoryType? = nil,
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        limit: Int? = nil,
        offset: Int = 0
    ) async throws -> [Node] {
        var sql = "SELECT id, content, type, created_at, updated_at, conversation_date, event_date, metadata FROM nodes WHERE 1=1"
        var conditions: [String] = []
        
        if let type = type {
            conditions.append("type = '\(type.rawValue)'")
        }
        
        if let createdAfter = createdAfter {
            conditions.append("created_at >= '\(ISO8601DateFormatter().string(from: createdAfter))'")
        }
        
        if let createdBefore = createdBefore {
            conditions.append("created_at <= '\(ISO8601DateFormatter().string(from: createdBefore))'")
        }
        
        if !conditions.isEmpty {
            sql += " AND " + conditions.joined(separator: " AND ")
        }
        
        sql += " ORDER BY created_at DESC"
        
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }
        
        sql += ";"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare nodes query: \(lastErrorMessage())")
        }
        
        var nodes: [Node] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let node = try decodeNode(from: statement!)
            nodes.append(node)
        }
        
        return nodes
    }
    
    /// Get all nodes (convenience method for visualization)
    public func getAllNodes() async throws -> [Node] {
        return try await getNodes(type: nil, createdAfter: nil, createdBefore: nil, limit: nil, offset: 0)
    }
    
    /// Get nodes with flexible filtering (for ConflictDetector)
    public func getNodes(
        filters: [NodeFilter] = [],
        limit: Int? = nil,
        offset: Int = 0
    ) async throws -> [Node] {
        var sql = "SELECT id, content, type, created_at, updated_at, conversation_date, event_date, metadata FROM nodes WHERE 1=1"
        var conditions: [String] = []
        
        for filter in filters {
            switch filter {
            case .type(let memoryType):
                conditions.append("type = '\(memoryType.rawValue)'")
            case .createdAfter(let date):
                conditions.append("created_at >= '\(ISO8601DateFormatter().string(from: date))'")
            case .createdBefore(let date):
                conditions.append("created_at <= '\(ISO8601DateFormatter().string(from: date))'")
            case .contentContains(let text):
                conditions.append("content LIKE '%\(text)%'")
            case .metadataKey(let key):
                conditions.append("metadata LIKE '%\"\(key)\"%'")
            case .metadataValue(let key, let value):
                // Check both key and value in JSON metadata
                // Format: "key":"value" for strings, "key":123 for ints, etc.
                let valueStr: String
                switch value {
                case .string(let str):
                    valueStr = "\"\(key)\":\"\(str)\""
                case .int(let int):
                    valueStr = "\"\(key)\":\(int)"
                case .double(let double):
                    valueStr = "\"\(key)\":\(double)"
                case .bool(let bool):
                    valueStr = "\"\(key)\":\(bool)"
                @unknown default:
                    // Fallback to just checking key exists
                    valueStr = "\"\(key)\""
                }
                conditions.append("metadata LIKE '%\(valueStr)%'")
            }
        }
        
        if !conditions.isEmpty {
            sql += " AND " + conditions.joined(separator: " AND ")
        }
        
        sql += " ORDER BY created_at DESC"
        
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }
        
        sql += ";"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare nodes query: \(lastErrorMessage())")
        }
        
        var nodes: [Node] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let node = try decodeNode(from: statement!)
            nodes.append(node)
        }
        
        return nodes
    }
    
    /// Update a node's content and/or metadata
    public func updateNode(
        _ id: NodeID,
        content: String? = nil,
        metadata: [String: MetadataValue]? = nil
    ) async throws {
        var updates: [String] = []
        
        if let content = content {
            updates.append("content = '\(content.replacingOccurrences(of: "'", with: "''"))'")
        }
        
        if let metadata = metadata {
            let metadataJSON = try encodeMetadata(metadata)
            updates.append("metadata = '\(metadataJSON.replacingOccurrences(of: "'", with: "''"))'")
        }
        
        updates.append("updated_at = '\(ISO8601DateFormatter().string(from: Date()))'")
        
        guard !updates.isEmpty else { return }
        
        let sql = "UPDATE nodes SET \(updates.joined(separator: ", ")) WHERE id = '\(id.value.uuidString)';"
        try execute(sql)
    }
    
    /// Delete a node with specified deletion mode
    public func deleteNode(_ id: NodeID, mode: DeletionMode = .cascade) async throws {
        try execute("BEGIN TRANSACTION;")
        
        do {
            switch mode {
            case .nodeOnly:
                // Just delete the node, foreign key constraints will fail if edges exist
                // Turn off foreign keys temporarily
                try execute("PRAGMA foreign_keys = OFF;")
                try execute("DELETE FROM nodes WHERE id = '\(id.value.uuidString)';")
                try execute("PRAGMA foreign_keys = ON;")
                
            case .cascade:
                // Delete all connected edges, then the node
                try execute("DELETE FROM edges WHERE from_node_id = '\(id.value.uuidString)' OR to_node_id = '\(id.value.uuidString)';")
                try execute("DELETE FROM nodes WHERE id = '\(id.value.uuidString)';")
                
            case .nodeAndOutgoing:
                // Delete outgoing edges, then the node
                try execute("DELETE FROM edges WHERE from_node_id = '\(id.value.uuidString)';")
                try execute("DELETE FROM nodes WHERE id = '\(id.value.uuidString)';")
                
            case .nodeAndIncoming:
                // Delete incoming edges, then the node
                try execute("DELETE FROM edges WHERE to_node_id = '\(id.value.uuidString)';")
                try execute("DELETE FROM nodes WHERE id = '\(id.value.uuidString)';")
            }
            
            try execute("COMMIT;")
        } catch {
            try execute("ROLLBACK;")
            throw error
        }
    }
    
    /// Get total node count
    public func getNodeCount() async throws -> Int {
        let sql = "SELECT COUNT(*) FROM nodes;"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare count query: \(lastErrorMessage())")
        }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        
        return 0
    }
    
    // MARK: - Edge Operations
    
    /// Store a single edge
    public func storeEdge(_ edge: Edge) async throws {
        try await storeEdges([edge])
    }
    
    /// Store multiple edges in a single transaction
    public func storeEdges(_ edges: [Edge]) async throws {
        guard !edges.isEmpty else { return }
        
        try execute("BEGIN TRANSACTION;")
        
        do {
            for edge in edges {
                let metadataJSON = try encodeMetadata(edge.metadata)
                
                let sql = """
                INSERT OR REPLACE INTO edges (id, from_node_id, to_node_id, relationship_type, weight, created_at, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """
                
                var statement: OpaquePointer?
                defer {
                    if statement != nil {
                        sqlite3_finalize(statement)
                    }
                }
                
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw SwiftMemError.storageError("Failed to prepare edge insert: \(lastErrorMessage())")
                }
                
                // Keep strings alive with .withCString and SQLITE_TRANSIENT
                let idStr = edge.id.value.uuidString
                let fromStr = edge.fromNodeID.value.uuidString
                let toStr = edge.toNodeID.value.uuidString
                let relStr = edge.relationshipType.rawValue
                let createdStr = ISO8601DateFormatter().string(from: edge.createdAt)
                
                idStr.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
                fromStr.withCString { sqlite3_bind_text(statement, 2, $0, -1, SQLITE_TRANSIENT) }
                toStr.withCString { sqlite3_bind_text(statement, 3, $0, -1, SQLITE_TRANSIENT) }
                relStr.withCString { sqlite3_bind_text(statement, 4, $0, -1, SQLITE_TRANSIENT) }
                sqlite3_bind_double(statement, 5, edge.weight)
                createdStr.withCString { sqlite3_bind_text(statement, 6, $0, -1, SQLITE_TRANSIENT) }
                metadataJSON.withCString { sqlite3_bind_text(statement, 7, $0, -1, SQLITE_TRANSIENT) }
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw SwiftMemError.storageError("Failed to insert edge: \(lastErrorMessage())")
                }
            }
            
            try execute("COMMIT;")
        } catch {
            try execute("ROLLBACK;")
            throw error
        }
    }
    
    /// Get all edges from a node
    public func getOutgoingEdges(from nodeId: NodeID) async throws -> [Edge] {
        let sql = """
        SELECT id, from_node_id, to_node_id, relationship_type, weight, created_at, metadata
        FROM edges WHERE from_node_id = ?;
        """
        
        return try await queryEdges(sql: sql, bindValue: nodeId.value.uuidString)
    }
    
    /// Get all edges to a node
    public func getIncomingEdges(to nodeId: NodeID) async throws -> [Edge] {
        let sql = """
        SELECT id, from_node_id, to_node_id, relationship_type, weight, created_at, metadata
        FROM edges WHERE to_node_id = ?;
        """
        
        return try await queryEdges(sql: sql, bindValue: nodeId.value.uuidString)
    }
    
    /// Get all edges connected to a node (incoming + outgoing)
    public func getAllEdges(for nodeId: NodeID) async throws -> [Edge] {
        let sql = """
        SELECT id, from_node_id, to_node_id, relationship_type, weight, created_at, metadata
        FROM edges WHERE from_node_id = ? OR to_node_id = ?;
        """
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare edges query: \(lastErrorMessage())")
        }
        
        sqlite3_bind_text(statement, 1, nodeId.value.uuidString, -1, nil)
        sqlite3_bind_text(statement, 2, nodeId.value.uuidString, -1, nil)
        
        var edges: [Edge] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let edge = try decodeEdge(from: statement!)
            edges.append(edge)
        }
        
        return edges
    }
    
    /// Get edges by relationship type
    public func getEdges(byRelationship relationship: RelationshipType) async throws -> [Edge] {
        let sql = """
        SELECT id, from_node_id, to_node_id, relationship_type, weight, created_at, metadata
        FROM edges WHERE relationship_type = ?;
        """
        
        return try await queryEdges(sql: sql, bindValue: relationship.rawValue)
    }
    
    /// Delete an edge
    public func deleteEdge(_ id: EdgeID) async throws {
        try execute("DELETE FROM edges WHERE id = '\(id.value.uuidString)';")
    }
    
    /// Delete all edges between two nodes
    public func deleteEdges(from: NodeID, to: NodeID) async throws {
        try execute("DELETE FROM edges WHERE from_node_id = '\(from.value.uuidString)' AND to_node_id = '\(to.value.uuidString)';")
    }
    
    /// Get total edge count
    public func getEdgeCount() async throws -> Int {
        let sql = "SELECT COUNT(*) FROM edges;"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare count query: \(lastErrorMessage())")
        }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        
        return 0
    }
    
    // MARK: - Graph Traversal Queries
    
    /// Get neighboring nodes (1-hop away)
    public func getNeighbors(of nodeId: NodeID, relationship: String? = nil) async throws -> [Node] {
        var sql = """
        SELECT DISTINCT n.id, n.content, n.type, n.created_at, n.updated_at, n.metadata
        FROM nodes n
        INNER JOIN edges e ON (e.to_node_id = n.id OR e.from_node_id = n.id)
        WHERE (e.from_node_id = ? OR e.to_node_id = ?)
        AND n.id != ?
        """
        
        if let relationship = relationship {
            sql += " AND e.relationship_type = '\(relationship)'"
        }
        
        sql += ";"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare neighbors query: \(lastErrorMessage())")
        }
        
        sqlite3_bind_text(statement, 1, nodeId.value.uuidString, -1, nil)
        sqlite3_bind_text(statement, 2, nodeId.value.uuidString, -1, nil)
        sqlite3_bind_text(statement, 3, nodeId.value.uuidString, -1, nil)
        
        var nodes: [Node] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let node = try decodeNode(from: statement!)
            nodes.append(node)
        }
        
        return nodes
    }
    
    // MARK: - Utility Operations
    
    /// Clear all data (nodes and edges)
    public func clearAll() async throws {
        try execute("DELETE FROM edges;")
        try execute("DELETE FROM nodes;")
    }
    
    /// Get database statistics
    public func getStats() async throws -> (nodeCount: Int, edgeCount: Int, dbSize: Int64) {
        let nodeCount = try await getNodeCount()
        let edgeCount = try await getEdgeCount()
        
        let attributes = try FileManager.default.attributesOfItem(atPath: dbPath.path)
        let dbSize = attributes[.size] as? Int64 ?? 0
        
        return (nodeCount, edgeCount, dbSize)
    }
    
    /// Get database file size in bytes
    public func getDatabaseSize() async throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: dbPath.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    // MARK: - Helper Methods
    
    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        
        if result != SQLITE_OK {
            let message = error != nil ? String(cString: error!) : "Unknown error"
            sqlite3_free(error)
            throw SwiftMemError.storageError("SQL execution failed: \(message)")
        }
    }
    
    private func lastErrorMessage() -> String {
        if let db = db {
            return String(cString: sqlite3_errmsg(db))
        }
        return "Unknown error"
    }
    
    private func queryEdges(sql: String, bindValue: String) async throws -> [Edge] {
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare edges query: \(lastErrorMessage())")
        }
        
        bindValue.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
        
        var edges: [Edge] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let edge = try decodeEdge(from: statement!)
            edges.append(edge)
        }
        
        return edges
    }
    
    // MARK: - Encoding/Decoding
    
    private func encodeMetadata(_ metadata: [String: MetadataValue]) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    private func decodeMetadata(_ json: String) throws -> [String: MetadataValue] {
        guard let data = json.data(using: .utf8) else {
            return [:]
        }
        let decoder = JSONDecoder()
        return try decoder.decode([String: MetadataValue].self, from: data)
    }
    
    private func decodeNode(from statement: OpaquePointer) throws -> Node {
        // Debug: Check what SQLite is returning
        let columnCount = sqlite3_column_count(statement)
        
        // Read all columns with null checks
        let col0Ptr = sqlite3_column_text(statement, 0)
        guard col0Ptr != nil else {
            throw SwiftMemError.storageError("Failed to decode node: id column is NULL (total columns: \(columnCount))")
        }
        let idString = String(cString: col0Ptr!)
        
        guard !idString.isEmpty else {
            throw SwiftMemError.storageError("Failed to decode node: id string is empty (total columns: \(columnCount))")
        }
        
        guard sqlite3_column_text(statement, 1) != nil else {
            throw SwiftMemError.storageError("Failed to decode node: content column is NULL")
        }
        let content = String(cString: sqlite3_column_text(statement, 1))
        
        guard sqlite3_column_text(statement, 2) != nil else {
            throw SwiftMemError.storageError("Failed to decode node: type column is NULL")
        }
        let typeString = String(cString: sqlite3_column_text(statement, 2))
        
        guard sqlite3_column_text(statement, 3) != nil else {
            throw SwiftMemError.storageError("Failed to decode node: created_at column is NULL")
        }
        let createdAtString = String(cString: sqlite3_column_text(statement, 3))
        
        guard sqlite3_column_text(statement, 4) != nil else {
            throw SwiftMemError.storageError("Failed to decode node: updated_at column is NULL")
        }
        let updatedAtString = String(cString: sqlite3_column_text(statement, 4))
        
        guard sqlite3_column_text(statement, 5) != nil else {
            throw SwiftMemError.storageError("Failed to decode node: conversation_date column is NULL")
        }
        let conversationDateString = String(cString: sqlite3_column_text(statement, 5))
        
        // event_date can be NULL
        let eventDateString: String? = {
            if let ptr = sqlite3_column_text(statement, 6) {
                return String(cString: ptr)
            }
            return nil
        }()
        
        guard sqlite3_column_text(statement, 7) != nil else {
            throw SwiftMemError.storageError("Failed to decode node: metadata column is NULL")
        }
        let metadataString = String(cString: sqlite3_column_text(statement, 7))
        
        guard let id = UUID(uuidString: idString) else {
            throw SwiftMemError.storageError("Failed to decode node: invalid UUID '\(idString)'")
        }
        
        guard let type = MemoryType(rawValue: typeString) else {
            throw SwiftMemError.storageError("Failed to decode node: invalid type '\(typeString)'")
        }
        
        guard let createdAt = ISO8601DateFormatter().date(from: createdAtString) else {
            throw SwiftMemError.storageError("Failed to decode node: invalid created_at '\(createdAtString)'")
        }
        
        guard let updatedAt = ISO8601DateFormatter().date(from: updatedAtString) else {
            throw SwiftMemError.storageError("Failed to decode node: invalid updated_at '\(updatedAtString)'")
        }
        
        guard let conversationDate = ISO8601DateFormatter().date(from: conversationDateString) else {
            throw SwiftMemError.storageError("Failed to decode node: invalid conversation_date '\(conversationDateString)'")
        }
        
        let eventDate: Date? = {
            guard let dateStr = eventDateString else { return nil }
            return ISO8601DateFormatter().date(from: dateStr)
        }()
        
        let metadata = try decodeMetadata(metadataString)
        
        return Node(
            id: NodeID(value: id),
            content: content,
            type: type,
            metadata: metadata,
            createdAt: createdAt,
            updatedAt: updatedAt,
            conversationDate: conversationDate,
            eventDate: eventDate
        )
    }
    
    private func decodeEdge(from statement: OpaquePointer) throws -> Edge {
        let idString = String(cString: sqlite3_column_text(statement, 0))
        let fromNodeIdString = String(cString: sqlite3_column_text(statement, 1))
        let toNodeIdString = String(cString: sqlite3_column_text(statement, 2))
        let relationshipTypeString = String(cString: sqlite3_column_text(statement, 3))
        let weight = sqlite3_column_double(statement, 4)
        let createdAtString = String(cString: sqlite3_column_text(statement, 5))
        let metadataString = String(cString: sqlite3_column_text(statement, 6))
        
        guard let id = UUID(uuidString: idString),
              let fromNodeId = UUID(uuidString: fromNodeIdString),
              let toNodeId = UUID(uuidString: toNodeIdString),
              let createdAt = ISO8601DateFormatter().date(from: createdAtString) else {
            throw SwiftMemError.storageError("Failed to decode edge")
        }
        
        // Parse relationship type with fallback to .related
        let relationshipType = RelationshipType(rawValue: relationshipTypeString) ?? .related
        
        let metadata = try decodeMetadata(metadataString)
        
        return Edge(
            id: EdgeID(value: id),
            fromNodeID: NodeID(value: fromNodeId),
            toNodeID: NodeID(value: toNodeId),
            relationshipType: relationshipType,
            weight: weight,
            createdAt: createdAt,
            metadata: metadata
        )
    }
    
    // MARK: - Embedding Storage
    
    /// Store an embedding vector for a node
    public func storeEmbedding(_ vector: [Float], for nodeId: NodeID) throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        // Convert Float array to Data (BLOB)
        let data = vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        let sql = """
        INSERT OR REPLACE INTO embeddings (node_id, vector, dimensions, created_at)
        VALUES (?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to prepare embedding insert: \(message)")
        }
        
        sqlite3_bind_text(statement, 1, nodeId.value.uuidString, -1, SQLITE_TRANSIENT)
        data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
        sqlite3_bind_int(statement, 3, Int32(vector.count))
        sqlite3_bind_text(statement, 4, timestamp, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to store embedding: \(message)")
        }
    }
    
    /// Retrieve an embedding vector for a node
    public func getEmbedding(for nodeId: NodeID) throws -> [Float]? {
        let sql = "SELECT vector, dimensions FROM embeddings WHERE node_id = ?;"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to prepare embedding query: \(message)")
        }
        
        sqlite3_bind_text(statement, 1, nodeId.value.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil // No embedding found
        }
        
        let blobPointer = sqlite3_column_blob(statement, 0)
        let blobSize = sqlite3_column_bytes(statement, 0)
        let dimensions = Int(sqlite3_column_int(statement, 1))
        
        guard let blobPointer = blobPointer else {
            return nil
        }
        
        // Convert BLOB back to Float array
        let data = Data(bytes: blobPointer, count: Int(blobSize))
        let vector = data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
        
        guard vector.count == dimensions else {
            throw SwiftMemError.storageError("Embedding dimension mismatch: expected \(dimensions), got \(vector.count)")
        }
        
        return vector
    }
    
    /// Retrieve all embeddings (for loading into VectorStore on startup)
    public func getAllEmbeddings() throws -> [(nodeId: NodeID, vector: [Float])] {
        let sql = "SELECT node_id, vector, dimensions FROM embeddings;"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to prepare embeddings query: \(message)")
        }
        
        var results: [(nodeId: NodeID, vector: [Float])] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let nodeIdString = String(cString: sqlite3_column_text(statement, 0))
            let blobPointer = sqlite3_column_blob(statement, 1)
            let blobSize = sqlite3_column_bytes(statement, 1)
            
            guard let nodeIdUUID = UUID(uuidString: nodeIdString),
                  let blobPointer = blobPointer else {
                continue
            }
            
            let data = Data(bytes: blobPointer, count: Int(blobSize))
            let vector = data.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Float.self))
            }
            
            results.append((nodeId: NodeID(value: nodeIdUUID), vector: vector))
        }
        
        return results
    }
    
    /// Delete an embedding for a node
    public func deleteEmbedding(for nodeId: NodeID) throws {
        let sql = "DELETE FROM embeddings WHERE node_id = ?;"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to prepare embedding delete: \(message)")
        }
        
        sqlite3_bind_text(statement, 1, nodeId.value.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to delete embedding: \(message)")
        }
    }
    
    /// Get count of stored embeddings
    public func embeddingCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM embeddings;"
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        
        return 0
    }
}
