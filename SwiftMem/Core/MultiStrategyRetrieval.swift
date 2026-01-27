//
//  MultiStrategyRetrieval.swift
//  SwiftMem
//
//  Multi-strategy retrieval with query analysis and adaptive scoring
//  Combines vector, keyword, fact, and goal-based retrieval
//

import Foundation

/// Result of a multi-strategy retrieval
public struct MultiStrategyRetrievalResult {
    public let memories: [ScoredMemoryResult]
    public let queryType: QueryType
    public let strategies: [String]
    public let retrievalTimeMs: Double

    public init(
        memories: [ScoredMemoryResult],
        queryType: QueryType,
        strategies: [String],
        retrievalTimeMs: Double
    ) {
        self.memories = memories
        self.queryType = queryType
        self.strategies = strategies
        self.retrievalTimeMs = retrievalTimeMs
    }
}

/// A memory with its retrieval score and metadata
public struct ScoredMemoryResult: Identifiable {
    public let id: UUID
    public let content: String
    public let score: Float
    public let scores: ScoreBreakdown
    public let retrievalReason: String
    public let layer: MemoryLayer

    public init(
        id: UUID,
        content: String,
        score: Float,
        scores: ScoreBreakdown,
        retrievalReason: String,
        layer: MemoryLayer
    ) {
        self.id = id
        self.content = content
        self.score = score
        self.scores = scores
        self.retrievalReason = retrievalReason
        self.layer = layer
    }
}

/// Breakdown of individual score components
public struct ScoreBreakdown {
    public let vector: Float
    public let keyword: Float
    public let recency: Float
    public let importance: Float
    public let utility: Float
    public let factMatch: Float
    public let layerBoost: Float

    public init(
        vector: Float = 0,
        keyword: Float = 0,
        recency: Float = 0,
        importance: Float = 0,
        utility: Float = 0,
        factMatch: Float = 0,
        layerBoost: Float = 0
    ) {
        self.vector = vector
        self.keyword = keyword
        self.recency = recency
        self.importance = importance
        self.utility = utility
        self.factMatch = factMatch
        self.layerBoost = layerBoost
    }
}

