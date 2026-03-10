//
//  HybridSearch.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation
import Accelerate

/// Hybrid search combining vector similarity and keyword matching
public actor HybridSearch {
    
    private let memoryGraphStore: MemoryGraphStore
    private let config: SwiftMemConfig
    
    public init(memoryGraphStore: MemoryGraphStore, config: SwiftMemConfig) {
        self.memoryGraphStore = memoryGraphStore
        self.config = config
    }
    
    // MARK: - Hybrid Search (v3: Reciprocal Rank Fusion)

    /// Search memories using RRF over three ranked lists: vector, BM25, graph-neighbors.
    /// - Parameter candidateMemories: Pre-filtered memory set (e.g. by container tag). nil = search all.
    /// - Note: vectorWeight/keywordWeight preserved for API compatibility but unused — RRF handles fusion.
    public func search(
        query: String,
        queryEmbedding: [Float],
        topK: Int = 10,
        vectorWeight: Float = 0.7,
        keywordWeight: Float = 0.3,
        candidateMemories: [MemoryNode]? = nil
    ) async throws -> [ScoredMemory] {
        let k = Float(config.rrfK)  // default 60
        let candidateK = topK * 3

        // Load memories once — use pre-filtered set if provided (tag/user filtering)
        let allMemories: [MemoryNode]
        if let candidates = candidateMemories {
            allMemories = candidates
        } else {
            allMemories = await memoryGraphStore.getAllMemories()
        }
        let memoryLookup = Dictionary(uniqueKeysWithValues: allMemories.map { ($0.id, $0) })

        // 1. Three ranked lists (all operating on the same candidate set)
        let vectorResults  = vectorSearch(embedding: queryEmbedding, memories: allMemories, topK: candidateK)
        let keywordResults = keywordSearch(query: query, memories: allMemories, topK: candidateK)
        let graphResults   = graphNeighborSearch(seedMemories: vectorResults, memoryLookup: memoryLookup, topK: candidateK)

        // 2. Build rank maps (1-based)
        func rankMap(_ results: [ScoredMemory]) -> [UUID: Int] {
            var map = [UUID: Int]()
            for (rank, sm) in results.enumerated() { map[sm.memory.id] = rank + 1 }
            return map
        }
        let vRanks = rankMap(vectorResults)
        let kRanks = rankMap(keywordResults)
        let gRanks = rankMap(graphResults)

        // 3. Collect all unique candidate IDs
        var allIds = Set(vRanks.keys)
        allIds.formUnion(kRanks.keys)
        allIds.formUnion(gRanks.keys)

        // 4. RRF score: Σ 1/(k + rank_i). Missing from list → penalty rank = candidateK+1
        let penalty = Float(candidateK + 1)
        var scored = [ScoredMemory]()
        for id in allIds {
            guard let memory = memoryLookup[id] else { continue }
            let rV = vRanks[id] != nil ? Float(vRanks[id]!) : penalty
            let rK = kRanks[id] != nil ? Float(kRanks[id]!) : penalty
            let rG = gRanks[id] != nil ? Float(gRanks[id]!) : penalty
            let rrfScore = 1.0 / (k + rV) + 1.0 / (k + rK) + 1.0 / (k + rG)
            scored.append(ScoredMemory(memory: memory, score: rrfScore))
        }

        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(topK))
    }

    // MARK: - Graph Neighbor Search

    /// Collect 1-hop neighbors of the top-5 seed results, scored by edge confidence
    private func graphNeighborSearch(seedMemories: [ScoredMemory], memoryLookup: [UUID: MemoryNode], topK: Int) -> [ScoredMemory] {
        let seeds = Array(seedMemories.prefix(5))

        var neighborScores = [UUID: Float]()
        for seed in seeds {
            for rel in seed.memory.relationships {
                guard neighborScores[rel.targetId] == nil else { continue }
                neighborScores[rel.targetId] = seed.score * rel.confidence * 0.8
            }
        }

        var results = [ScoredMemory]()
        for (id, score) in neighborScores {
            if let memory = memoryLookup[id] {
                results.append(ScoredMemory(memory: memory, score: score))
            }
        }
        results.sort { $0.score > $1.score }
        return Array(results.prefix(topK))
    }

    // MARK: - Vector Search

    private func vectorSearch(embedding: [Float], memories: [MemoryNode], topK: Int) -> [ScoredMemory] {
        var scored: [ScoredMemory] = []
        for memory in memories {
            let similarity = cosineSimilarity(embedding, memory.embedding)
            scored.append(ScoredMemory(memory: memory, score: similarity))
        }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(topK))
    }

    // MARK: - Keyword Search (BM25-like)

    private func keywordSearch(query: String, memories: [MemoryNode], topK: Int) -> [ScoredMemory] {
        let queryTerms = tokenize(query)
        let totalDocs = memories.count
        let avgDocLength = memories.isEmpty ? 50.0 : Float(memories.reduce(0) { $0 + tokenize($1.content).count }) / Float(totalDocs)

        var scored: [ScoredMemory] = []
        for memory in memories {
            let score = bm25Score(queryTerms: queryTerms, document: memory.content, totalDocs: totalDocs, avgDocLength: avgDocLength)
            scored.append(ScoredMemory(memory: memory, score: score))
        }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(topK))
    }
    
    /// BM25 scoring algorithm
    private func bm25Score(queryTerms: [String], document: String, totalDocs: Int = 100, avgDocLength: Float = 50.0) -> Float {
        let docTerms = tokenize(document)
        let docLength = Float(docTerms.count)
        
        let k1: Float = 1.5
        let b: Float = 0.75
        let n = Float(max(totalDocs, 1))
        
        var score: Float = 0.0
        
        for term in queryTerms {
            let termFreq = Float(docTerms.filter { $0 == term }.count)
            
            if termFreq > 0 {
                // Proper BM25 IDF: log((N - df + 0.5) / (df + 0.5) + 1)
                // Using df=1 as approximation since we score per-document
                let idf = log((n - 1.0 + 0.5) / (1.0 + 0.5) + 1.0)
                let numerator = termFreq * (k1 + 1.0)
                let denominator = termFreq + k1 * (1.0 - b + b * (docLength / avgDocLength))
                
                score += idf * (numerator / denominator)
            }
        }
        
        return score
    }
    
    /// Tokenize text into terms
    private func tokenize(_ text: String) -> [String] {
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 }
    }
}

