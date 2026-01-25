//
//  MemoryNode.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation

/// A node in the memory graph representing a single piece of knowledge
public struct MemoryNode: Identifiable, Codable, Equatable {
    public let id: UUID
    public let content: String
    public let embedding: [Float]
    public let timestamp: Date
    public var confidence: Float
    public var relationships: [MemoryRelationship]
    public var metadata: MemoryMetadata
    public var isLatest: Bool  // For UPDATES relationships
    public var isStatic: Bool  // Core facts vs episodic memories
    public var containerTags: [String]  // Session/topic/category tags for filtering
    
    public init(
        id: UUID = UUID(),
        content: String,
        embedding: [Float],
        timestamp: Date = Date(),
        confidence: Float = 1.0,
        relationships: [MemoryRelationship] = [],
        metadata: MemoryMetadata = MemoryMetadata(),
        isLatest: Bool = true,
        isStatic: Bool = false,
        containerTags: [String] = []
    ) {
        self.id = id
        self.content = content
        self.embedding = embedding
        self.timestamp = timestamp
        self.confidence = confidence
        self.relationships = relationships
        self.metadata = metadata
        self.isLatest = isLatest
        self.isStatic = isStatic
        self.containerTags = containerTags
    }
}

/// Relationship between memory nodes
public struct MemoryRelationship: Codable, Equatable {
    public let type: RelationType
    public let targetId: UUID
    public let confidence: Float
    public let timestamp: Date
    
    public init(
        type: RelationType,
        targetId: UUID,
        confidence: Float = 1.0,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.targetId = targetId
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// Types of relationships between memories
public enum RelationType: String, Codable, Equatable {
    /// New information supersedes old information (temporal update)
    /// Example: "Alex works at Google" → "Alex works at Stripe"
    case updates
    
    /// New information enriches existing information (additive)
    /// Example: "Alex is PM" → "Alex leads payments team of 5"
    case extends
    
    /// Information inferred from multiple memories (derived)
    /// Example: From "PM at Stripe" + "discusses APIs" → "Works on core payments"
    case derives
    
    /// Contradicts existing information (conflict)
    case contradicts
    
    /// Related but not directly connected
    case relatedTo
}

/// Metadata for a memory node
public struct MemoryMetadata: Codable, Equatable {
    public var source: MemorySource
    public var entities: [String]
    public var topics: [String]
    public var importance: Float
    public var accessCount: Int
    public var lastAccessed: Date?
    public var userConfirmed: Bool
    
    public init(
        source: MemorySource = .conversation,
        entities: [String] = [],
        topics: [String] = [],
        importance: Float = 0.5,
        accessCount: Int = 0,
        lastAccessed: Date? = nil,
        userConfirmed: Bool = false
    ) {
        self.source = source
        self.entities = entities
        self.topics = topics
        self.importance = importance
        self.accessCount = accessCount
        self.lastAccessed = lastAccessed
        self.userConfirmed = userConfirmed
    }
}

/// Source of a memory
public enum MemorySource: String, Codable, Equatable {
    case conversation
    case document
    case userInput
    case derived
    case imported
}

// MARK: - Memory Classification

extension MemoryNode {
    /// Calculate decay factor based on age and access
    public func decayFactor(currentDate: Date = Date()) -> Float {
        let daysSinceCreation = currentDate.timeIntervalSince(timestamp) / 86400
        let daysSinceAccess = metadata.lastAccessed.map { currentDate.timeIntervalSince($0) / 86400 } ?? daysSinceCreation
        
        // Static memories decay slower
        let decayRate: Float = isStatic ? 0.01 : 0.05
        
        // Access boosts relevance
        let accessBoost = Float(min(metadata.accessCount, 10)) * 0.1
        
        let ageFactor = exp(-decayRate * Float(daysSinceCreation))
        let accessFactor = exp(-decayRate * Float(daysSinceAccess)) + accessBoost
        
        return min(ageFactor * accessFactor, 1.0)
    }
    
    /// Current effective confidence considering decay
    public func effectiveConfidence(currentDate: Date = Date()) -> Float {
        return confidence * decayFactor(currentDate: currentDate)
    }
}

// MARK: - Graph Operations

extension MemoryNode {
    /// Add a relationship to another memory
    public mutating func addRelationship(_ relationship: MemoryRelationship) {
        // Remove existing relationship to same target if exists
        relationships.removeAll { $0.targetId == relationship.targetId && $0.type == relationship.type }
        relationships.append(relationship)
        
        // If this is an UPDATES relationship, mark this as latest
        if relationship.type == .updates {
            isLatest = true
        }
    }
    
    /// Get all relationships of a specific type
    public func relationships(ofType type: RelationType) -> [MemoryRelationship] {
        return relationships.filter { $0.type == type }
    }
    
    /// Check if this memory is superseded by another
    public var isSuperseded: Bool {
        return !isLatest && relationships.contains { $0.type == .updates }
    }
}
