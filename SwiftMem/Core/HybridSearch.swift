//
//  HybridSearch.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation

/// Hybrid search combining vector similarity and keyword matching
public actor HybridSearch {
    
    private let memoryGraphStore: MemoryGraphStore
    private let config: SwiftMemConfig
    
    public init(memoryGraphStore: MemoryGraphStore, config: SwiftMemConfig) {
        self.memoryGraphStore = memoryGraphStore
        self.config = config
    }
    
    // MARK: - Hybrid Search
    
    /// Search memories using hybrid approach (vector + keyword)
    public func search(
        query: String,
        queryEmbedding: [Float],
        topK: Int = 10,
        vectorWeight: Float = 0.7,
        keywordWeight: Float = 0.3
    ) async throws -> [ScoredMemory] {
        
        // 1. Vector similarity search
        let vectorResults = try await vectorSearch(embedding: queryEmbedding, topK: topK * 2)
        
        // 2. Keyword search (BM25-like)
        let keywordResults = await keywordSearch(query: query, topK: topK * 2)
        
        // 3. Combine scores
        var combinedScores: [UUID: Float] = [:]
        
        for result in vectorResults {
            combinedScores[result.memory.id] = result.score * vectorWeight
        }
        
        for result in keywordResults {
            let existingScore = combinedScores[result.memory.id] ?? 0
            combinedScores[result.memory.id] = existingScore + (result.score * keywordWeight)
        }
        
        // 4. Sort by combined score
        let allMemories = await memoryGraphStore.getAllMemories()
        var scoredMemories: [ScoredMemory] = []
        
        for (memoryId, score) in combinedScores {
            if let memory = allMemories.first(where: { $0.id == memoryId }) {
                scoredMemories.append(ScoredMemory(memory: memory, score: score))
            }
        }
        
        scoredMemories.sort { $0.score > $1.score }
        
        return Array(scoredMemories.prefix(topK))
    }
    
    // MARK: - Vector Search
    
    private func vectorSearch(embedding: [Float], topK: Int) async throws -> [ScoredMemory] {
        let allMemories = await memoryGraphStore.getAllMemories()
        
        var scored: [ScoredMemory] = []
        
        for memory in allMemories {
            let similarity = cosineSimilarity(embedding, memory.embedding)
            scored.append(ScoredMemory(memory: memory, score: similarity))
        }
        
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(topK))
    }
    
    // MARK: - Keyword Search (BM25-like)
    
    private func keywordSearch(query: String, topK: Int) async -> [ScoredMemory] {
        let queryTerms = tokenize(query)
        let allMemories = await memoryGraphStore.getAllMemories()
        
        let totalDocs = allMemories.count
        let avgDocLength = allMemories.isEmpty ? 50.0 : Float(allMemories.reduce(0) { $0 + tokenize($1.content).count }) / Float(totalDocs)
        
        var scored: [ScoredMemory] = []
        
        for memory in allMemories {
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
    
    private func calculateRecencyBoost(memory: MemoryNode) -> Float {
        let daysSinceCreation = Date().timeIntervalSince(memory.timestamp) / 86400
        
        if daysSinceCreation < 1 {
            return 1.0
        } else if daysSinceCreation < 7 {
            return 0.5
        } else if daysSinceCreation < 30 {
            return 0.2
        } else {
            return 0.0
        }
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

// MARK: - Cosine Similarity

private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count else { return 0 }

    var dotProduct: Float = 0
    var normA: Float = 0
    var normB: Float = 0

    for i in 0..<a.count {
        dotProduct += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }

    let denominator = sqrt(normA) * sqrt(normB)
    return denominator > 0 ? dotProduct / denominator : 0
}

/// Package-internal cosine similarity for embeddings (used by MMR)
func embeddingCosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    return cosineSimilarity(a, b)
}