// MARK: - Re-ranking

/// Re-ranks search results using LLM or advanced scoring
public actor Reranker {
    
    private let config: SwiftMemConfig
    
    public init(config: SwiftMemConfig) {
        self.config = config
    }
    
    /// Re-rank memories based on relevance to query
    public func rerank(
        query: String,
        memories: [ScoredMemory],
        topK: Int = 10
    ) async throws -> [ScoredMemory] {
        
        var reranked: [ScoredMemory] = []
        
        for scoredMemory in memories {
            // Calculate additional relevance factors
            var adjustedScore = scoredMemory.score
            
            // Boost recent memories
            let recencyBoost = calculateRecencyBoost(memory: scoredMemory.memory)
            adjustedScore += recencyBoost * 0.1
            
            // Boost high-confidence memories
            let confidenceBoost = scoredMemory.memory.effectiveConfidence()
            adjustedScore *= confidenceBoost
            
            // Boost static memories (core facts)
            if scoredMemory.memory.isStatic {
                adjustedScore *= 1.2
            }
            
            // Boost frequently accessed memories
            let accessBoost = min(Float(scoredMemory.memory.metadata.accessCount) * 0.05, 0.3)
            adjustedScore += accessBoost
            
            reranked.append(ScoredMemory(memory: scoredMemory.memory, score: adjustedScore))
        }
        
        reranked.sort { $0.score > $1.score }
        return Array(reranked.prefix(topK))
    }
    
    /// v3: Exponential decay per memory type.
    /// static → half-life ~289 days; dynamic → half-life ~3 days
    private func calculateRecencyBoost(memory: MemoryNode) -> Float {
        let hoursSince = Date().timeIntervalSince(memory.timestamp) / 3600.0
        let rate = memory.isStatic
            ? config.memoryDecayConfig.staticDecayRatePerHour
            : config.memoryDecayConfig.dynamicDecayRatePerHour
        return Float(pow(rate, hoursSince))
    }
}

// MARK: - LLM Reranker

