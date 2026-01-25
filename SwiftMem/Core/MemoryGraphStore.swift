//
//  MemoryGraphStore.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation
import SQLite3

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
        try await store.initializeMemorySchema()
        try await store.loadMemoriesIntoGraph()
        
        return store
    }
    
    private init(graphStore: GraphStore, memoryGraph: MemoryGraph) {
        self.graphStore = graphStore
        self.memoryGraph = memoryGraph
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
        
        // Execute schema creation (would need access to db pointer from GraphStore)
        // For now, this is a placeholder - we'll integrate with GraphStore's execute method
    }
    
    // MARK: - Memory Operations
    
    /// Add a memory node
    public func addMemory(_ node: MemoryNode) async throws {
        // Add to in-memory graph
        await memoryGraph.addNode(node)
        
        // Persist to database
        try await persistMemoryNode(node)
        
        // Persist relationships
        for relationship in node.relationships {
            try await persistRelationship(from: node.id, relationship: relationship)
        }
    }
    
    /// Update a memory node
    public func updateMemory(_ node: MemoryNode) async throws {
        await memoryGraph.updateNode(node)
        try await persistMemoryNode(node)
        
        // Delete old relationships and add new ones
        try await deleteRelationships(for: node.id)
        for relationship in node.relationships {
            try await persistRelationship(from: node.id, relationship: relationship)
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
        try await persistRelationship(from: sourceId, relationship: relationship)
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
        // Convert to SQL INSERT/UPDATE
        // This would use GraphStore's execute method
        // Placeholder for now
    }
    
    private func persistRelationship(from sourceId: UUID, relationship: MemoryRelationship) async throws {
        // Convert to SQL INSERT
        // Placeholder for now
    }
    
    private func deleteRelationships(for nodeId: UUID) async throws {
        // Delete all relationships for a node
        // Placeholder for now
    }
    
    private func loadMemoriesIntoGraph() async throws {
        // Load all memory nodes from database into MemoryGraph
        // Placeholder for now
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
