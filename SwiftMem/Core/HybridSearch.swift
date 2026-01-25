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
        
        var scored: [ScoredMemory] = []
        
        for memory in allMemories {
            let score = bm25Score(queryTerms: queryTerms, document: memory.content)
            scored.append(ScoredMemory(memory: memory, score: score))
        }
        
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(topK))
    }
    
    /// BM25 scoring algorithm
    private func bm25Score(queryTerms: [String], document: String) -> Float {
        let docTerms = tokenize(document)
        let docLength = Float(docTerms.count)
        let avgDocLength: Float = 50.0 // Approximate
        
        let k1: Float = 1.5
        let b: Float = 0.75
        
        var score: Float = 0.0
        
        for term in queryTerms {
            let termFreq = Float(docTerms.filter { $0 == term }.count)
            
            if termFreq > 0 {
                let idf = log((1.0 + Float(1)) / (termFreq + 1.0))
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
