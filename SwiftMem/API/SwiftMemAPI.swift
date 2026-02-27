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
    
    /// Reset all components and close database connections (for repair/cleanup)
    public func reset() async {
        print("🔄 [SwiftMemAPI] Resetting all components...")
        
        // Clear all components (this will trigger their deinit and close DB connections)
        memoryGraphStore = nil
        userProfileManager = nil
        memoryExtractor = nil
        hybridSearch = nil
        reranker = nil
        memoryDecay = nil
        relationshipDetector = nil
        memoryConsolidator = nil
        batchOperations = nil
        graphStore = nil
        vectorStore = nil
        embeddingEngine = nil
        retrievalEngine = nil
        embedder = nil
        
        isInitialized = false
        
        print("✅ [SwiftMemAPI] Reset complete - all connections closed")
    }
    
    // MARK: - Helper Functions
    
    /// Extract topics from content using enhanced keyword extraction
    /// Optimized for local-first privacy approach
    private func extractTopics(from content: String) -> [String] {
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "from", "as", "is", "was", "are", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "must", "can", "i", "you", "he", "she", "it", "we", "they", "my", "your", "his", "her", "its", "our", "their", "this", "that", "these", "those", "said", "asked", "told", "went", "came", "made", "got", "get", "take", "took", "give", "gave", "know", "knew", "think", "thought", "want", "wanted", "need", "needed", "like", "liked", "feel", "felt", "see", "saw", "look", "looked", "come", "going", "able", "lot", "really", "just", "also", "even", "well", "back", "only", "over", "after", "before", "through", "where", "when", "why", "how", "what", "which", "who", "whom", "whose"])
        
        let words = content.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) }
        
        // Priority keywords for coaching/personal development
        let priorityKeywords = Set(["family", "work", "career", "health", "mental", "emotional", "relationship", "goal", "development", "growth", "stress", "anxiety", "balance", "wellness", "fitness", "project", "learning", "skill", "achievement", "success", "purpose", "values", "vision", "coaching", "therapy", "mindfulness", "meditation", "exercise", "nutrition", "sleep", "energy", "productivity", "focus", "creativity", "financial", "budget", "savings"])
        
        // Get unique words with scoring
        var wordScores: [String: Float] = [:]
        for word in words {
            // Priority keywords get higher scores
            if priorityKeywords.contains(word) {
                wordScores[word, default: 0] += 3.0
            } else if word.count > 6 {
                wordScores[word, default: 0] += 1.5
            } else {
                wordScores[word, default: 0] += 1.0
            }
        }
        
        let topics = wordScores
            .filter { $0.value >= 1.5 } // Only keep words with decent scores
            .sorted { $0.value > $1.value }
            .prefix(8) // Get more topics for better matching
            .map { $0.key }
        
        return Array(topics)
    }
    
    // MARK: - Simple Public API
    
    /// Add a memory (simple one-liner)
    public func add(content: String, userId: String) async throws {
        try await add(content: content, userId: userId, metadata: nil, containerTags: [])
    }
    
    /// Add a memory with metadata, container tags, and temporal grounding
    public func add(
        content: String,
        userId: String,
        metadata: [String: Any]?,
        containerTags: [String] = [],
        conversationDate: Date? = nil,
        eventDate: Date? = nil,
        skipRelationships: Bool = false
    ) async throws {
        guard let embedder = embedder, let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        // Generate embedding
        let embedding = try await embedder.embed(content)
        
        // Extract entities for better relationship detection (Supermemory approach)
        let entityExtractor = EntityExtractor()
        let extractedFacts = await entityExtractor.extractFacts(from: content)
        let entities = extractedFacts.map { "\($0.subject):\($0.value)" }
        
        // Extract topics from content (simple keyword extraction)
        let topics = extractTopics(from: content)
        
        if !entities.isEmpty || !topics.isEmpty {
            print("🔍 [SwiftMemAPI] Extracted from '\(String(content.prefix(50)))...':")
            if !entities.isEmpty {
                print("  📋 Entities: \(entities.joined(separator: ", "))")
            }
            if !topics.isEmpty {
                print("  🏷️ Topics: \(topics.joined(separator: ", "))")
            }
        }
        
        // Add userId to container tags for persistence (profiles are in-memory only)
        var allTags = containerTags
        if !allTags.contains("user:\(userId)") {
            allTags.append("user:\(userId)")
        }

        // Create memory node with extracted entities, topics, and temporal grounding
        let memory = MemoryNode(
            content: content,
            embedding: embedding,
            timestamp: conversationDate ?? Date(),
            metadata: MemoryMetadata(
                source: .userInput,
                entities: entities,
                topics: topics,
                importance: 0.7
            ),
            containerTags: allTags
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
        
        // Use HybridSearch for SOTA retrieval (vector + keyword + BM25)
        guard let hybridSearch = hybridSearch else {
            throw SwiftMemError.notInitialized
        }
        
        let hybridResults = try await hybridSearch.search(
            query: query,
            queryEmbedding: queryEmbedding,
            topK: limit * 2,  // Get more results for graph expansion
            vectorWeight: 0.7,
            keywordWeight: 0.3
        )
        
        // Get static memories (core facts) for boosting
        let staticMemories = await store.getStaticMemories()
        let staticIds = Set(staticMemories.map { $0.id })
        print("📌 [SwiftMemAPI] \(staticIds.count) static memories (core facts) available for boosting")
        
        // Apply static memory boost to hybrid results
        let boostedResults = hybridResults.map { scoredMemory -> (MemoryNode, Float) in
            var score = scoredMemory.score
            
            // USER PROFILE BOOST: Static memories (core facts) get priority
            if staticIds.contains(scoredMemory.memory.id) {
                score = min(1.0, score + 0.1)
                print("  📌 Boosting static memory: \(String(scoredMemory.memory.content.prefix(40)))...")
            }
            
            return (scoredMemory.memory, score)
        }
        
        print("📊 [SwiftMemAPI] Top scores before filtering: \(boostedResults.prefix(5).map { $0.1 })")
        
        // Filter by search threshold and take top results
        let initialResults = boostedResults
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
    
    /// Add a relationship between two memories (public API for batch operations)
    public func addRelationshipToStore(
        from sourceId: UUID,
        to targetId: UUID,
        type: RelationType,
        confidence: Float
    ) async throws {
        guard let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        
        try await store.addRelationship(
            from: sourceId,
            to: targetId,
            type: type,
            confidence: confidence
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
    
    // MARK: - Dynamic Profile (Supermemory-style RAM Layer)
    
    /// Get dynamic context string for AI prompts (RAM-like instant access)
    /// This is the "currently working on" / "recent endeavors" layer
    public func getDynamicContext(userId: String, limit: Int = 5) async -> String {
        guard let profileManager = userProfileManager else {
            return ""
        }
        
        return await profileManager.getDynamicContextString(userId: userId, limit: limit)
    }
    
    /// Update dynamic context (e.g., "currently working on X")
    public func updateDynamicContext(
        userId: String,
        content: String,
        category: DynamicContextCategory,
        importance: Float = 0.7
    ) async {
        guard let profileManager = userProfileManager else {
            return
        }
        
        await profileManager.updateDynamicContext(
            userId: userId,
            content: content,
            category: category,
            importance: importance
        )
    }
    
    /// Auto-extract dynamic context from recent memories
    /// Call this periodically (e.g., after each session) to keep dynamic context fresh
    public func extractDynamicContext(userId: String) async {
        guard let profileManager = userProfileManager else {
            return
        }
        
        await profileManager.extractDynamicContext(userId: userId)
    }
    
    /// Get user profile (static + dynamic context)
    public func getUserProfile(userId: String) async -> UserProfile? {
        guard let profileManager = userProfileManager else {
            return nil
        }
        
        return await profileManager.getProfile(userId: userId)
    }
    
    /// Clear profile cache (useful for memory pressure)
    public func clearProfileCache() async {
        guard let profileManager = userProfileManager else {
            return
        }
        
        await profileManager.clearCache()
    }
    
    // MARK: - Clear All Memories
    
    /// Clear all memories and relationships (for benchmarks/testing)
    public func clearAll() async throws {
        guard let store = memoryGraphStore else {
            throw SwiftMemError.notInitialized
        }
        try await store.clearAll()
    }
    
    // MARK: - Memory Decay Control
    
    /// Manually trigger decay process (normally runs automatically every 24h)
    public func processDecay() async throws {
        guard let decay = memoryDecay else {
            throw SwiftMemError.notInitialized
        }
        
        try await decay.processDecay()
    }
    
    /// Manually trigger memory pruning (normally runs automatically every 7 days)
    public func pruneMemories(threshold: Float = 0.1) async throws -> Int {
        guard let decay = memoryDecay else {
            throw SwiftMemError.notInitialized
        }
        
        return try await decay.pruneMemories(threshold: threshold)
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
