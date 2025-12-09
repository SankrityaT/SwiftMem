//
//  SwiftMemClient.swift
//  SwiftMem
//
//  Created by Sankritya on 12/9/25.
//

import Foundation

/// High-level facade over SwiftMem's core components.
///
/// This is intentionally minimal: it wraps GraphStore, VectorStore,
/// EmbeddingEngine, and RetrievalEngine behind a single type so apps
/// can use SwiftMem without thinking about storage or retrieval internals.
public actor SwiftMemClient {
    public let config: SwiftMemConfig
    public let graphStore: GraphStore
    public let vectorStore: VectorStore
    public let embeddingEngine: EmbeddingEngine
    public let retrievalEngine: RetrievalEngine
    public let sessionManager: SessionManager
    
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
    
    // MARK: - Public API
    
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
}
