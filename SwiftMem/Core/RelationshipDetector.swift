//
//  RelationshipDetector.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation

/// Detects relationships between memories using embedding similarity
public actor RelationshipDetector {
    
    private let config: SwiftMemConfig
    
    // Lowered threshold for local-first approach: 20% similarity for relationships
    // Jaccard similarity on short topic/keyword lists needs much lower thresholds
    private let similarityThreshold: Float = 0.2
    
    // k-NN optimization: only compare with top K most similar memories
    private let maxComparisons: Int = 10
    
    public init(config: SwiftMemConfig) {
        self.config = config
    }
    
    // MARK: - Relationship Detection
    
    /// Detect relationships between a new memory and existing memories using embedding similarity
    public func detectRelationships(
        newMemory: MemoryNode,
        existingMemories: [MemoryNode]
    ) async throws -> [DetectedRelationship] {
        
        guard !newMemory.embedding.isEmpty else {
            return []
        }
        
        var relationships: [DetectedRelationship] = []
        
        // k-NN optimization: Find top K most similar memories
        let similarMemories = findMostSimilar(
            target: newMemory,
            candidates: existingMemories,
            topK: maxComparisons
        )
        
        print("🔗 [RelationshipDetector] Found \(similarMemories.count) similar memories above threshold \(similarityThreshold)")
        
        for (memory, similarity) in similarMemories {
            // Determine relationship type based on similarity and context
            if let relationship = determineRelationshipType(
                new: newMemory,
                existing: memory,
                similarity: similarity
            ) {
                relationships.append(relationship)
                print("  → \(relationship.type): \(memory.id.uuidString.prefix(8))... (similarity: \(similarity), confidence: \(relationship.confidence))")
            }
        }
        
        return relationships
    }
    
    // MARK: - Embedding-Based Similarity
    
    /// Find most similar memories using cosine similarity (k-NN optimization)
    private func findMostSimilar(
        target: MemoryNode,
        candidates: [MemoryNode],
        topK: Int
    ) -> [(MemoryNode, Float)] {
        
        var similarities: [(MemoryNode, Float)] = []
        
        for candidate in candidates {
            guard !candidate.embedding.isEmpty else { continue }
            guard candidate.id != target.id else { continue }
            
            let similarity = cosineSimilarity(target.embedding, candidate.embedding)
            
            // Only consider memories above threshold (0.725)
            if similarity >= similarityThreshold {
                similarities.append((candidate, similarity))
            }
        }
        
        // Sort by similarity and take top K
        return similarities
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0 }
    }
    
    /// Determine relationship type based on similarity and context
    private func determineRelationshipType(
        new: MemoryNode,
        existing: MemoryNode,
        similarity: Float
    ) -> DetectedRelationship? {
        
        // High similarity (>0.50) + temporal ordering = UPDATES
        // Jaccard similarity needs much lower thresholds for short topic/keyword lists
        if similarity > 0.50 && new.timestamp > existing.timestamp {
            return DetectedRelationship(
                type: .updates,
                targetId: existing.id,
                confidence: similarity,
                reason: "High similarity with temporal superseding"
            )
        }
        
        // Medium-high similarity (>0.35) + shared entities/topics = EXTENDS
        // Lower threshold for keyword/topic overlap
        if similarity > 0.35 {
            let sharedEntities = !Set(existing.metadata.entities).isDisjoint(with: new.metadata.entities)
            let sharedTopics = !Set(existing.metadata.topics).isDisjoint(with: new.metadata.topics)
            if (sharedEntities && !existing.metadata.entities.isEmpty) || 
               (sharedTopics && !existing.metadata.topics.isEmpty) {
                return DetectedRelationship(
                    type: .extends,
                    targetId: existing.id,
                    confidence: similarity,
                    reason: "Related content with shared context"
                )
            }
        }
        
        // Medium similarity (>0.20) + shared topics = RELATEDTO
        // Base threshold for any keyword/topic overlap
        if similarity >= similarityThreshold {
            return DetectedRelationship(
                type: .relatedTo,
                targetId: existing.id,
                confidence: similarity,
                reason: "Semantically related content"
            )
        }
        
        return nil
    }
    
    /// Calculate cosine similarity between two embeddings
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
    
    // MARK: - Batch Processing
    
    /// Detect relationships for multiple new memories
    public func detectRelationshipsBatch(
        newMemories: [MemoryNode],
        existingMemories: [MemoryNode]
    ) async throws -> [UUID: [DetectedRelationship]] {
        
        var results: [UUID: [DetectedRelationship]] = [:]
        
        for newMemory in newMemories {
            let relationships = try await detectRelationships(
                newMemory: newMemory,
                existingMemories: existingMemories
            )
            results[newMemory.id] = relationships
        }
        
        return results
    }
}

// MARK: - Supporting Types

/// A detected relationship with confidence score
public struct DetectedRelationship {
    public let type: RelationType
    public let targetId: UUID
    public let confidence: Float
    public let reason: String
    
    public init(type: RelationType, targetId: UUID, confidence: Float, reason: String) {
        self.type = type
        self.targetId = targetId
        self.confidence = confidence
        self.reason = reason
    }
}

// MARK: - LLM Integration

extension RelationshipDetector {
    /// Call LLM for relationship detection (to be implemented with actual LLM)
    private func callLLM(prompt: String) async throws -> String {
        // This will integrate with Qwen or other LLM
        // For now, return empty string (heuristics will be used)
        return ""
    }
    
    /// Parse LLM JSON response
    private func parseLLMResponse(_ response: String) -> (isRelated: Bool, confidence: Float, reason: String)? {
        // Parse JSON response from LLM
        // For now, return nil (heuristics will be used)
        return nil
    }
}
