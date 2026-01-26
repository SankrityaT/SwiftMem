//
//  SwiftMemAPI.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//  Simple public API for SwiftMem
//

import Foundation

/// Simple, clean API for SwiftMem
/// Usage:
/// ```
/// let memory = SwiftMemAPI.shared
/// 
/// // Add memory
/// try await memory.add(content: "I love pizza", userId: "user123")
/// 
/// // Search memories
/// let results = try await memory.search(query: "food preferences", userId: "user123")
/// ```
public actor SwiftMemAPI {
    
    public static let shared = SwiftMemAPI()
    
    private var memoryGraphStore: MemoryGraphStore?
    private var userProfileManager: UserProfileManager?
    private var memoryExtractor: MemoryExtractor?
    private var hybridSearch: HybridSearch?
    private var reranker: Reranker?
    private var memoryDecay: MemoryDecay?
    private var relationshipDetector: RelationshipDetector?
    private var embedder: Embedder?
    private var config: SwiftMemConfig
    
    // Phase 7 & 8: Consolidation and Batch Operations
    private var memoryConsolidator: MemoryConsolidator?
    private var batchOperations: BatchOperations?
    
    // Integration with existing components
    private var graphStore: GraphStore?
    private var vectorStore: VectorStore?
    private var embeddingEngine: EmbeddingEngine?
    private var retrievalEngine: RetrievalEngine?
    
    private var isInitialized = false
    
    private init() {
        self.config = .default
    }
    
    // MARK: - Initialization
    
    /// Initialize SwiftMem (call once at app startup)
    public func initialize(config: SwiftMemConfig = .default, embedder: Embedder? = nil) async throws {
        guard !isInitialized else { return }
        
        // Use NLEmbedding by default
        self.embedder = embedder ?? NLEmbedder()
        
        // Update config to match embedder dimensions
        var updatedConfig = config
        updatedConfig.embeddingDimensions = self.embedder!.dimensions
        self.config = updatedConfig
        
        // Initialize GraphStore ONCE (shared by both old and new components)
        let sharedGraphStore = try await GraphStore.create(config: updatedConfig)
        
        // Initialize existing components (for compatibility)
        self.graphStore = sharedGraphStore
        self.vectorStore = VectorStore(config: updatedConfig)
        self.embeddingEngine = EmbeddingEngine(embedder: self.embedder!, config: updatedConfig)
        
        // Initialize new Memory Graph components - REUSE the same GraphStore
        self.memoryGraphStore = try await MemoryGraphStore.create(config: updatedConfig, graphStore: sharedGraphStore)
        self.userProfileManager = UserProfileManager(memoryGraphStore: memoryGraphStore!)
        self.relationshipDetector = RelationshipDetector(config: updatedConfig)
        self.memoryExtractor = MemoryExtractor(config: updatedConfig, relationshipDetector: relationshipDetector!)
        self.hybridSearch = HybridSearch(memoryGraphStore: memoryGraphStore!, config: updatedConfig)
        self.reranker = Reranker(config: updatedConfig)
        self.memoryDecay = MemoryDecay(memoryGraphStore: memoryGraphStore!, config: updatedConfig)
        
        // Phase 7 & 8: Initialize consolidator and batch operations
        self.memoryConsolidator = MemoryConsolidator()
        self.batchOperations = BatchOperations(embedder: self.embedder!, relationshipDetector: relationshipDetector!)
        
        // Create integrated RetrievalEngine
        self.retrievalEngine = RetrievalEngine(
            graphStore: graphStore!,
            vectorStore: vectorStore!,
            embeddingEngine: embeddingEngine!,
            config: updatedConfig
        )
        
        // Start background decay process
        print("⏰ [SwiftMemAPI] Starting memory decay background process...")
        Task {
            await memoryDecay?.startScheduledDecay()
            print("✅ [SwiftMemAPI] Memory decay process started")
        }
        
        isInitialized = true
        print("✅ [SwiftMemAPI] Initialization complete - all components wired")
    }
    
    // MARK: - Simple Public API
    
    /// Add a memory (simple one-liner)
    public func add(content: String, userId: String) async throws {
        try await add(content: content, userId: userId, metadata: nil, containerTags: [])
    }
    
    /// Add a memory with metadata and container tags
    public func add(
        content: String,
        userId: String,
        metadata: [String: Any]?,
        containerTags: [String] = [],
        skipRelationships: Bool = false
    ) async throws {
        guard let embedder = embedder, let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        // Generate embedding
        let embedding = try await embedder.embed(content)
        
        // Create memory node
        let memory = MemoryNode(
            content: content,
            embedding: embedding,
            metadata: MemoryMetadata(
                source: .userInput,
                importance: 0.7
            ),
            containerTags: containerTags
        )
        
        // Detect relationships with existing memories (skip during bulk operations to prevent DB conflicts)
        var relationships: [DetectedRelationship] = []
        if !skipRelationships {
            let existingMemories = await store.getAllMemories()
            print("🔗 [SwiftMemAPI] Detecting relationships with \(existingMemories.count) existing memories...")
            relationships = try await relationshipDetector?.detectRelationships(
                newMemory: memory,
                existingMemories: existingMemories
            ) ?? []
            print("🔗 [SwiftMemAPI] Found \(relationships.count) relationships")
        }
        
        // Add relationships to memory
        var memoryWithRelations = memory
        for relationship in relationships {
            print("  → \(relationship.type): \(relationship.targetId.uuidString.prefix(8))... (confidence: \(relationship.confidence))")
            memoryWithRelations.addRelationship(MemoryRelationship(
                type: relationship.type,
                targetId: relationship.targetId,
                confidence: relationship.confidence
            ))
        }
        
        // Classify as static or dynamic BEFORE storing
        let isStatic = await userProfileManager?.classifyMemory(memoryWithRelations, userId: userId) ?? false
        print("🏷️ [SwiftMemAPI] Classified as: \(isStatic ? "static" : "dynamic")")
        
        // Update memory with classification
        var finalMemory = memoryWithRelations
        finalMemory.isStatic = isStatic
        
        // Store memory in MemoryGraphStore with classification
        try await store.addMemory(finalMemory)
        print("💾 [SwiftMemAPI] Stored memory with \(finalMemory.relationships.count) relationships")
    }
    
    /// Search memories with optional container tag filtering
    public func search(
        query: String,
        userId: String,
        limit: Int = 10,
        containerTags: [String] = []
    ) async throws -> [MemoryResult] {
        guard let embedder = embedder, let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        // Generate query embedding
        let queryEmbedding = try await embedder.embed(query)
        
        // Search in MemoryGraphStore with similarity scores
        let allMemories = await store.getAllMemories()
        
        // MEMORY DECAY: Filter out low-confidence memories
        let confidenceThreshold: Float = 0.3
        
        // SEARCH THRESHOLD: Use 0.3 for broad search
        // 0.6 is too strict for initial queries
        let searchThreshold: Float = 0.3
        let activeMemories = allMemories.filter { memory in
            let confidence = memory.effectiveConfidence()
            return confidence >= confidenceThreshold
        }
        
        let decayedCount = allMemories.count - activeMemories.count
        
        // CONTAINER TAG FILTERING: Filter by tags if provided
        let filteredMemories: [MemoryNode]
        if !containerTags.isEmpty {
            filteredMemories = activeMemories.filter { memory in
                // Memory must have at least one matching tag
                !Set(memory.containerTags).isDisjoint(with: containerTags)
            }
            print("🔍 [SwiftMemAPI] Searching \(filteredMemories.count) memories (filtered by tags: \(containerTags)) from \(activeMemories.count) active (\(decayedCount) decayed)")
        } else {
            filteredMemories = activeMemories
            print("🔍 [SwiftMemAPI] Searching \(activeMemories.count) active memories (filtered \(decayedCount) decayed) for: '\(query)'")
        }
        
        // Extract keywords from query for boosting
        let keywords = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        
        // Get static memories (core facts) for boosting
        let staticMemories = await store.getStaticMemories()
        let staticIds = Set(staticMemories.map { $0.id })
        print("📌 [SwiftMemAPI] \(staticIds.count) static memories (core facts) available for boosting")
        
        // Calculate cosine similarity + keyword boost + profile boost for each memory
        let scored = filteredMemories.compactMap { memory -> (MemoryNode, Float)? in
            guard !memory.embedding.isEmpty else { return nil }
            
            // Base similarity score
            var similarity = cosineSimilarity(queryEmbedding, memory.embedding)
            
            // Keyword boosting - if query keywords appear in content, boost score
            let contentLower = memory.content.lowercased()
            var keywordBoost: Float = 0.0
            for keyword in keywords {
                if contentLower.contains(keyword) {
                    keywordBoost += 0.15 // Boost by 0.15 per keyword match
                }
            }
            
            // USER PROFILE BOOST: Static memories (core facts) get priority
            var profileBoost: Float = 0.0
            if staticIds.contains(memory.id) {
                profileBoost = 0.1 // Boost static memories by 0.1
                print("  📌 Boosting static memory: \(String(memory.content.prefix(40)))...")
            }
            
            similarity = min(1.0, similarity + keywordBoost + profileBoost)
            return (memory, similarity)
        }
        
        // Sort by similarity first (before filtering)
        let sortedResults = scored.sorted { $0.1 > $1.1 }
        
        print("📊 [SwiftMemAPI] Top scores before filtering: \(sortedResults.prefix(5).map { $0.1 })")
        
        // Filter by search threshold and take top results
        let initialResults = sortedResults
            .filter { $0.1 >= searchThreshold }  // Min 0.3 similarity
            .prefix(limit)
        
        print("📊 [SwiftMemAPI] Initial top \(initialResults.count) results (threshold: \(searchThreshold)):")
        for (i, (memory, score)) in initialResults.enumerated() {
            print("  \(i+1). Score: \(score) - \(String(memory.content.prefix(60)))...")
        }
        
        // GRAPH-BASED EXPANSION: Follow relationships to find related memories
        var expandedResults: [(MemoryNode, Float)] = Array(initialResults)
        var seenIds = Set(initialResults.map { $0.0.id })
        
        print("🕸️ [SwiftMemAPI] Expanding via relationships...")
        for (memory, baseScore) in initialResults {
            // Follow relationships to related memories
            for relationship in memory.relationships {
                // Find the related memory
                if let relatedMemory = activeMemories.first(where: { $0.id == relationship.targetId }),
                   !seenIds.contains(relatedMemory.id) {
                    // Score decays based on relationship confidence
                    let relatedScore = baseScore * relationship.confidence * 0.8 // 80% of original score
                    expandedResults.append((relatedMemory, relatedScore))
                    seenIds.insert(relatedMemory.id)
                    print("  → Found \(relationship.type) memory (score: \(relatedScore))")
                }
            }
        }
        
        // Re-sort with expanded results and take top K
        let finalResults = expandedResults
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
        
        print("✅ [SwiftMemAPI] Final results after graph expansion: \(finalResults.count)")
        
        // Convert to public result type
        return finalResults.map { (memory, score) in
            MemoryResult(memory: memory, score: score)
        }
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
    
    /// Add memories from a conversation (automatic extraction)
    public func addConversation(conversation: String, userId: String) async throws -> Int {
        guard let embedder = embedder, let extractor = memoryExtractor, let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        // Extract memories
        let extracted = try await extractor.extractMemories(
            from: conversation,
            userId: userId,
            embedder: embedder
        )
        
        // Store each memory
        for extractedMemory in extracted {
            let memoryNode = extractedMemory.toMemoryNode()
            try await store.addMemory(memoryNode)
            _ = await userProfileManager?.classifyMemory(memoryNode, userId: userId)
        }
        
        return extracted.count
    }
    
    /// Get user context (static + recent dynamic memories)
    public func getUserContext(userId: String, maxDynamic: Int = 10) async throws -> [MemoryResult] {
        guard let profileManager = userProfileManager else {
            throw SwiftMemError.notInitialized
        }
        
        let context = await profileManager.getUserContext(userId: userId, maxDynamic: maxDynamic)
        return context.map { MemoryResult(memory: $0, score: 1.0) }
    }
    
    /// Get enriched context for a memory (includes related memories)
    public func getEnrichedContext(memoryId: UUID) async throws -> [MemoryResult] {
        guard let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        let enriched = await store.getEnrichedContext(for: memoryId)
        return enriched.map { MemoryResult(memory: $0, score: 1.0) }
    }
    
    /// Update a memory
    public func update(memoryId: UUID, newContent: String) async throws {
        guard let embedder = embedder, let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        guard let oldMemory = await store.getMemory(memoryId) else {
            throw SwiftMemError.memoryNotFound
        }
        
        // Generate new embedding
        let newEmbedding = try await embedder.embed(newContent)
        
        // Create new memory that UPDATES the old one
        let newMemory = MemoryNode(
            content: newContent,
            embedding: newEmbedding,
            relationships: [
                MemoryRelationship(type: .updates, targetId: oldMemory.id)
            ]
        )
        
        try await store.addMemory(newMemory)
        
        // Mark old memory as not latest
        var updatedOld = oldMemory
        updatedOld.isLatest = false
        try await store.updateMemory(updatedOld)
    }
    
    /// Delete a memory
    public func delete(memoryId: UUID) async throws {
        // Archive instead of hard delete
        guard let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        guard var memory = await store.getMemory(memoryId) else {
            throw SwiftMemError.memoryNotFound
        }
        
        // Mark as forgotten
        memory.confidence = 0.0
        try await store.updateMemory(memory)
    }
    
    /// Get statistics
    public func getStats() async throws -> APIMemoryStats {
        guard let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        let (nodes, relationships, avgDegree) = await store.getStatistics()
        
        return APIMemoryStats(
            totalMemories: nodes,
            totalRelationships: relationships,
            averageDegree: avgDegree
        )
    }
    
    /// Get all memories (for visualization/debugging)
    public func getAllMemories() async throws -> [MemoryResult] {
        guard let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        let nodes = await store.getAllMemories()
        return nodes.map { node in
            MemoryResult(memory: node, score: 1.0)
        }
    }
    
    // MARK: - Phase 7: Memory Consolidation
    
    /// Consolidate duplicate memories to reduce redundancy
    public func consolidateMemories(userId: String) async throws -> Int {
        guard let store = memoryGraphStore,
              let consolidator = memoryConsolidator else {
            throw SwiftMemError.notInitialized
        }
        
        let memories = await store.getAllMemories()
        let (consolidated, removedIds) = await consolidator.consolidate(memories: memories)
        
        // Update store with consolidated memories
        for memory in consolidated {
            try await store.updateMemory(memory)
        }
        
        // Remove duplicates
        for id in removedIds {
            await store.deleteMemory(id)
        }
        
        return removedIds.count
    }
    
    // MARK: - Phase 8: Batch Operations
    
    /// Batch add multiple memories efficiently
    public func batchAdd(
        contents: [String],
        userId: String,
        containerTags: [[String]] = []
    ) async throws {
        guard let store = memoryGraphStore,
              let batchOps = batchOperations,
              let userProfile = userProfileManager else {
            throw SwiftMemError.notInitialized
        }
        
        let existingMemories = await store.getAllMemories()
        let newMemories = try await batchOps.batchAdd(
            contents: contents,
            userId: userId,
            containerTags: containerTags,
            existingMemories: existingMemories
        )
        
        // Store and classify each memory
        for memory in newMemories {
            try await store.addMemory(memory)
            let isStatic = await userProfile.classifyMemory(memory, userId: userId)
            print("🏷️ [SwiftMemAPI] Classified as: \(isStatic ? "static" : "dynamic")")
        }
    }
    
    /// Batch delete multiple memories by IDs
    public func batchDelete(ids: [UUID]) async throws {
        guard let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        for id in ids {
            await store.deleteMemory(id)
        }
    }
    
    /// Batch update memories
    public func batchUpdate(
        updates: [(id: UUID, content: String?, metadata: MemoryMetadata?, containerTags: [String]?)]
    ) async throws {
        guard let store = memoryGraphStore,
              let batchOps = batchOperations else {
            throw SwiftMemError.notInitialized
        }
        
        let allMemories = await store.getAllMemories()
        let updatedMemories = try await batchOps.batchUpdate(updates: updates, memories: allMemories)
        
        for memory in updatedMemories {
            try await store.updateMemory(memory)
        }
    }
}

// MARK: - Public Result Types

/// Memory search result
public struct MemoryResult: Identifiable {
    public let id: UUID
    public let content: String
    public let score: Float
    public let timestamp: Date
    public let confidence: Float
    public let isStatic: Bool
    public let entities: [String]
    public let topics: [String]
    public let containerTags: [String]
    public let relationships: [MemoryRelationship]
    
    init(memory: MemoryNode, score: Float) {
        self.id = memory.id
        self.content = memory.content
        self.score = score
        self.timestamp = memory.timestamp
        self.confidence = memory.confidence
        self.isStatic = memory.isStatic
        self.entities = memory.metadata.entities
        self.topics = memory.metadata.topics
        self.containerTags = memory.containerTags
        self.relationships = memory.relationships
    }
}

/// Memory statistics
public struct APIMemoryStats {
    public let totalMemories: Int
    public let totalRelationships: Int
    public let averageDegree: Double
}

// MARK: - Errors

extension SwiftMemError {
    static var notInitialized: SwiftMemError {
        return .configurationError("SwiftMem not initialized. Call initialize() first.")
    }
    
    static var memoryNotFound: SwiftMemError {
        return .storageError("Memory not found")
    }
}
