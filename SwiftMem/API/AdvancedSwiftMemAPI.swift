//
//  AdvancedSwiftMemAPI.swift
//  SwiftMem
//
//  Enhanced API with SOTA architecture features
//  Fact-based contradiction, goal-centric memory, multi-strategy retrieval
//

import Foundation

/// Enhanced SwiftMem API with SOTA architecture
/// Integrates: Fact extraction, Contradiction detection, Goal-centric memory, Multi-strategy retrieval
public actor AdvancedSwiftMemAPI {

    public static let shared = AdvancedSwiftMemAPI()

    // MARK: - Core Components

    private var advancedStore: AdvancedGraphStore?
    private var memoryGraphStore: MemoryGraphStore?
    private var embedder: Embedder?
    private var config: SwiftMemConfig

    // MARK: - SOTA Components

    private var factIndex: FactIndex?
    private var contradictionEngine: FactContradictionEngine?
    private var entityExtractor: AdvancedEntityExtractor?
    private var temporalExtractor: TemporalExtractor?
    private var goalManager: GoalMemoryManager?
    private var multiStrategyRetrieval: MultiStrategyRetrieval?

    // MARK: - State

    private var isInitialized = false

    private init() {
        self.config = .default
    }

    // MARK: - Initialization

    /// Initialize with SOTA architecture components
    public func initialize(config: SwiftMemConfig = .default, embedder: Embedder? = nil) async throws {
        guard !isInitialized else { return }

        self.config = config
        self.embedder = embedder ?? NLEmbedder()

        // Initialize advanced store (includes all SOTA components)
        self.advancedStore = try await AdvancedGraphStore.create(config: config)

        // Get component references from store
        self.factIndex = await advancedStore?.getFactIndex()
        self.contradictionEngine = await advancedStore?.getContradictionEngine()
        self.entityExtractor = await advancedStore?.getEntityExtractor()
        self.temporalExtractor = await advancedStore?.getTemporalExtractor()
        self.goalManager = await advancedStore?.getGoalManager()

        // Initialize multi-strategy retrieval
        if let temporal = temporalExtractor, let goals = goalManager, let facts = factIndex {
            self.multiStrategyRetrieval = MultiStrategyRetrieval(
                temporalExtractor: temporal,
                goalManager: goals,
                factIndex: facts
            )
        }

        isInitialized = true
        print("✅ [AdvancedSwiftMemAPI] SOTA architecture initialized")
    }

    // MARK: - Enhanced Add Memory

    /// Add a memory with full SOTA processing
    public func add(
        content: String,
        userId: String,
        containerTags: [String] = [],
        conversationDate: Date? = nil
    ) async throws -> AddMemoryResult {
        guard let embedder = embedder,
              let store = advancedStore,
              let entityExtractor = entityExtractor,
              let temporalExtractor = temporalExtractor,
              let goalManager = goalManager else {
            throw SwiftMemError.notInitialized
        }

        // Generate embedding
        let embedding = try await embedder.embed(content)
        let memoryId = UUID()

        // 1. Extract structured data
        let extraction = await entityExtractor.extract(
            from: content,
            sourceMemoryId: memoryId,
            userId: userId
        )

        // 2. Extract temporal info
        let temporalInfo = await temporalExtractor.extract(
            from: content,
            referenceDate: conversationDate ?? Date()
        )

        // 3. Check for contradictions
        var contradictionResults: [ContradictionResult] = []
        if !extraction.facts.isEmpty {
            contradictionResults = try await store.checkAndResolveContradictions(
                newFacts: extraction.facts,
                userId: userId
            )

            if !contradictionResults.isEmpty {
                print("⚠️ [AdvancedSwiftMemAPI] Found \(contradictionResults.count) contradictions")
                for result in contradictionResults {
                    print("  → \(await contradictionEngine?.describeContradiction(result) ?? "Unknown")")
                }
            }
        }

        // 4. Check if this is a goal
        var goalCluster: GoalCluster? = nil
        if await goalManager.isGoalContent(content) {
            goalCluster = await goalManager.registerGoal(
                memoryId: memoryId,
                content: content,
                userId: userId
            )
            print("🎯 [AdvancedSwiftMemAPI] Registered new goal: \(content.prefix(50))...")
        }

        // 5. Link to existing goals
        let goalLinks = await goalManager.linkMemoryToGoals(
            memoryId: memoryId,
            content: content,
            emotionalValence: extraction.emotionalValence,
            userId: userId
        )

        if !goalLinks.isEmpty {
            print("🔗 [AdvancedSwiftMemAPI] Linked to \(goalLinks.count) goals")
        }

        // 6. Determine memory layer
        let layer = determineMemoryLayer(
            content: content,
            facts: extraction.facts,
            temporalInfo: temporalInfo,
            isGoal: goalCluster != nil
        )

        // 7. Calculate importance
        let importance = calculateImportance(
            facts: extraction.facts,
            emotionalValence: extraction.emotionalValence,
            isGoal: goalCluster != nil,
            goalLinks: goalLinks
        )

        // 8. Store facts
        for fact in extraction.facts {
            try await store.storeFact(fact, userId: userId)
        }

        // 9. Store entities
        for entity in extraction.entities {
            try await store.storeEntity(entity)
        }

        // 10. Store goal cluster if created
        if let cluster = goalCluster {
            try await store.storeGoalCluster(cluster)
        }

        print("✅ [AdvancedSwiftMemAPI] Added memory with:")
        print("  📋 Facts: \(extraction.facts.count)")
        print("  👤 Entities: \(extraction.entities.count)")
        print("  🎭 Emotion: \(extraction.emotionalValence.primary) (\(extraction.emotionalValence.intensity))")
        print("  📍 Layer: \(layer)")
        print("  ⭐ Importance: \(importance)")

        return AddMemoryResult(
            memoryId: memoryId,
            factsExtracted: extraction.facts.count,
            entitiesExtracted: extraction.entities.count,
            contradictionsFound: contradictionResults.count,
            goalsLinked: goalLinks.count,
            isGoal: goalCluster != nil,
            layer: layer,
            importance: importance,
            emotionalValence: extraction.emotionalValence
        )
    }

    // MARK: - Enhanced Search

    /// Search with multi-strategy retrieval
    public func search(
        query: String,
        userId: String,
        limit: Int = 10,
        containerTags: [String] = []
    ) async throws -> SearchResult {
        guard let embedder = embedder,
              let retrieval = multiStrategyRetrieval else {
            throw SwiftMemError.notInitialized
        }

        // Generate query embedding
        let queryEmbedding = try await embedder.embed(query)

        // Get memories for retrieval
        let memories = try await getMemoriesForRetrieval(userId: userId, containerTags: containerTags)

        // Perform multi-strategy retrieval
        let result = await retrieval.retrieve(
            query: query,
            memories: memories,
            queryEmbedding: queryEmbedding,
            userId: userId,
            topK: limit
        )

        print("🔍 [AdvancedSwiftMemAPI] Search completed:")
        print("  📊 Query type: \(result.queryType)")
        print("  🎯 Strategies: \(result.strategies.joined(separator: ", "))")
        print("  ⏱️ Time: \(String(format: "%.2f", result.retrievalTimeMs))ms")
        print("  📝 Results: \(result.memories.count)")

        return SearchResult(
            memories: result.memories,
            queryType: result.queryType,
            strategiesUsed: result.strategies,
            retrievalTimeMs: result.retrievalTimeMs
        )
    }

    /// Analyze a query without searching
    public func analyzeQuery(_ query: String) async -> QueryAnalysis? {
        return await multiStrategyRetrieval?.analyzeQuery(query)
    }

    // MARK: - Goal Operations

    /// Get coaching context for a specific goal
    public func getCoachingContext(goalId: UUID) async -> CoachingContext? {
        return await goalManager?.generateCoachingContext(for: goalId)
    }

    /// Get all goals for a user
    public func getGoals(userId: String) async -> [GoalCluster] {
        return await goalManager?.getGoalsForUser(userId) ?? []
    }

    /// Get goals relevant to a query
    public func findRelevantGoals(query: String, userId: String, topK: Int = 3) async -> [GoalCluster] {
        return await goalManager?.findRelevantGoals(query: query, userId: userId, topK: topK) ?? []
    }

    /// Get formatted coaching context string for LLM
    public func getFormattedCoachingContext(goalId: UUID) async -> String? {
        return await goalManager?.formatCoachingContextString(for: goalId)
    }

    // MARK: - Fact Operations

    /// Get all facts for a subject (e.g., "user", "mom", etc.)
    public func getFacts(subject: String, userId: String) async throws -> [Fact] {
        return try await advancedStore?.getFactsForSubject(subject, userId: userId) ?? []
    }

    /// Check if new facts would contradict existing knowledge
    public func checkContradictions(facts: [Fact], userId: String) async throws -> [ContradictionResult] {
        return try await advancedStore?.checkAndResolveContradictions(newFacts: facts, userId: userId) ?? []
    }

    // MARK: - Temporal Operations

    /// Extract temporal information from text
    public func extractTemporalInfo(_ text: String, referenceDate: Date = Date()) async -> TemporalInfo {
        return await temporalExtractor?.extract(from: text, referenceDate: referenceDate) ?? TemporalInfo()
    }

    /// Get recency score for a date
    public func getRecencyScore(for date: Date) async -> Float {
        return await temporalExtractor?.recencyScore(for: date) ?? 0.5
    }

    // MARK: - Entity Operations

    /// Extract entities from content
    public func extractEntities(from content: String, userId: String) async -> [TrackedEntity] {
        return await entityExtractor?.extractEntities(from: content, userId: userId) ?? []
    }

    // MARK: - Helpers

    private func getMemoriesForRetrieval(userId: String, containerTags: [String]) async throws -> [MemoryForRetrieval] {
        // This would integrate with the existing MemoryGraphStore
        // For now, return empty - the integration point is ready
        return []
    }

    private func determineMemoryLayer(
        content: String,
        facts: [Fact],
        temporalInfo: TemporalInfo,
        isGoal: Bool
    ) -> MemoryLayer {
        // Goals are core memories
        if isGoal {
            return .core
        }

        // Facts with exclusive predicates (location, attribute) are core
        let hasCoreFacts = facts.contains { fact in
            fact.predicateCategory.isMutuallyExclusive && fact.confidence > 0.8
        }
        if hasCoreFacts {
            return .core
        }

        // Ongoing states are short-term
        if temporalInfo.isOngoing {
            return .shortTerm
        }

        // Past events are long-term
        if temporalInfo.temporalType == .past {
            return .longTerm
        }

        // Default to short-term
        return .shortTerm
    }

    private func calculateImportance(
        facts: [Fact],
        emotionalValence: EmotionalValence,
        isGoal: Bool,
        goalLinks: [GoalLinkResult]
    ) -> Float {
        var importance: Float = 0.5

        // Goals are highly important
        if isGoal {
            importance += 0.3
        }

        // Linked to goals increases importance
        if !goalLinks.isEmpty {
            importance += Float(min(goalLinks.count, 3)) * 0.1
        }

        // Facts increase importance
        if !facts.isEmpty {
            importance += Float(min(facts.count, 3)) * 0.05
        }

        // Emotional content is more important
        if emotionalValence.isEmotional {
            importance += emotionalValence.intensity * 0.1
        }

        return min(importance, 1.0)
    }
}