/// Re-ranks search results using on-device LLM scoring
public actor LLMReranker {

    private let config: SwiftMemConfig
    private let llmService: LLMService

    public init(config: SwiftMemConfig, llmService: LLMService) {
        self.config = config
        self.llmService = llmService
    }

    /// Rerank memories by asking LLM to score query-memory relevance
    /// Falls back to original order on any failure
    public func rerank(
        query: String,
        memories: [ScoredMemory],
        topK: Int = 10
    ) async -> [ScoredMemory] {
        guard config.llmConfig.enableLLMReranking,
              await llmService.isAvailable,
              !memories.isEmpty else {
            return Array(memories.prefix(topK))
        }

        // Only rerank top-20 candidates for efficiency
        let candidates = Array(memories.prefix(20))

        // Build prompt listing candidates
        var memoryList = ""
        for (i, sm) in candidates.enumerated() {
            let preview = String(sm.memory.content.prefix(150))
            memoryList += "\(i): \(preview)\n"
        }

        let prompt = """
        Score each memory's relevance to the query on a 0.0-1.0 scale.

        Query: \(query)

        Memories:
        \(memoryList)

        Return ONLY a JSON object: {"scores": [0.8, 0.2, ...]}
        One score per memory in the same order. Higher = more relevant.
        """

        let systemPrompt = "You are a relevance scoring system. Return ONLY valid JSON. No explanations."

        guard let response = await llmService.complete(
            prompt: prompt,
            systemPrompt: systemPrompt,
            maxTokens: config.llmConfig.rerankingMaxTokens
        ) else {
            return Array(memories.prefix(topK))
        }

        // Parse scores
        guard let scores = parseLLMScores(response, expectedCount: candidates.count) else {
            return Array(memories.prefix(topK))
        }

        // Blend LLM score (60%) with original score (40%)
        var reranked: [ScoredMemory] = []
        for (i, sm) in candidates.enumerated() {
            let blendedScore = scores[i] * 0.6 + sm.score * 0.4
            reranked.append(ScoredMemory(memory: sm.memory, score: blendedScore))
        }

        reranked.sort { $0.score > $1.score }
        print("✅ [LLMReranker] Reranked \(candidates.count) candidates")
        return Array(reranked.prefix(topK))
    }

    private func parseLLMScores(_ response: String, expectedCount: Int) -> [Float]? {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        else if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scores = json["scores"] as? [Any] else {
            return nil
        }

        let floatScores = scores.compactMap { element -> Float? in
            if let d = element as? Double { return Float(d) }
            if let i = element as? Int { return Float(i) }
            return nil
        }

        guard floatScores.count == expectedCount else { return nil }
        return floatScores.map { min(max($0, 0.0), 1.0) }
    }
}

// MARK: - MMR Diversification

/// Maximal Marginal Relevance diversification to reduce redundancy in results
public func mmrDiversify(
    memories: [ScoredMemory],
    topK: Int,
    lambda: Float = 0.7
) -> [ScoredMemory] {
    guard !memories.isEmpty else { return [] }
    guard memories.count > topK else { return memories }

    var selected: [ScoredMemory] = []
    var remaining = memories

    // Always select the highest-scored memory first
    selected.append(remaining.removeFirst())

    while selected.count < topK && !remaining.isEmpty {
        var bestIdx = 0
        var bestMMR: Float = -Float.infinity

        for (i, candidate) in remaining.enumerated() {
            let relevance = candidate.score

            // Max similarity to any already-selected memory
            var maxSim: Float = 0
            for sel in selected {
                let sim = embeddingCosineSimilarity(candidate.memory.embedding, sel.memory.embedding)
                maxSim = max(maxSim, sim)
            }

            let mmrScore = lambda * relevance - (1.0 - lambda) * maxSim
            if mmrScore > bestMMR {
                bestMMR = mmrScore
                bestIdx = i
            }
        }

        selected.append(remaining.remove(at: bestIdx))
    }

    return selected
}

// MARK: - Supporting Types

public struct ScoredMemory {
    public let memory: MemoryNode
    public let score: Float
}

// MARK: - Cosine Similarity (v3: vDSP-accelerated, 10-40x faster than scalar)

private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    let n = vDSP_Length(a.count)
    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    vDSP_dotpr(a, 1, b, 1, &dot, n)
    vDSP_dotpr(a, 1, a, 1, &normA, n)
    vDSP_dotpr(b, 1, b, 1, &normB, n)
    let denom = sqrtf(normA) * sqrtf(normB)
    return denom > 0 ? dot / denom : 0
}

/// Package-internal cosine similarity for embeddings (used by MMR and contradiction detection)
func embeddingCosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    return cosineSimilarity(a, b)
}