/// Multi-strategy retrieval engine
public actor MultiStrategyRetrieval {

    // MARK: - Dependencies

    private let temporalExtractor: TemporalExtractor
    private let goalManager: GoalMemoryManager
    private let factIndex: FactIndex

    // MARK: - Query Analysis Keywords

    private let factualKeywords = ["what", "when", "where", "who", "which", "name", "birthday", "age", "how old", "how many"]
    private let conceptualKeywords = ["how", "why", "feel", "think", "opinion", "about", "regarding"]
    private let temporalKeywords = ["yesterday", "last week", "recently", "today", "when did", "last time"]
    private let goalKeywords = ["goal", "progress", "how am i doing", "fitness", "health", "career", "relationship"]
    private let emotionalKeywords = ["happy", "sad", "stressed", "anxious", "excited", "feel", "feeling", "emotion"]

    // MARK: - Initialization

    public init(
        temporalExtractor: TemporalExtractor,
        goalManager: GoalMemoryManager,
        factIndex: FactIndex
    ) {
        self.temporalExtractor = temporalExtractor
        self.goalManager = goalManager
        self.factIndex = factIndex
    }

    // MARK: - Public API

    /// Analyze a query and determine the best retrieval strategy
    public func analyzeQuery(_ query: String) -> QueryAnalysis {
        let lower = query.lowercased()

        // Classify query type
        let queryType = classifyQueryType(lower)

        // Get optimal weights
        let weights = RetrievalWeights.forQueryType(queryType)

        // Extract entities from query
        let queryEntities = extractQueryEntities(query)

        // Extract temporal scope
        let temporalScope = extractTemporalScope(lower)

        return QueryAnalysis(
            queryType: queryType,
            weights: weights,
            entities: queryEntities,
            temporalScope: temporalScope,
            originalQuery: query
        )
    }

    /// Perform multi-strategy retrieval
    public func retrieve(
        query: String,
        memories: [MemoryForRetrieval],
        queryEmbedding: [Float],
        userId: String,
        topK: Int = 10
    ) async -> MultiStrategyRetrievalResult {
        let startTime = Date()

        // Analyze query
        let analysis = analyzeQuery(query)

        // Run parallel retrieval strategies
        var candidates: [UUID: CandidateScores] = [:]
        var strategiesUsed: [String] = []

        // Strategy 1: Vector similarity
        let vectorResults = vectorSearch(
            queryEmbedding: queryEmbedding,
            memories: memories,
            topK: topK * 2
        )
        strategiesUsed.append("vector")

        for (memory, score) in vectorResults {
            candidates[memory.id, default: CandidateScores()].vector = score
            candidates[memory.id]?.memory = memory
        }

        // Strategy 2: Keyword matching
        let keywordResults = keywordSearch(
            query: query,
            memories: memories,
            topK: topK * 2
        )
        strategiesUsed.append("keyword")

        for (memory, score) in keywordResults {
            candidates[memory.id, default: CandidateScores()].keyword = score
            if candidates[memory.id]?.memory == nil {
                candidates[memory.id]?.memory = memory
            }
        }

        // Strategy 3: Fact lookup (if query seems factual)
        if analysis.queryType == .factual {
            let factResults = await factLookup(
                entities: analysis.entities,
                memories: memories
            )
            strategiesUsed.append("fact_lookup")

            for (memory, score) in factResults {
                candidates[memory.id, default: CandidateScores()].factMatch = score
                if candidates[memory.id]?.memory == nil {
                    candidates[memory.id]?.memory = memory
                }
            }
        }

        // Strategy 4: Goal-based retrieval (if query is about goals)
        if analysis.queryType == .goalProgress {
            let goalResults = await goalBasedRetrieval(
                query: query,
                memories: memories,
                userId: userId
            )
            strategiesUsed.append("goal_based")

            for (memory, score) in goalResults {
                candidates[memory.id, default: CandidateScores()].factMatch = score // Reuse factMatch for goal relevance
                if candidates[memory.id]?.memory == nil {
                    candidates[memory.id]?.memory = memory
                }
            }
        }

        // Calculate final scores
        var scoredResults: [ScoredMemoryResult] = []

        for (memoryId, scores) in candidates {
            guard let memory = scores.memory else { continue }

            // Calculate recency score
            let recencyScore = await temporalExtractor.recencyScore(for: memory.timestamp)

            // Calculate utility score
            let utilityScore = memory.totalRetrievals > 0
                ? Float(memory.usefulRetrievals) / Float(memory.totalRetrievals)
                : 0.5

            // Layer boost
            let layerBoost = Float(memory.layer.retrievalPriority) / 100.0

            // Build score breakdown
            let breakdown = ScoreBreakdown(
                vector: scores.vector,
                keyword: scores.keyword,
                recency: recencyScore,
                importance: memory.importance,
                utility: utilityScore,
                factMatch: scores.factMatch,
                layerBoost: layerBoost
            )

            // Calculate weighted final score
            let finalScore = calculateFinalScore(breakdown: breakdown, weights: analysis.weights)

            // Generate retrieval reason
            let reason = generateRetrievalReason(breakdown: breakdown, weights: analysis.weights)

            scoredResults.append(ScoredMemoryResult(
                id: memoryId,
                content: memory.content,
                score: finalScore,
                scores: breakdown,
                retrievalReason: reason,
                layer: memory.layer
            ))
        }

        // Sort by score and take top K
        scoredResults.sort { $0.score > $1.score }
        let topResults = Array(scoredResults.prefix(topK))

        let elapsedMs = Date().timeIntervalSince(startTime) * 1000

        return MultiStrategyRetrievalResult(
            memories: topResults,
            queryType: analysis.queryType,
            strategies: strategiesUsed,
            retrievalTimeMs: elapsedMs
        )
    }

    // MARK: - Query Classification

    private func classifyQueryType(_ query: String) -> QueryType {
        // Check for emotional queries
        for keyword in emotionalKeywords {
            if query.contains(keyword) {
                return .emotional
            }
        }

        // Check for goal queries
        for keyword in goalKeywords {
            if query.contains(keyword) {
                return .goalProgress
            }
        }

        // Check for temporal queries
        for keyword in temporalKeywords {
            if query.contains(keyword) {
                return .temporal
            }
        }

        // Check for factual queries (who, what, when, where)
        for keyword in factualKeywords {
            if query.contains(keyword) {
                return .factual
            }
        }

        // Check for conceptual queries
        for keyword in conceptualKeywords {
            if query.contains(keyword) {
                return .conceptual
            }
        }

        // Default to exploratory
        return .exploratory
    }

    private func extractQueryEntities(_ query: String) -> [String] {
        var entities: [String] = []

        // Extract capitalized words
        let words = query.components(separatedBy: .whitespacesAndNewlines)
        let excludedWords = Set(["I", "What", "When", "Where", "Who", "How", "Why", "The", "A", "An", "My"])

        for word in words {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            if clean.first?.isUppercase == true && !excludedWords.contains(clean) {
                entities.append(clean)
            }
        }

        // Extract quoted strings
        if let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"", options: []) {
            let range = NSRange(query.startIndex..., in: query)
            let matches = regex.matches(in: query, range: range)

            for match in matches {
                if let range = Range(match.range(at: 1), in: query) {
                    entities.append(String(query[range]))
                }
            }
        }

        return entities
    }

    private func extractTemporalScope(_ query: String) -> TemporalScope {
        if query.contains("today") || query.contains("now") {
            return .today
        } else if query.contains("yesterday") {
            return .yesterday
        } else if query.contains("this week") || query.contains("recently") {
            return .thisWeek
        } else if query.contains("last week") {
            return .lastWeek
        } else if query.contains("this month") {
            return .thisMonth
        } else if query.contains("last month") {
            return .lastMonth
        }
        return .all
    }

    // MARK: - Retrieval Strategies

    private func vectorSearch(
        queryEmbedding: [Float],
        memories: [MemoryForRetrieval],
        topK: Int
    ) -> [(MemoryForRetrieval, Float)] {
        var results: [(MemoryForRetrieval, Float)] = []

        for memory in memories {
            let similarity = cosineSimilarity(queryEmbedding, memory.embedding)
            if similarity > 0.2 { // Minimum threshold
                results.append((memory, similarity))
            }
        }

        results.sort { $0.1 > $1.1 }
        return Array(results.prefix(topK))
    }

    private func keywordSearch(
        query: String,
        memories: [MemoryForRetrieval],
        topK: Int
    ) -> [(MemoryForRetrieval, Float)] {
        let queryWords = Set(query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 })

        let stopWords = Set(["the", "a", "an", "is", "are", "was", "were", "to", "and", "or", "but", "in", "on", "at", "for", "of", "with"])
        let filteredQuery = queryWords.subtracting(stopWords)

        var results: [(MemoryForRetrieval, Float)] = []

        for memory in memories {
            let contentWords = Set(memory.content.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count > 2 })
            let filteredContent = contentWords.subtracting(stopWords)

            let intersection = filteredQuery.intersection(filteredContent)
            guard !intersection.isEmpty else { continue }

            // BM25-like scoring
            let score = Float(intersection.count) / Float(max(filteredQuery.count, 1))

            // Boost for exact phrase match
            var finalScore = score
            if memory.content.lowercased().contains(query.lowercased()) {
                finalScore += 0.3
            }

            results.append((memory, min(finalScore, 1.0)))
        }

        results.sort { $0.1 > $1.1 }
        return Array(results.prefix(topK))
    }

    private func factLookup(
        entities: [String],
        memories: [MemoryForRetrieval]
    ) async -> [(MemoryForRetrieval, Float)] {
        guard !entities.isEmpty else { return [] }

        var results: [(MemoryForRetrieval, Float)] = []

        // Get facts for entities
        for entity in entities {
            let facts = await factIndex.getFacts(forSubject: entity.lowercased())

            for fact in facts {
                // Find memory containing this fact
                if let memory = memories.first(where: { $0.id == fact.sourceMemoryId }) {
                    results.append((memory, fact.confidence))
                }
            }
        }

        return results
    }

    private func goalBasedRetrieval(
        query: String,
        memories: [MemoryForRetrieval],
        userId: String
    ) async -> [(MemoryForRetrieval, Float)] {
        // Find relevant goals
        let relevantGoals = await goalManager.findRelevantGoals(query: query, userId: userId, topK: 3)

        var results: [(MemoryForRetrieval, Float)] = []

        for goal in relevantGoals {
            // Get all memories linked to this goal
            if let organized = await goalManager.getOrganizedMemories(for: goal.id) {
                let allLinkedIds = organized.progressIds + organized.blockerIds +
                                   organized.motivationIds + organized.insightIds

                for linkedId in allLinkedIds {
                    if let memory = memories.first(where: { $0.id == linkedId }) {
                        results.append((memory, 0.8)) // High score for goal-linked memories
                    }
                }
            }
        }

        return results
    }

    // MARK: - Score Calculation

    private func calculateFinalScore(breakdown: ScoreBreakdown, weights: RetrievalWeights) -> Float {
        let baseScore = breakdown.vector * weights.vector +
                       breakdown.keyword * weights.keyword +
                       breakdown.recency * weights.recency +
                       breakdown.importance * weights.importance +
                       breakdown.utility * weights.utility +
                       breakdown.factMatch * weights.factMatch

        // Apply layer boost
        let boostedScore = baseScore * (1.0 + breakdown.layerBoost * 0.1)

        return min(boostedScore, 1.0)
    }

    private func generateRetrievalReason(breakdown: ScoreBreakdown, weights: RetrievalWeights) -> String {
        var reasons: [String] = []

        let components: [(String, Float, Float)] = [
            ("vector similarity", breakdown.vector, weights.vector),
            ("keyword match", breakdown.keyword, weights.keyword),
            ("recency", breakdown.recency, weights.recency),
            ("importance", breakdown.importance, weights.importance),
            ("utility", breakdown.utility, weights.utility),
            ("fact match", breakdown.factMatch, weights.factMatch)
        ]

        // Find top contributing factors
        let sorted = components.sorted { $0.1 * $0.2 > $1.1 * $1.2 }

        for (name, score, weight) in sorted.prefix(2) {
            if score > 0.3 && weight > 0.1 {
                reasons.append(name)
            }
        }

        if reasons.isEmpty {
            return "general relevance"
        }

        return reasons.joined(separator: ", ")
    }

    // MARK: - Utilities

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }

        let magnitude = sqrt(magnitudeA) * sqrt(magnitudeB)
        return magnitude > 0 ? dotProduct / magnitude : 0
    }
}