// MARK: - Result Types

/// Result of adding a memory
public struct AddMemoryResult {
    public let memoryId: UUID
    public let factsExtracted: Int
    public let entitiesExtracted: Int
    public let contradictionsFound: Int
    public let goalsLinked: Int
    public let isGoal: Bool
    public let layer: MemoryLayer
    public let importance: Float
    public let emotionalValence: EmotionalValence
}

/// Result of a search operation
public struct SearchResult {
    public let memories: [ScoredMemoryResult]
    public let queryType: QueryType
    public let strategiesUsed: [String]
    public let retrievalTimeMs: Double

    /// Format as context for LLM
    public func formatForLLM(maxTokens: Int = 500) -> String {
        var output = "RELEVANT MEMORIES:\n"
        var tokenEstimate = 20

        for (index, memory) in memories.enumerated() {
            let line = "\(index + 1). [\(memory.retrievalReason)] \(memory.content)\n"
            let lineTokens = line.count / 4

            if tokenEstimate + lineTokens > maxTokens {
                break
            }

            output += line
            tokenEstimate += lineTokens
        }

        return output
    }
}

// MARK: - Integration Helper

extension AdvancedSwiftMemAPI {
    /// Bridge to convert existing MemoryNode to MemoryForRetrieval
    public func convertToRetrievalFormat(_ node: MemoryNode) -> MemoryForRetrieval {
        return MemoryForRetrieval(
            id: node.id,
            content: node.content,
            embedding: node.embedding,
            timestamp: node.timestamp,
            importance: node.metadata.importance,
            layer: node.isStatic ? .core : .shortTerm,
            usefulRetrievals: 0,
            totalRetrievals: node.metadata.accessCount
        )
    }
}
