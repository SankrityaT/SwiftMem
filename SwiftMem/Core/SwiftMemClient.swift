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
    public static func makeOnDisk(
        config: SwiftMemConfig,
        embedder: Embedder
    ) async throws -> SwiftMemClient {
        let graphStore = try await GraphStore.create(config: config)
        let vectorStore = VectorStore(config: config)
        let embeddingEngine = EmbeddingEngine(embedder: embedder, config: config)
        return SwiftMemClient(
            config: config,
            graphStore: graphStore,
            vectorStore: vectorStore,
            embeddingEngine: embeddingEngine
        )
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
        if let sid = sessionId?.rawValue {
            meta["session_id"] = .string(sid)
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
        
        return node.id
    }
    
    /// Retrieve relevant context for a query, returning SwiftMem's
    /// structured ConversationContext for direct use in prompts.
    public func retrieveContext(
        for query: String,
        maxResults: Int? = nil,
        strategy: RetrievalStrategy? = nil
    ) async throws -> ConversationContext {
        let result = try await retrievalEngine.query(
            query,
            maxResults: maxResults,
            strategy: strategy,
            filters: nil
        )
        return result.context
    }
}