// MARK: - Supporting Types

/// Query analysis result
public struct QueryAnalysis {
    public let queryType: QueryType
    public let weights: RetrievalWeights
    public let entities: [String]
    public let temporalScope: TemporalScope
    public let originalQuery: String
}

/// Temporal scope for queries
public enum TemporalScope {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case all
}

/// Intermediate scores during retrieval
private struct CandidateScores {
    var memory: MemoryForRetrieval?
    var vector: Float = 0
    var keyword: Float = 0
    var factMatch: Float = 0
}

/// Memory data needed for retrieval (lightweight view)
public struct MemoryForRetrieval {
    public let id: UUID
    public let content: String
    public let embedding: [Float]
    public let timestamp: Date
    public let importance: Float
    public let layer: MemoryLayer
    public let usefulRetrievals: Int
    public let totalRetrievals: Int

    public init(
        id: UUID,
        content: String,
        embedding: [Float],
        timestamp: Date,
        importance: Float,
        layer: MemoryLayer,
        usefulRetrievals: Int = 0,
        totalRetrievals: Int = 0
    ) {
        self.id = id
        self.content = content
        self.embedding = embedding
        self.timestamp = timestamp
        self.importance = importance
        self.layer = layer
        self.usefulRetrievals = usefulRetrievals
        self.totalRetrievals = totalRetrievals
    }
}
