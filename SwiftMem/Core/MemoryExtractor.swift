//
//  MemoryExtractor.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation

/// Automatically extracts structured memories from conversations
public actor MemoryExtractor {
    
    private let config: SwiftMemConfig
    private let relationshipDetector: RelationshipDetector
    
    public init(config: SwiftMemConfig, relationshipDetector: RelationshipDetector) {
        self.config = config
        self.relationshipDetector = relationshipDetector
    }
    
    // MARK: - Memory Extraction
    
    /// Extract memories from a conversation
    public func extractMemories(
        from conversation: String,
        userId: String,
        embedder: Embedder
    ) async throws -> [ExtractedMemory] {
        
        // 1. Use LLM to extract structured facts
        let extractedFacts = try await extractFactsWithLLM(conversation: conversation)
        
        // 2. Generate embeddings for each fact
        var memories: [ExtractedMemory] = []
        
        for fact in extractedFacts {
            let embedding = try await embedder.embed(fact.content)
            
            let memory = ExtractedMemory(
                content: fact.content,
                embedding: embedding,
                type: fact.type,
                entities: fact.entities,
                topics: fact.topics,
                importance: fact.importance,
                confidence: fact.confidence,
                userId: userId
            )
            
            memories.append(memory)
        }
        
        return memories
    }
    
    /// Extract facts using LLM
    private func extractFactsWithLLM(conversation: String) async throws -> [ConversationFact] {
        let prompt = """
        Extract structured memories from this conversation. Focus on:
        1. Facts about the user (preferences, work, life)
        2. Events and experiences
        3. Relationships and people
        4. Goals and plans
        
        Conversation:
        \(conversation)
        
        Return JSON array:
        [
          {
            "content": "clear, concise fact",
            "type": "fact|preference|event|goal",
            "entities": ["person", "place", "thing"],
            "topics": ["work", "personal", "hobby"],
            "importance": 0.0-1.0,
            "confidence": 0.0-1.0
          }
        ]
        
        Only extract meaningful, specific information. Avoid generic statements.
        """
        
        // Call LLM (placeholder - will integrate with Qwen)
        // For now, use heuristic extraction
        return extractFactsHeuristic(from: conversation)
    }
    
    /// Heuristic-based fact extraction (fallback)
    private func extractFactsHeuristic(from text: String) -> [ConversationFact] {
        var facts: [ConversationFact] = []
        
        // Split into sentences
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        for sentence in sentences {
            // Check if sentence contains factual information
            if containsFactualKeywords(sentence) {
                let type = classifyFactType(sentence)
                let entities = extractEntities(sentence)
                let topics = extractTopics(sentence)
                let importance = calculateImportance(sentence)
                
                facts.append(ConversationFact(
                    content: sentence,
                    type: type,
                    entities: entities,
                    topics: topics,
                    importance: importance,
                    confidence: 0.7
                ))
            }
        }
        
        return facts
    }
    
    // MARK: - Heuristic Helpers
    
    private func containsFactualKeywords(_ text: String) -> Bool {
        let factKeywords = [
            "i am", "i'm", "my name", "i work", "i like", "i love", "i prefer",
            "i went", "i did", "i plan", "i want", "i need",
            "works at", "lives in", "born in", "graduated from"
        ]
        
        let lowercased = text.lowercased()
        return factKeywords.contains { lowercased.contains($0) }
    }
    
    private func classifyFactType(_ text: String) -> ExtractedMemoryType {
        let lowercased = text.lowercased()
        
        if lowercased.contains("prefer") || lowercased.contains("like") || lowercased.contains("love") {
            return .preference
        } else if lowercased.contains("went") || lowercased.contains("did") || lowercased.contains("happened") {
            return .event
        } else if lowercased.contains("plan") || lowercased.contains("want") || lowercased.contains("goal") {
            return .goal
        } else {
            return .fact
        }
    }
    
    private func extractEntities(_ text: String) -> [String] {
        // Simple entity extraction (would use NER in production)
        var entities: [String] = []
        
        // Extract capitalized words (potential proper nouns)
        let words = text.split(separator: " ")
        for word in words {
            let wordStr = String(word)
            if wordStr.first?.isUppercase == true && wordStr.count > 2 {
                entities.append(wordStr)
            }
        }
        
        return entities
    }
    
    private func extractTopics(_ text: String) -> [String] {
        var topics: [String] = []
        let lowercased = text.lowercased()
        
        let topicKeywords: [String: [String]] = [
            "work": ["work", "job", "career", "office", "company", "project"],
            "personal": ["family", "friend", "relationship", "home", "life"],
            "hobby": ["hobby", "interest", "enjoy", "fun", "play", "sport"],
            "health": ["health", "exercise", "diet", "sleep", "wellness"],
            "learning": ["learn", "study", "course", "book", "education"]
        ]
        
        for (topic, keywords) in topicKeywords {
            if keywords.contains(where: { lowercased.contains($0) }) {
                topics.append(topic)
            }
        }
        
        return topics
    }
    
    private func calculateImportance(_ text: String) -> Float {
        var importance: Float = 0.5
        
        // Boost for personal pronouns
        if text.lowercased().contains("i ") || text.lowercased().contains("my ") {
            importance += 0.2
        }
        
        // Boost for strong emotions
        let emotionWords = ["love", "hate", "amazing", "terrible", "important", "critical"]
        if emotionWords.contains(where: { text.lowercased().contains($0) }) {
            importance += 0.2
        }
        
        // Boost for definitive statements
        if text.lowercased().contains("always") || text.lowercased().contains("never") {
            importance += 0.1
        }
        
        return min(importance, 1.0)
    }
    
    // MARK: - Batch Processing
    
    /// Extract memories from multiple conversations
    public func extractMemoriesBatch(
        conversations: [(id: String, content: String)],
        userId: String,
        embedder: Embedder
    ) async throws -> [String: [ExtractedMemory]] {
        
        var results: [String: [ExtractedMemory]] = [:]
        
        for (id, content) in conversations {
            let memories = try await extractMemories(
                from: content,
                userId: userId,
                embedder: embedder
            )
            results[id] = memories
        }
        
        return results
    }
}

// MARK: - Supporting Types

/// Memory type classification for extraction
public enum ExtractedMemoryType: String, Codable {
    case fact
    case preference
    case event
    case goal
}

/// Extracted fact from conversation
public struct ConversationFact {
    let content: String
    let type: ExtractedMemoryType
    let entities: [String]
    let topics: [String]
    let importance: Float
    let confidence: Float
}

/// Extracted memory ready to be stored
public struct ExtractedMemory {
    public let content: String
    public let embedding: [Float]
    public let type: ExtractedMemoryType
    public let entities: [String]
    public let topics: [String]
    public let importance: Float
    public let confidence: Float
    public let userId: String
    
    /// Convert to MemoryNode
    public func toMemoryNode() -> MemoryNode {
        return MemoryNode(
            content: content,
            embedding: embedding,
            confidence: confidence,
            metadata: MemoryMetadata(
                source: .conversation,
                entities: entities,
                topics: topics,
                importance: importance
            )
        )
    }
}
