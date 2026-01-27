//
//  AdvancedGraphStore.swift
//  SwiftMem
//
//  Enhanced storage with facts, entities, and goal-centric tables
//  Extends existing MemoryGraphStore with SOTA architecture
//

import Foundation
import SQLite3

/// SQLITE_TRANSIENT tells SQLite to make its own copy of the string
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Enhanced graph store with SOTA architecture tables
public actor AdvancedGraphStore {

    // MARK: - Properties

    private var db: OpaquePointer?
    private let dbPath: URL

    // Component stores
    private let factIndex: FactIndex
    private let contradictionEngine: FactContradictionEngine
    private let entityExtractor: AdvancedEntityExtractor
    private let temporalExtractor: TemporalExtractor
    private let goalManager: GoalMemoryManager

    // MARK: - Initialization

    public static func create(config: SwiftMemConfig) async throws -> AdvancedGraphStore {
        let store = AdvancedGraphStore(config: config)
        try await store.initializeDatabase()
        try await store.initializeAdvancedSchema()
        try await store.loadDataIntoMemory()
        return store
    }

    private init(config: SwiftMemConfig) {
        // Determine database path
        let filename = "swiftmem_advanced.db"
        let directory: URL

        switch config.storageLocation {
        case .applicationSupport:
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("SwiftMem", isDirectory: true)
        case .documents:
            directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("SwiftMem", isDirectory: true)
        case .caches:
            directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("SwiftMem", isDirectory: true)
        case .custom(let url):
            directory = url
        }

        // Create directory if needed
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        self.dbPath = directory.appendingPathComponent(filename)
        self.factIndex = FactIndex()
        self.contradictionEngine = FactContradictionEngine()
        self.entityExtractor = AdvancedEntityExtractor()
        self.temporalExtractor = TemporalExtractor()
        self.goalManager = GoalMemoryManager()
    }

    // MARK: - Database Initialization

    private func initializeDatabase() async throws {
        var db: OpaquePointer?
        let result = sqlite3_open(dbPath.path, &db)

        guard result == SQLITE_OK, let database = db else {
            throw SwiftMemError.storageError("Failed to open database: \(result)")
        }

        self.db = database

        // Enable WAL mode for better concurrency
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try execute("PRAGMA foreign_keys = ON;")

        print("✅ [AdvancedGraphStore] Database opened at \(dbPath.path)")
    }

    private func initializeAdvancedSchema() async throws {
        let schemas = [
            // Facts table
            """
            CREATE TABLE IF NOT EXISTS facts (
                id TEXT PRIMARY KEY,
                memory_id TEXT NOT NULL,
                subject TEXT NOT NULL,
                predicate TEXT NOT NULL,
                object TEXT NOT NULL,
                predicate_category TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 0.8,
                valid_from TEXT,
                valid_until TEXT,
                detection_method TEXT NOT NULL,
                created_at TEXT NOT NULL,
                user_id TEXT NOT NULL
            );
            """,

            // Facts indexes
            """
            CREATE INDEX IF NOT EXISTS idx_facts_memory ON facts(memory_id);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_facts_subject ON facts(subject);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_facts_lookup ON facts(subject, predicate);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_facts_category ON facts(predicate_category);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_facts_user ON facts(user_id);
            """,

            // Entities table
            """
            CREATE TABLE IF NOT EXISTS entities (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                normalized_name TEXT NOT NULL,
                type TEXT NOT NULL,
                aliases TEXT,
                first_mentioned TEXT NOT NULL,
                mention_count INTEGER NOT NULL DEFAULT 1,
                related_fact_ids TEXT,
                user_id TEXT NOT NULL
            );
            """,

            // Entities indexes
            """
            CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(normalized_name);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(type);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_entities_user ON entities(user_id);
            """,
            """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_entities_unique ON entities(normalized_name, type, user_id);
            """,

            // Goal clusters table
            """
            CREATE TABLE IF NOT EXISTS goal_clusters (
                id TEXT PRIMARY KEY,
                goal_memory_id TEXT NOT NULL,
                goal_content TEXT NOT NULL,
                created_at TEXT NOT NULL,
                progress_ids TEXT,
                blocker_ids TEXT,
                motivation_ids TEXT,
                insight_ids TEXT,
                emotional_trajectory TEXT,
                user_id TEXT NOT NULL
            );
            """,

            // Goal clusters indexes
            """
            CREATE INDEX IF NOT EXISTS idx_goals_user ON goal_clusters(user_id);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_goals_memory ON goal_clusters(goal_memory_id);
            """,

            // Enhanced memory metadata table (extends existing)
            """
            CREATE TABLE IF NOT EXISTS memory_metadata_v2 (
                memory_id TEXT PRIMARY KEY,
                layer TEXT NOT NULL DEFAULT 'shortTerm',
                temporal_info TEXT,
                emotional_valence TEXT,
                useful_retrievals INTEGER NOT NULL DEFAULT 0,
                total_retrievals INTEGER NOT NULL DEFAULT 0,
                superseded_by TEXT,
                goal_id TEXT
            );
            """,

            // Memory to goal links
            """
            CREATE TABLE IF NOT EXISTS memory_goal_links (
                id TEXT PRIMARY KEY,
                memory_id TEXT NOT NULL,
                goal_id TEXT NOT NULL,
                relationship_type TEXT NOT NULL,
                relevance REAL NOT NULL,
                created_at TEXT NOT NULL
            );
            """,

            """
            CREATE INDEX IF NOT EXISTS idx_memory_goal_memory ON memory_goal_links(memory_id);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_memory_goal_goal ON memory_goal_links(goal_id);
            """
        ]

        for schema in schemas {
            try execute(schema)
        }

        print("✅ [AdvancedGraphStore] Advanced schema initialized")
    }

    // MARK: - Fact Operations

    /// Store a fact
    public func storeFact(_ fact: Fact, userId: String) async throws {
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }

        let sql = """
        INSERT OR REPLACE INTO facts (
            id, memory_id, subject, predicate, object, predicate_category,
            confidence, valid_from, valid_until, detection_method, created_at, user_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare fact insert")
        }

        let idStr = fact.id.uuidString
        let memoryIdStr = fact.sourceMemoryId.uuidString
        let categoryStr = fact.predicateCategory.rawValue
        let methodStr = fact.detectionMethod.rawValue
        let nowStr = ISO8601DateFormatter().string(from: Date())
        let validFromStr = fact.validFrom.map { ISO8601DateFormatter().string(from: $0) }
        let validUntilStr = fact.validUntil.map { ISO8601DateFormatter().string(from: $0) }

        idStr.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
        memoryIdStr.withCString { sqlite3_bind_text(statement, 2, $0, -1, SQLITE_TRANSIENT) }
        fact.subject.withCString { sqlite3_bind_text(statement, 3, $0, -1, SQLITE_TRANSIENT) }
        fact.predicate.withCString { sqlite3_bind_text(statement, 4, $0, -1, SQLITE_TRANSIENT) }
        fact.object.withCString { sqlite3_bind_text(statement, 5, $0, -1, SQLITE_TRANSIENT) }
        categoryStr.withCString { sqlite3_bind_text(statement, 6, $0, -1, SQLITE_TRANSIENT) }
        sqlite3_bind_double(statement, 7, Double(fact.confidence))

        if let validFromStr = validFromStr {
            validFromStr.withCString { sqlite3_bind_text(statement, 8, $0, -1, SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 8)
        }

        if let validUntilStr = validUntilStr {
            validUntilStr.withCString { sqlite3_bind_text(statement, 9, $0, -1, SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 9)
        }

        methodStr.withCString { sqlite3_bind_text(statement, 10, $0, -1, SQLITE_TRANSIENT) }
        nowStr.withCString { sqlite3_bind_text(statement, 11, $0, -1, SQLITE_TRANSIENT) }
        userId.withCString { sqlite3_bind_text(statement, 12, $0, -1, SQLITE_TRANSIENT) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SwiftMemError.storageError("Failed to insert fact")
        }

        // Add to index
        await factIndex.addFact(fact)
    }

    /// Get facts for a subject
    public func getFactsForSubject(_ subject: String, userId: String) async throws -> [Fact] {
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }

        let sql = "SELECT * FROM facts WHERE subject = ? AND user_id = ?;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare fact query")
        }

        let normalizedSubject = subject.lowercased()
        normalizedSubject.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
        userId.withCString { sqlite3_bind_text(statement, 2, $0, -1, SQLITE_TRANSIENT) }

        var facts: [Fact] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            if let fact = parseFact(from: statement) {
                facts.append(fact)
            }
        }

        return facts
    }

    /// Check for contradictions when adding new facts
    public func checkAndResolveContradictions(
        newFacts: [Fact],
        userId: String
    ) async throws -> [ContradictionResult] {
        // Get existing facts for the same subjects
        var existingFacts: [Fact] = []
        let subjects = Set(newFacts.map { $0.subject })

        for subject in subjects {
            let facts = try await getFactsForSubject(subject, userId: userId)
            existingFacts.append(contentsOf: facts)
        }

        // Check for contradictions
        let results = await contradictionEngine.checkContradictions(
            newFacts: newFacts,
            existingFacts: existingFacts
        )

        // Handle resolutions
        for result in results where result.resolution == .newSupersedes {
            if let oldFact = result.existingFact {
                // Mark old fact as superseded (could add a superseded_by column)
                try await markFactSuperseded(oldFact.id)
            }
        }

        return results
    }

    private func markFactSuperseded(_ factId: UUID) async throws {
        // Remove from active index
        await factIndex.removeFact(factId)

        // Could also update a superseded flag in DB if needed
    }

    // MARK: - Entity Operations

    /// Store an entity
    public func storeEntity(_ entity: TrackedEntity) async throws {
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }

        // Check if entity already exists
        let existing = try await getEntity(name: entity.normalizedName, type: entity.type, userId: entity.userId)

        if var existingEntity = existing {
            // Update existing entity
            existingEntity.mentionCount += 1
            existingEntity.aliases.formUnion(entity.aliases)
            try await updateEntity(existingEntity)
            return
        }

        // Insert new entity
        let sql = """
        INSERT INTO entities (
            id, name, normalized_name, type, aliases,
            first_mentioned, mention_count, related_fact_ids, user_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare entity insert")
        }

        let idStr = entity.id.uuidString
        let typeStr = entity.type.rawValue
        let aliasesStr = (try? JSONEncoder().encode(Array(entity.aliases)))
            .flatMap { String(data: $0, encoding: .utf8) }
        let firstMentionedStr = ISO8601DateFormatter().string(from: entity.firstMentioned)
        let relatedFactsStr = (try? JSONEncoder().encode(entity.relatedFactIds.map { $0.uuidString }))
            .flatMap { String(data: $0, encoding: .utf8) }

        idStr.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
        entity.name.withCString { sqlite3_bind_text(statement, 2, $0, -1, SQLITE_TRANSIENT) }
        entity.normalizedName.withCString { sqlite3_bind_text(statement, 3, $0, -1, SQLITE_TRANSIENT) }
        typeStr.withCString { sqlite3_bind_text(statement, 4, $0, -1, SQLITE_TRANSIENT) }

        if let aliasesStr = aliasesStr {
            aliasesStr.withCString { sqlite3_bind_text(statement, 5, $0, -1, SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 5)
        }

        firstMentionedStr.withCString { sqlite3_bind_text(statement, 6, $0, -1, SQLITE_TRANSIENT) }
        sqlite3_bind_int(statement, 7, Int32(entity.mentionCount))

        if let relatedFactsStr = relatedFactsStr {
            relatedFactsStr.withCString { sqlite3_bind_text(statement, 8, $0, -1, SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 8)
        }

        entity.userId.withCString { sqlite3_bind_text(statement, 9, $0, -1, SQLITE_TRANSIENT) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SwiftMemError.storageError("Failed to insert entity")
        }
    }

    private func getEntity(name: String, type: TrackedEntityType, userId: String) async throws -> TrackedEntity? {
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }

        let sql = "SELECT * FROM entities WHERE normalized_name = ? AND type = ? AND user_id = ?;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare entity query")
        }

        name.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
        type.rawValue.withCString { sqlite3_bind_text(statement, 2, $0, -1, SQLITE_TRANSIENT) }
        userId.withCString { sqlite3_bind_text(statement, 3, $0, -1, SQLITE_TRANSIENT) }

        if sqlite3_step(statement) == SQLITE_ROW {
            return parseEntity(from: statement)
        }

        return nil
    }

    private func updateEntity(_ entity: TrackedEntity) async throws {
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }

        let sql = """
        UPDATE entities SET
            aliases = ?, mention_count = ?, related_fact_ids = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare entity update")
        }

        let aliasesStr = (try? JSONEncoder().encode(Array(entity.aliases)))
            .flatMap { String(data: $0, encoding: .utf8) }
        let relatedFactsStr = (try? JSONEncoder().encode(entity.relatedFactIds.map { $0.uuidString }))
            .flatMap { String(data: $0, encoding: .utf8) }
        let idStr = entity.id.uuidString

        if let aliasesStr = aliasesStr {
            aliasesStr.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 1)
        }

        sqlite3_bind_int(statement, 2, Int32(entity.mentionCount))

        if let relatedFactsStr = relatedFactsStr {
            relatedFactsStr.withCString { sqlite3_bind_text(statement, 3, $0, -1, SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 3)
        }

        idStr.withCString { sqlite3_bind_text(statement, 4, $0, -1, SQLITE_TRANSIENT) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SwiftMemError.storageError("Failed to update entity")
        }
    }

    // MARK: - Goal Operations

    /// Store a goal cluster
    public func storeGoalCluster(_ cluster: GoalCluster) async throws {
        guard let db = db else {
            throw SwiftMemError.storageError("Database not initialized")
        }

        let sql = """
        INSERT OR REPLACE INTO goal_clusters (
            id, goal_memory_id, goal_content, created_at,
            progress_ids, blocker_ids, motivation_ids, insight_ids,
            emotional_trajectory, user_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SwiftMemError.storageError("Failed to prepare goal insert")
        }

        let encoder = JSONEncoder()
        let idStr = cluster.id.uuidString
        let goalMemoryIdStr = cluster.goalMemoryId.uuidString
        let createdAtStr = ISO8601DateFormatter().string(from: cluster.createdAt)
        let progressStr = (try? encoder.encode(cluster.progressMemoryIds.map { $0.uuidString }))
            .flatMap { String(data: $0, encoding: .utf8) }
        let blockerStr = (try? encoder.encode(cluster.blockerMemoryIds.map { $0.uuidString }))
            .flatMap { String(data: $0, encoding: .utf8) }
        let motivationStr = (try? encoder.encode(cluster.motivationMemoryIds.map { $0.uuidString }))
            .flatMap { String(data: $0, encoding: .utf8) }
        let insightStr = (try? encoder.encode(cluster.insightMemoryIds.map { $0.uuidString }))
            .flatMap { String(data: $0, encoding: .utf8) }
        let trajectoryStr = (try? encoder.encode(cluster))
            .flatMap { String(data: $0, encoding: .utf8) }

        idStr.withCString { sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT) }
        goalMemoryIdStr.withCString { sqlite3_bind_text(statement, 2, $0, -1, SQLITE_TRANSIENT) }
        cluster.goalContent.withCString { sqlite3_bind_text(statement, 3, $0, -1, SQLITE_TRANSIENT) }
        createdAtStr.withCString { sqlite3_bind_text(statement, 4, $0, -1, SQLITE_TRANSIENT) }

        if let str = progressStr { str.withCString { sqlite3_bind_text(statement, 5, $0, -1, SQLITE_TRANSIENT) } }
        else { sqlite3_bind_null(statement, 5) }

        if let str = blockerStr { str.withCString { sqlite3_bind_text(statement, 6, $0, -1, SQLITE_TRANSIENT) } }
        else { sqlite3_bind_null(statement, 6) }

        if let str = motivationStr { str.withCString { sqlite3_bind_text(statement, 7, $0, -1, SQLITE_TRANSIENT) } }
        else { sqlite3_bind_null(statement, 7) }

        if let str = insightStr { str.withCString { sqlite3_bind_text(statement, 8, $0, -1, SQLITE_TRANSIENT) } }
        else { sqlite3_bind_null(statement, 8) }

        if let str = trajectoryStr { str.withCString { sqlite3_bind_text(statement, 9, $0, -1, SQLITE_TRANSIENT) } }
        else { sqlite3_bind_null(statement, 9) }

        cluster.userId.withCString { sqlite3_bind_text(statement, 10, $0, -1, SQLITE_TRANSIENT) }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SwiftMemError.storageError("Failed to insert goal cluster")
        }
    }

    // MARK: - Helper Methods

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

    private func parseFact(from statement: OpaquePointer?) -> Fact? {
        guard let statement = statement,
              let idCStr = sqlite3_column_text(statement, 0),
              let memoryIdCStr = sqlite3_column_text(statement, 1),
              let subjectCStr = sqlite3_column_text(statement, 2),
              let predicateCStr = sqlite3_column_text(statement, 3),
              let objectCStr = sqlite3_column_text(statement, 4),
              let categoryCStr = sqlite3_column_text(statement, 5) else {
            return nil
        }

        guard let id = UUID(uuidString: String(cString: idCStr)),
              let memoryId = UUID(uuidString: String(cString: memoryIdCStr)),
              let category = PredicateCategory(rawValue: String(cString: categoryCStr)) else {
            return nil
        }

        let confidence = Float(sqlite3_column_double(statement, 6))

        var validFrom: Date? = nil
        if let validFromCStr = sqlite3_column_text(statement, 7) {
            validFrom = ISO8601DateFormatter().date(from: String(cString: validFromCStr))
        }

        var validUntil: Date? = nil
        if let validUntilCStr = sqlite3_column_text(statement, 8) {
            validUntil = ISO8601DateFormatter().date(from: String(cString: validUntilCStr))
        }

        var detectionMethod: FactDetectionMethod = .patternMatch
        if let methodCStr = sqlite3_column_text(statement, 9),
           let method = FactDetectionMethod(rawValue: String(cString: methodCStr)) {
            detectionMethod = method
        }

        return Fact(
            id: id,
            subject: String(cString: subjectCStr),
            predicate: String(cString: predicateCStr),
            object: String(cString: objectCStr),
            predicateCategory: category,
            confidence: confidence,
            sourceMemoryId: memoryId,
            validFrom: validFrom,
            validUntil: validUntil,
            detectionMethod: detectionMethod
        )
    }

    private func parseEntity(from statement: OpaquePointer?) -> TrackedEntity? {
        guard let statement = statement,
              let idCStr = sqlite3_column_text(statement, 0),
              let nameCStr = sqlite3_column_text(statement, 1),
              let typeCStr = sqlite3_column_text(statement, 3),
              let userIdCStr = sqlite3_column_text(statement, 8) else {
            return nil
        }

        guard let id = UUID(uuidString: String(cString: idCStr)),
              let type = TrackedEntityType(rawValue: String(cString: typeCStr)) else {
            return nil
        }

        var aliases: Set<String> = []
        if let aliasesCStr = sqlite3_column_text(statement, 4) {
            let aliasesStr = String(cString: aliasesCStr)
            if let data = aliasesStr.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                aliases = Set(decoded)
            }
        }

        var firstMentioned = Date()
        if let dateCStr = sqlite3_column_text(statement, 5) {
            if let date = ISO8601DateFormatter().date(from: String(cString: dateCStr)) {
                firstMentioned = date
            }
        }

        let mentionCount = Int(sqlite3_column_int(statement, 6))

        return TrackedEntity(
            id: id,
            name: String(cString: nameCStr),
            type: type,
            aliases: aliases,
            firstMentioned: firstMentioned,
            mentionCount: mentionCount,
            userId: String(cString: userIdCStr)
        )
    }

    private func loadDataIntoMemory() async throws {
        // Load facts into index
        guard let db = db else { return }

        let sql = "SELECT * FROM facts;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }

        var factCount = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            if let fact = parseFact(from: statement) {
                await factIndex.addFact(fact)
                factCount += 1
            }
        }

        print("📊 [AdvancedGraphStore] Loaded \(factCount) facts into index")
    }

    // MARK: - Public Accessors

    /// Get the fact index for direct queries
    public func getFactIndex() -> FactIndex {
        return factIndex
    }

    /// Get the contradiction engine
    public func getContradictionEngine() -> FactContradictionEngine {
        return contradictionEngine
    }

    /// Get the entity extractor
    public func getEntityExtractor() -> AdvancedEntityExtractor {
        return entityExtractor
    }

    /// Get the temporal extractor
    public func getTemporalExtractor() -> TemporalExtractor {
        return temporalExtractor
    }

    /// Get the goal manager
    public func getGoalManager() -> GoalMemoryManager {
        return goalManager
    }
}
