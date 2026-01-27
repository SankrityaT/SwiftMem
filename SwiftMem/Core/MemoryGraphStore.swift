//
//  MemoryGraphStore.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation
import SQLite3

// MARK: - SQLite Constants
/// SQLITE_TRANSIENT tells SQLite to make its own copy of the string
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Enhanced GraphStore that persists MemoryNodes with relationships
/// Integrates with existing GraphStore for backward compatibility
public actor MemoryGraphStore {
    
    private let graphStore: GraphStore
    private let memoryGraph: MemoryGraph
    private var db: OpaquePointer?
    
    // MARK: - Initialization
    
    public static func create(config: SwiftMemConfig) async throws -> MemoryGraphStore {
        let graphStore = try await GraphStore.create(config: config)
        let memoryGraph = MemoryGraph()
        
        let store = MemoryGraphStore(graphStore: graphStore, memoryGraph: memoryGraph)
        try await store.initializeDatabase()
        try await store.initializeMemorySchema()
        try await store.loadMemoriesIntoGraph()
        
        return store
    }
    
    /// Create with existing GraphStore to prevent double database creation
    public static func create(config: SwiftMemConfig, graphStore: GraphStore) async throws -> MemoryGraphStore {
        let memoryGraph = MemoryGraph()
        
        let store = MemoryGraphStore(graphStore: graphStore, memoryGraph: memoryGraph)
        try await store.initializeDatabase()
        try await store.initializeMemorySchema()
        try await store.loadMemoriesIntoGraph()
        
        return store
    }
    
    private init(graphStore: GraphStore, memoryGraph: MemoryGraph) {
        self.graphStore = graphStore
        self.memoryGraph = memoryGraph
    }
    
    private func initializeDatabase() async {
        self.db = await graphStore.db
    }
    
    // MARK: - Schema
    
    private func initializeMemorySchema() async throws {
        // Extend existing schema with memory-specific tables
        let schemas = [
            // Memory nodes with embeddings and metadata
            """
            CREATE TABLE IF NOT EXISTS memory_nodes (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                embedding BLOB NOT NULL,
                timestamp TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 1.0,
                is_latest INTEGER NOT NULL DEFAULT 1,
                is_static INTEGER NOT NULL DEFAULT 0,
                container_tags TEXT,
                source TEXT NOT NULL,
                importance REAL NOT NULL DEFAULT 0.5,
                access_count INTEGER NOT NULL DEFAULT 0,
                last_accessed TEXT,
                user_confirmed INTEGER NOT NULL DEFAULT 0,
                entities TEXT,
                topics TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """,
            
            // Memory relationships
            """
            CREATE TABLE IF NOT EXISTS memory_relationships (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                target_id TEXT NOT NULL,
                type TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 1.0,
                timestamp TEXT NOT NULL,
                FOREIGN KEY (source_id) REFERENCES memory_nodes(id) ON DELETE CASCADE,
                FOREIGN KEY (target_id) REFERENCES memory_nodes(id) ON DELETE CASCADE
            );
            """,
            
            // Indexes for performance
            """
            CREATE INDEX IF NOT EXISTS idx_memory_nodes_timestamp ON memory_nodes(timestamp);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_memory_nodes_is_latest ON memory_nodes(is_latest);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_memory_nodes_confidence ON memory_nodes(confidence);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_memory_relationships_source ON memory_relationships(source_id);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_memory_relationships_target ON memory_relationships(target_id);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_memory_relationships_type ON memory_relationships(type);
            """
        ]
        
        // Execute schema creation using GraphStore's database
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }
        
        for schema in schemas {
            var error: UnsafeMutablePointer<Int8>?
            let result = sqlite3_exec(db, schema, nil, nil, &error)
            
            if result != SQLITE_OK {
                let message = error != nil ? String(cString: error!) : "Unknown error"
                sqlite3_free(error)
                throw SwiftMemError.storageError("Failed to create schema: \(message)")
            }
        }
        
        print("✅ [MemoryGraphStore] Schema initialized successfully")
    }
    
    // MARK: - Memory Operations

    /// Execute raw SQL (for transactions)
    private func execute(_ sql: String) throws {
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }
        var error: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let message = error != nil ? String(cString: error!) : "Unknown error"
            sqlite3_free(error)
            throw SwiftMemError.storageError("SQL execution failed: \(message)")
        }
    }

    /// Add a memory node
    public func addMemory(_ node: MemoryNode) async throws {
        // Add to in-memory graph first
        await memoryGraph.addNode(node)

        // Use transaction for atomic persistence
        try execute("BEGIN TRANSACTION;")

        do {
            // Persist to database
            try await persistMemoryNode(node)

            // Persist relationships
            for relationship in node.relationships {
                try await persistRelationship(from: node.id, relationship: relationship)
            }

            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
    
    /// Update a memory node
    public func updateMemory(_ node: MemoryNode) async throws {
        await memoryGraph.updateNode(node)

        // Use transaction for atomic persistence
        try execute("BEGIN TRANSACTION;")

        do {
            try await persistMemoryNode(node)

            // Delete old relationships and add new ones
            try await deleteRelationships(for: node.id)
            for relationship in node.relationships {
                try await persistRelationship(from: node.id, relationship: relationship)
            }

            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
    
    /// Get a memory by ID
    public func getMemory(_ id: UUID) async -> MemoryNode? {
        return await memoryGraph.getNode(id)
    }
    
    /// Get all memories
    public func getAllMemories() async -> [MemoryNode] {
        return await memoryGraph.getAllNodes()
    }
    
    /// Delete a memory by ID
    public func deleteMemory(_ id: UUID) async {
        await memoryGraph.removeNode(id)

        // Also delete from database
        guard let db = db else { return }

        // Delete relationships first (foreign key constraints)
        let deleteRelSql = "DELETE FROM memory_relationships WHERE source_id = ? OR target_id = ?;"
        var relStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteRelSql, -1, &relStatement, nil) == SQLITE_OK {
            let idStr = id.uuidString
            idStr.withCString { ptr in
                sqlite3_bind_text(relStatement, 1, ptr, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(relStatement, 2, ptr, -1, SQLITE_TRANSIENT)
            }
            sqlite3_step(relStatement)
            sqlite3_finalize(relStatement)
        }

        // Delete the memory node
        let deleteNodeSql = "DELETE FROM memory_nodes WHERE id = ?;"
        var nodeStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteNodeSql, -1, &nodeStatement, nil) == SQLITE_OK {
            let idStr = id.uuidString
            idStr.withCString { sqlite3_bind_text(nodeStatement, 1, $0, -1, SQLITE_TRANSIENT) }
            sqlite3_step(nodeStatement)
            sqlite3_finalize(nodeStatement)
        }
    }
    
    /// Add a relationship between memories
    public func addRelationship(
        from sourceId: UUID,
        to targetId: UUID,
        type: RelationType,
        confidence: Float = 1.0
    ) async throws {
        await memoryGraph.addRelationship(from: sourceId, to: targetId, type: type, confidence: confidence)

        let relationship = MemoryRelationship(type: type, targetId: targetId, confidence: confidence)

        // Use transaction for atomic persistence
        try execute("BEGIN TRANSACTION;")
        do {
            try await persistRelationship(from: sourceId, relationship: relationship)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
    
    /// Get related memories
    public func getRelatedMemories(_ nodeId: UUID, ofType type: RelationType? = nil) async -> [MemoryNode] {
        return await memoryGraph.getRelatedNodes(nodeId, ofType: type)
    }
    
    /// Get latest version of a memory
    public func getLatestVersion(of nodeId: UUID) async -> MemoryNode? {
        return await memoryGraph.getLatestVersion(of: nodeId)
    }
    
    /// Get enriched context for a memory
    public func getEnrichedContext(for nodeId: UUID) async -> [MemoryNode] {
        return await memoryGraph.getEnrichedContext(for: nodeId)
    }
    
    // MARK: - Filtering & Queries
    
    /// Get only latest (non-superseded) memories
    public func getLatestMemories() async -> [MemoryNode] {
        return await memoryGraph.getLatestNodes()
    }
    
    /// Get memories by confidence threshold
    public func getMemoriesByConfidence(minConfidence: Float) async -> [MemoryNode] {
        return await memoryGraph.getNodesByConfidence(minConfidence: minConfidence)
    }
    
    /// Get static memories (core facts)
    public func getStaticMemories() async -> [MemoryNode] {
        return await memoryGraph.getStaticMemories()
    }
    
    /// Get dynamic memories (episodic)
    public func getDynamicMemories() async -> [MemoryNode] {
        return await memoryGraph.getDynamicMemories()
    }
    
    /// Search memories by content similarity using cosine similarity
    public func searchMemories(embedding: [Float], topK: Int = 10) async throws -> [MemoryNode] {
        let allMemories = await memoryGraph.getAllNodes()
        
        // Calculate cosine similarity for each memory
        let scored = allMemories.compactMap { memory -> (MemoryNode, Float)? in
            guard !memory.embedding.isEmpty else { return nil }
            let similarity = cosineSimilarity(embedding, memory.embedding)
            return (memory, similarity)
        }
        
        // Sort by similarity and return top K
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
    }
    
    /// Calculate cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        
        var dotProduct: Float = 0.0
        var magnitudeA: Float = 0.0
        var magnitudeB: Float = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }
        
        let magnitude = sqrt(magnitudeA) * sqrt(magnitudeB)
        return magnitude > 0 ? dotProduct / magnitude : 0.0
    }
    
    // MARK: - Persistence Helpers
    
    private func persistMemoryNode(_ node: MemoryNode) async throws {
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }

        let sql = """
        INSERT OR REPLACE INTO memory_nodes (
            id, content, embedding, timestamp, confidence,
            is_latest, is_static, container_tags,
            source, importance, access_count, last_accessed, user_confirmed, entities, topics,
            created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to prepare memory insert: \(message)")
        }

        // CRITICAL: Keep all strings alive during the entire bind + step operation
        // Using SQLITE_TRANSIENT ensures SQLite copies the string data
        let idStr = node.id.uuidString
        let contentStr = node.content
        let timestampStr = ISO8601DateFormatter().string(from: node.timestamp)
        let nowStr = ISO8601DateFormatter().string(from: Date())
        let sourceStr = node.metadata.source.rawValue

        // Pre-encode JSON strings
        let tagsStr = (try? JSONEncoder().encode(node.containerTags))
            .flatMap { String(data: $0, encoding: .utf8) }
        let entitiesStr = (try? JSONEncoder().encode(node.metadata.entities))
            .flatMap { String(data: $0, encoding: .utf8) }
        let topicsStr = (try? JSONEncoder().encode(node.metadata.topics))
            .flatMap { String(data: $0, encoding: .utf8) }
        let lastAccessedStr = node.metadata.lastAccessed
            .map { ISO8601DateFormatter().string(from: $0) }

        // Bind parameters using withCString to ensure pointer validity
        idStr.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
        contentStr.withCString { sqlite3_bind_text(statement, 2, $0, -1, SQLITE_TRANSIENT) }

        // Bind embedding as blob with SQLITE_TRANSIENT
        let embeddingData = node.embedding.withUnsafeBytes { Data($0) }
        embeddingData.withUnsafeBytes { ptr in
            sqlite3_bind_blob(statement, 3, ptr.baseAddress, Int32(embeddingData.count), SQLITE_TRANSIENT)
        }

        timestampStr.withCString { sqlite3_bind_text(statement, 4, $0, -1, SQLITE_TRANSIENT) }
        sqlite3_bind_double(statement, 5, Double(node.confidence))
        sqlite3_bind_int(statement, 6, node.isLatest ? 1 : 0)
        sqlite3_bind_int(statement, 7, node.isStatic ? 1 : 0)

        // Bind container tags as JSON
        if let tagsStr = tagsStr {
            tagsStr.withCString { sqlite3_bind_text(statement, 8, $0, -1, SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 8)
        }

        // Bind individual metadata fields
        sourceStr.withCString { sqlite3_bind_text(statement, 9, $0, -1, SQLITE_TRANSIENT) }
        sqlite3_bind_double(statement, 10, Double(node.metadata.importance))
        sqlite3_bind_int(statement, 11, Int32(node.metadata.accessCount))

        if let lastAccessedStr = lastAccessedStr {
            lastAccessedStr.withCString { sqlite3_bind_text(statement, 12, $0, -1, SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 12)
        }

        sqlite3_bind_int(statement, 13, node.metadata.userConfirmed ? 1 : 0)

        // Bind entities and topics as JSON arrays
        if let entitiesStr = entitiesStr {
            entitiesStr.withCString { sqlite3_bind_text(statement, 14, $0, -1, SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 14)
        }

        if let topicsStr = topicsStr {
            topicsStr.withCString { sqlite3_bind_text(statement, 15, $0, -1, SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 15)
        }

        // Bind created_at and updated_at
        timestampStr.withCString { sqlite3_bind_text(statement, 16, $0, -1, SQLITE_TRANSIENT) }
        nowStr.withCString { sqlite3_bind_text(statement, 17, $0, -1, SQLITE_TRANSIENT) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to insert memory: \(message)")
        }
    }
    
    private func persistRelationship(from sourceId: UUID, relationship: MemoryRelationship) async throws {
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }

        let sql = """
        INSERT OR REPLACE INTO memory_relationships (
            id, source_id, target_id, type, confidence, timestamp
        ) VALUES (?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to prepare relationship insert: \(message)")
        }

        // CRITICAL: Keep all strings alive during the entire bind + step operation
        let relationshipIdStr = UUID().uuidString
        let sourceIdStr = sourceId.uuidString
        let targetIdStr = relationship.targetId.uuidString
        let typeStr = relationship.type.rawValue
        let timestampStr = ISO8601DateFormatter().string(from: Date())

        relationshipIdStr.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
        sourceIdStr.withCString { sqlite3_bind_text(statement, 2, $0, -1, SQLITE_TRANSIENT) }
        targetIdStr.withCString { sqlite3_bind_text(statement, 3, $0, -1, SQLITE_TRANSIENT) }
        typeStr.withCString { sqlite3_bind_text(statement, 4, $0, -1, SQLITE_TRANSIENT) }
        sqlite3_bind_double(statement, 5, Double(relationship.confidence))
        timestampStr.withCString { sqlite3_bind_text(statement, 6, $0, -1, SQLITE_TRANSIENT) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to insert relationship: \(message)")
        }
    }
    
    private func deleteRelationships(for nodeId: UUID) async throws {
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }

        let sql = "DELETE FROM memory_relationships WHERE source_id = ?;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to prepare relationship delete: \(message)")
        }

        let nodeIdStr = nodeId.uuidString
        nodeIdStr.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SwiftMemError.storageError("Failed to delete relationships: \(message)")
        }
    }
    
    private func loadMemoriesIntoGraph() async throws {
        guard let db = db else { return }
        
        let sql = "SELECT id, content, embedding, timestamp, confidence, is_latest, is_static, container_tags, source, importance, access_count, last_accessed, user_confirmed, entities, topics FROM memory_nodes;"
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            print("⚠️ [MemoryGraphStore] Failed to prepare SELECT: \(message)")
            return
        }
        
        var loadedCount = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            // Parse node data
            guard let idString = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: idString)),
                  let contentCString = sqlite3_column_text(statement, 1) else {
                continue
            }
            
            let content = String(cString: contentCString)
            
            // Parse embedding blob
            var embedding: [Float] = []
            if let embeddingBlob = sqlite3_column_blob(statement, 2) {
                let embeddingSize = sqlite3_column_bytes(statement, 2)
                let embeddingData = Data(bytes: embeddingBlob, count: Int(embeddingSize))
                embedding = embeddingData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            }
            
            // Parse timestamp
            var timestamp = Date()
            if let timestampCString = sqlite3_column_text(statement, 3) {
                let timestampString = String(cString: timestampCString)
                if let parsedDate = ISO8601DateFormatter().date(from: timestampString) {
                    timestamp = parsedDate
                }
            }
            
            let confidence = Float(sqlite3_column_double(statement, 4))
            let isLatest = sqlite3_column_int(statement, 5) == 1
            let isStatic = sqlite3_column_int(statement, 6) == 1
            
            // Parse container tags
            var containerTags: [String] = []
            if let tagsCString = sqlite3_column_text(statement, 7) {
                let tagsString = String(cString: tagsCString)
                if let tagsData = tagsString.data(using: .utf8),
                   let tags = try? JSONDecoder().decode([String].self, from: tagsData) {
                    containerTags = tags
                }
            }
            
            // Parse metadata from individual columns
            var source: MemorySource = .conversation
            if let sourceCString = sqlite3_column_text(statement, 8) {
                let sourceString = String(cString: sourceCString)
                source = MemorySource(rawValue: sourceString) ?? .conversation
            }
            
            let importance = Float(sqlite3_column_double(statement, 9))
            let accessCount = Int(sqlite3_column_int(statement, 10))
            
            var lastAccessed: Date? = nil
            if let lastAccessedCString = sqlite3_column_text(statement, 11) {
                let lastAccessedString = String(cString: lastAccessedCString)
                lastAccessed = ISO8601DateFormatter().date(from: lastAccessedString)
            }
            
            let userConfirmed = sqlite3_column_int(statement, 12) == 1
            
            var entities: [String] = []
            if let entitiesCString = sqlite3_column_text(statement, 13) {
                let entitiesString = String(cString: entitiesCString)
                if let entitiesData = entitiesString.data(using: .utf8),
                   let decodedEntities = try? JSONDecoder().decode([String].self, from: entitiesData) {
                    entities = decodedEntities
                }
            }
            
            var topics: [String] = []
            if let topicsCString = sqlite3_column_text(statement, 14) {
                let topicsString = String(cString: topicsCString)
                if let topicsData = topicsString.data(using: .utf8),
                   let decodedTopics = try? JSONDecoder().decode([String].self, from: topicsData) {
                    topics = decodedTopics
                }
            }
            
            let metadata = MemoryMetadata(
                source: source,
                entities: entities,
                topics: topics,
                importance: importance,
                accessCount: accessCount,
                lastAccessed: lastAccessed,
                userConfirmed: userConfirmed
            )
            
            // Create memory node
            let node = MemoryNode(
                id: id,
                content: content,
                embedding: embedding,
                timestamp: timestamp,
                confidence: confidence,
                relationships: [], // Will load relationships separately
                metadata: metadata,
                isLatest: isLatest,
                isStatic: isStatic,
                containerTags: containerTags
            )
            
            await memoryGraph.addNode(node)
            loadedCount += 1
        }
        
        print("💾 [MemoryGraphStore] Loaded \(loadedCount) memories from database")
        
        // Load relationships
        try await loadRelationshipsIntoGraph()
    }
    
    private func loadRelationshipsIntoGraph() async throws {
        guard let db = db else { return }
        
        let sql = "SELECT source_id, target_id, type, confidence FROM memory_relationships;"
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        
        var relationshipCount = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sourceIdString = sqlite3_column_text(statement, 0),
                  let sourceId = UUID(uuidString: String(cString: sourceIdString)),
                  let targetIdString = sqlite3_column_text(statement, 1),
                  let targetId = UUID(uuidString: String(cString: targetIdString)),
                  let typeCString = sqlite3_column_text(statement, 2) else {
                continue
            }
            
            let typeString = String(cString: typeCString)
            let type = RelationType(rawValue: typeString) ?? .relatedTo
            let confidence = Float(sqlite3_column_double(statement, 3))
            
            await memoryGraph.addRelationship(from: sourceId, to: targetId, type: type, confidence: confidence)
            relationshipCount += 1
        }
        
        print("🔗 [MemoryGraphStore] Loaded \(relationshipCount) relationships from database")
    }
    
    // MARK: - Statistics
    
    public func getStatistics() async -> (nodes: Int, relationships: Int, avgDegree: Double) {
        let nodeCount = await memoryGraph.nodeCount()
        let relCount = await memoryGraph.relationshipCount()
        let avgDegree = await memoryGraph.averageDegree()
        return (nodeCount, relCount, avgDegree)
    }
}

// MARK: - Integration with Existing SwiftMem

extension MemoryGraphStore {
    /// Convert existing SwiftMem memories to MemoryNodes
    public func migrateFromVectorStore(vectorStore: VectorStore, embedder: Embedder) async throws {
        // Get all existing memories from VectorStore
        // Convert to MemoryNodes
        // Detect relationships using LLM
        // Add to MemoryGraph
        // This will be implemented when we integrate with existing code
    }
}
