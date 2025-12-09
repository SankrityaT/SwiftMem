//
//  SwiftMemClient.swift
//  SwiftMem
//
//  Created by Sankritya on 12/9/25.
//

import Foundation

// MARK: - Memory Stats

/// Statistics about stored memories
public struct MemoryStats {
    public let totalMemories: Int
    public let totalSessions: Int
    public let storageSize: Int64
    
    public init(totalMemories: Int, totalSessions: Int, storageSize: Int64) {
        self.totalMemories = totalMemories
        self.totalSessions = totalSessions
        self.storageSize = storageSize
    }
}

/// High-level facade over SwiftMem's core components.
///
/// Complete API surface for memory storage, retrieval, sessions,
/// conflict detection, and entity extraction.
public actor SwiftMemClient {
    public let config: SwiftMemConfig
    public let graphStore: GraphStore
    public let vectorStore: VectorStore
    public let embeddingEngine: EmbeddingEngine
    public let retrievalEngine: RetrievalEngine
    public let sessionManager: SessionManager
    public let conflictDetector: ConflictDetector
    private let entityExtractor = EntityExtractor()
    
    // MARK: - Initialization
    
    /// Create a new SwiftMemClient with explicitly constructed components.
    /// After init, call `loadPersistedEmbeddings()` to restore vectors from SQLite.
    public init(
        config: SwiftMemConfig,
        graphStore: GraphStore,
        vectorStore: VectorStore,
        embeddingEngine: EmbeddingEngine
    ) {
        self.config = config
        self.graphStore = graphStore
        self.vectorStore = vectorStore
        self.embeddingEngine = embeddingEngine
        self.retrievalEngine = RetrievalEngine(
            graphStore: graphStore,
            vectorStore: vectorStore,
            embeddingEngine: embeddingEngine,
            config: config
        )
        self.sessionManager = SessionManager(graphStore: graphStore)
        self.conflictDetector = ConflictDetector(
            graphStore: graphStore,
            vectorStore: vectorStore,
            embeddingEngine: embeddingEngine
        )
    }
    
    /// Convenience factory that builds in-process stores on disk using the
    /// given config and a provided Embedder implementation.
    /// Automatically loads persisted embeddings from SQLite.
    public static func makeOnDisk(
        config: SwiftMemConfig,
        embedder: Embedder
    ) async throws -> SwiftMemClient {
        let graphStore = try await GraphStore.create(config: config)
        let vectorStore = VectorStore(config: config)
        let embeddingEngine = EmbeddingEngine(embedder: embedder, config: config)
        let client = SwiftMemClient(
            config: config,
            graphStore: graphStore,
            vectorStore: vectorStore,
            embeddingEngine: embeddingEngine
        )
        // Load persisted embeddings into VectorStore
        try await client.loadPersistedEmbeddings()
        return client
    }
    
    /// Load all persisted embeddings from SQLite into VectorStore.
    /// Call this after init if not using makeOnDisk factory.
    public func loadPersistedEmbeddings() async throws {
        let embeddings = try await graphStore.getAllEmbeddings()
        for (nodeId, vector) in embeddings {
            try await vectorStore.addVector(vector, for: nodeId)
        }
        print("✅ [SwiftMemClient] Loaded \(embeddings.count) persisted embeddings")
    }
    
    // MARK: - Core Storage
    
    /// Store a conversation turn as a memory, optionally associated with a session.
    @discardableResult
    public func storeMessage(
        text: String,
        role: MessageRole,
        sessionId: SessionID? = nil,
        metadata: [String: MetadataValue] = [:]
    ) async throws -> NodeID {
        var meta = metadata
        if let sid = sessionId {
            meta["session_id"] = .string(sid.value.uuidString)
        }
        meta["role"] = .string(role.rawValue)
        
        let node = Node(
            content: text,
            type: .episodic,
            metadata: meta
        )
        
        try await graphStore.storeNode(node)
        let embedding = try await embeddingEngine.embed(node.content)
        try await vectorStore.addVector(embedding, for: node.id)
        
        // Persist embedding to SQLite for recovery on app restart
        try await graphStore.storeEmbedding(embedding, for: node.id)
        
        return node.id
    }
    
    /// Store memory with automatic conflict detection and resolution.
    @discardableResult
    public func storeMemoryWithConflictDetection(
        text: String,
        type: MemoryType = .semantic,
        metadata: [String: MetadataValue] = [:],
        autoResolve: Bool = true
    ) async throws -> NodeID {
        let node = Node(content: text, type: type, metadata: metadata)
        
        // Detect conflicts using entity extraction
        let conflicts = try await conflictDetector.detectConflictsWithEntities(for: node)
        
        if !conflicts.isEmpty && autoResolve {
            try await conflictDetector.resolveConflicts(conflicts)
        }
        
        // Store node
        try await graphStore.storeNode(node)
        let embedding = try await embeddingEngine.embed(node.content)
        try await vectorStore.addVector(embedding, for: node.id)
        try await graphStore.storeEmbedding(embedding, for: node.id)
        
        return node.id
    }
    
    /// Store an entire conversation as memories.
    @discardableResult
    public func storeConversation(
        messages: [(text: String, role: MessageRole)],
        sessionId: SessionID
    ) async throws -> [NodeID] {
        var nodeIds: [NodeID] = []
        
        for (index, msg) in messages.enumerated() {
            let node = Node(
                content: msg.text,
                type: .episodic,
                metadata: [
                    "session_id": .string(sessionId.value.uuidString),
                    "role": .string(msg.role.rawValue),
                    "message_index": .int(index)
                ]
            )
            
            try await sessionManager.storeMemory(
                node,
                sessionId: sessionId,
                messageIndex: index
            )
            
            let embedding = try await embeddingEngine.embed(node.content)
            try await vectorStore.addVector(embedding, for: node.id)
            try await graphStore.storeEmbedding(embedding, for: node.id)
            
            nodeIds.append(node.id)
        }
        
        return nodeIds
    }
    
    /// Delete a specific memory.
    public func deleteMemory(_ nodeId: NodeID) async throws {
        try await graphStore.deleteNode(nodeId, mode: .cascade)
        await vectorStore.removeVector(for: nodeId)
    }
    
    // MARK: - Retrieval
    
    /// Retrieve relevant context for a query, returning formatted context string.
    public func retrieveContext(
        for query: String,
        maxResults: Int? = nil,
        strategy: RetrievalStrategy? = nil
    ) async throws -> (formatted: String, nodes: [ScoredNode]) {
        let result = try await retrievalEngine.query(
            query,
            maxResults: maxResults,
            strategy: strategy,
            filters: nil
        )
        return (formatted: result.formattedContext, nodes: result.nodes)
    }
    
    /// Query across specific sessions.
    public func queryAcrossSessions(
        _ query: String,
        sessionIds: [SessionID],
        maxResults: Int = 10
    ) async throws -> [(nodeId: NodeID, score: Float)] {
        let sessionQuery = SessionQuery(sessionIds: sessionIds)
        let sessionNodes = try await sessionManager.getMemories(query: sessionQuery)
        
        // Filter by vector similarity
        let embedding = try await embeddingEngine.embed(query)
        let results = try await vectorStore.search(query: embedding, k: maxResults * 2)
        
        // Return only nodes from specified sessions
        let sessionNodeIds = Set(sessionNodes.map { $0.id })
        return Array(results.filter { sessionNodeIds.contains($0.nodeId) }.prefix(maxResults))
    }
    
    /// Get session timeline grouped by date.
    public func getTimeline(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [Date: [SessionID]] {
        return try await sessionManager.getSessionTimeline(from: startDate, to: endDate)
    }
    
    // MARK: - Sessions
    
    /// Start a new session.
    public func startSession(type: SessionType = .chat) async -> Session {
        return await sessionManager.startSession(type: type)
    }
    
    /// End a session.
    public func endSession(_ sessionId: SessionID) async {
        await sessionManager.endSession(sessionId)
    }
    
    /// Get all memories from a session.
    public func getSessionMemories(sessionId: SessionID) async throws -> [Node] {
        return try await sessionManager.getMemories(fromSession: sessionId)
    }
    
    // MARK: - Entity Extraction
    
    /// Extract structured facts from text using pattern matching.
    public func extractFacts(from text: String) async -> [ExtractedFact] {
        return await entityExtractor.extractFacts(from: text)
    }
    
    // MARK: - Analytics
    
    /// Get memory statistics.
    public func getMemoryStats() async throws -> MemoryStats {
        let nodeCount = try await graphStore.getNodeCount()
        let sessions = try await sessionManager.getSessions(
            from: Date.distantPast,
            to: Date()
        )
        
        return MemoryStats(
            totalMemories: nodeCount,
            totalSessions: sessions.count,
            storageSize: try await graphStore.getDatabaseSize()
        )
    }
    
    // MARK: - Maintenance
    
    /// Clear all memories (use with caution).
    public func clearAllMemories() async throws {
        try await graphStore.clearAll()
        await vectorStore.clearAll()
    }
}
