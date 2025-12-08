//
//  Types.swift
//  SwiftMem
//
//  Core data structures for graph-based memory system
//

import Foundation

// MARK: - Identifiers

/// Type-safe identifier for memory nodes
public struct NodeID: Hashable, Codable, CustomStringConvertible {
    public let value: UUID
    
    public init() {
        self.value = UUID()
    }
    
    public init(value: UUID) {
        self.value = value
    }
    
    public var description: String {
        value.uuidString
    }
}

/// Type-safe identifier for relationships between nodes
public struct EdgeID: Hashable, Codable, CustomStringConvertible {
    public let value: UUID
    
    public init() {
        self.value = UUID()
    }
    
    public init(value: UUID) {
        self.value = value
    }
    
    public var description: String {
        value.uuidString
    }
}

// MARK: - Memory Types

/// Categories of memories stored in the graph
public enum MemoryType: String, Codable, CaseIterable {
    /// Event-based memories (e.g., "User mentioned stress on Dec 5th")
    case episodic
    
    /// Factual knowledge (e.g., "User's mom's birthday is June 15th")
    case semantic
    
    /// Procedural knowledge (e.g., "User prefers morning workouts")
    case procedural
    
    /// Emotional states (e.g., "User felt anxious about presentation")
    case emotional
    
    /// Conversation turns
    case conversation
    
    /// User goals and objectives
    case goal
    
    /// General/unspecified memory
    case general
}

/// Types of entities that can be extracted from memories
public enum EntityType: String, Codable, CaseIterable {
    case person
    case location
    case organization
    case date
    case event
    case topic
    case emotion
    case goal
    case project
    case other
}

// MARK: - Node (Memory)

/// Represents a single memory or piece of information in the graph
public struct Node: Identifiable, Codable, Equatable {
    public let id: NodeID
    
    /// The actual content/text of the memory
    public let content: String
    
    /// Type of memory
    public let type: MemoryType
    
    /// Custom metadata as JSON-compatible dictionary
    public var metadata: [String: MetadataValue]
    
    /// When this memory was created in the system
    public let createdAt: Date
    
    /// When this memory was last updated
    public var updatedAt: Date
    
    /// When the conversation/document actually took place (defaults to createdAt)
    /// Use this for batch imports where conversation happened in the past
    public let conversationDate: Date
    
    /// When the event/fact being described actually occurred (optional)
    /// e.g., "Yesterday I went hiking" → eventDate would be yesterday
    /// Enables temporal reasoning: "What did I do last week?"
    public let eventDate: Date?
    
    /// Vector embedding of the content (stored separately in VectorStore)
    /// This is just for reference - actual storage happens in VectorStore
    public var hasEmbedding: Bool = false
    
    public init(
        id: NodeID = NodeID(),
        content: String,
        type: MemoryType = .general,
        metadata: [String: MetadataValue] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        conversationDate: Date? = nil,  // Defaults to createdAt if nil
        eventDate: Date? = nil,
        hasEmbedding: Bool = false
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.conversationDate = conversationDate ?? createdAt  // Backward compatible
        self.eventDate = eventDate
        self.hasEmbedding = hasEmbedding
    }
}

// MARK: - Filters

/// Filters for querying nodes
public enum NodeFilter {
    case type(MemoryType)
    case createdAfter(Date)
    case createdBefore(Date)
    case contentContains(String)
    case metadataKey(String)
    case metadataValue(String, MetadataValue)
}

// MARK: - Edge (Relationship)

/// Semantic relationship types between memories (inspired by knowledge graphs)
public enum RelationshipType: String, Codable, CaseIterable {
    /// Generic relationship
    case related = "related"
    
    /// Knowledge update relationships
    case updates = "updates"          // New info replaces old (e.g., "color is now green" updates "color is blue")
    case extends = "extends"          // New info adds detail (e.g., adds job title to employment record)
    case supersedes = "supersedes"    // Completely replaces (stronger than updates)
    case derives = "derives"          // Inferred from multiple sources
    
    /// Temporal relationships
    case followedBy = "followed_by"   // Sequential events
    case precedes = "precedes"        // Opposite of followedBy
    case causes = "causes"            // Causal relationship
    
    /// Hierarchical relationships
    case partOf = "part_of"           // Component relationship
    case contains = "contains"        // Opposite of partOf
    case subtopicOf = "subtopic_of"   // Topic hierarchy
    
    /// Associative relationships
    case similarTo = "similar_to"     // Semantic similarity
    case oppositeOf = "opposite_of"   // Contrasting concepts
    case mentions = "mentions"        // References another memory
    
    /// Session relationships
    case sameSession = "same_session" // From same conversation
    case references = "references"    // Explicit reference to previous memory
}

/// Represents a relationship between two nodes in the graph
public struct Edge: Identifiable, Codable, Equatable {
    public let id: EdgeID
    
    /// Source node
    public let fromNodeID: NodeID
    
    /// Target node
    public let toNodeID: NodeID
    
    /// Type of relationship
    public let relationshipType: RelationshipType
    
    /// Strength of the relationship (0.0 to 1.0)
    public let weight: Double
    
    /// When this relationship was created
    public let createdAt: Date
    
    /// Custom metadata
    public var metadata: [String: MetadataValue]
    
    public init(
        id: EdgeID = EdgeID(),
        fromNodeID: NodeID,
        toNodeID: NodeID,
        relationshipType: RelationshipType = .related,
        weight: Double = 1.0,
        createdAt: Date = Date(),
        metadata: [String: MetadataValue] = [:]
    ) {
        self.id = id
        self.fromNodeID = fromNodeID
        self.toNodeID = toNodeID
        self.relationshipType = relationshipType
        self.weight = min(max(weight, 0.0), 1.0) // Clamp between 0 and 1
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

// MARK: - Entity

/// Represents an extracted entity from memory content
public struct Entity: Identifiable, Codable, Equatable {
    public let id: NodeID
    
    /// Entity name (e.g., "Sarah", "Phoenix", "Starbucks")
    public let name: String
    
    /// Type of entity
    public let type: EntityType
    
    /// Source node this entity was extracted from
    public let sourceNodeID: NodeID
    
    /// Confidence score of extraction (0.0 to 1.0)
    public let confidence: Double
    
    /// Additional attributes
    public var attributes: [String: MetadataValue]
    
    public init(
        id: NodeID = NodeID(),
        name: String,
        type: EntityType,
        sourceNodeID: NodeID,
        confidence: Double = 1.0,
        attributes: [String: MetadataValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.sourceNodeID = sourceNodeID
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.attributes = attributes
    }
}

// MARK: - Metadata Value

/// Type-safe metadata values that can be stored in nodes/edges
public enum MetadataValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case array([MetadataValue])
    case dictionary([String: MetadataValue])
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Date.self) {
            self = .date(value)
        } else if let value = try? container.decode([MetadataValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: MetadataValue].self) {
            self = .dictionary(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported metadata value type"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .date(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Retrieval Types

/// Strategy for retrieving memories from the graph
public enum RetrievalStrategy {
    /// Pure vector similarity search
    case vector
    
    /// Graph traversal only
    case graph
    
    /// Combination of vector and graph (recommended)
    case hybrid
    
    /// Time-based retrieval (most recent first)
    case temporal
    
    /// Custom retrieval function
    case custom((String) async throws -> [Node])
}

/// Format for context returned to LLMs
public enum ContextFormat {
    /// Natural conversational format
    /// "In previous conversations, you mentioned..."
    case conversational
    
    /// Bullet point list
    /// "- User mentioned X\n- User struggles with Y"
    case bulletPoints
    
    /// Structured JSON format for function calling
    case structured
    
    /// Raw text chunks without formatting
    case raw
}

/// A node with its similarity/relevance score
public struct ScoredNode: Identifiable, Equatable {
    public let node: Node
    
    /// Relevance score (0.0 to 1.0, higher is more relevant)
    public let score: Double
    
    /// Why this node was retrieved (for debugging/transparency)
    public let reason: String
    
    public var id: NodeID {
        node.id
    }
    
    public init(node: Node, score: Double, reason: String = "") {
        self.node = node
        self.score = min(max(score, 0.0), 1.0)
        self.reason = reason
    }
}

/// Result of a retrieval query
public struct RetrievalResult: Equatable {
    /// Retrieved nodes with scores
    public let nodes: [ScoredNode]
    
    /// Formatted context ready for LLM
    public let formattedContext: String
    
    /// Metadata about the retrieval
    public let metadata: RetrievalMetadata
    
    public init(
        nodes: [ScoredNode],
        formattedContext: String,
        metadata: RetrievalMetadata
    ) {
        self.nodes = nodes
        self.formattedContext = formattedContext
        self.metadata = metadata
    }
}

/// Metadata about a retrieval operation
public struct RetrievalMetadata: Equatable {
    /// Strategy used for retrieval
    public let strategy: String
    
    /// Number of nodes searched
    public let nodesSearched: Int
    
    /// Time taken for retrieval (in seconds)
    public let retrievalTime: TimeInterval
    
    /// Number of tokens in formatted context (estimate)
    public let estimatedTokens: Int
    
    public init(
        strategy: String,
        nodesSearched: Int,
        retrievalTime: TimeInterval,
        estimatedTokens: Int
    ) {
        self.strategy = strategy
        self.nodesSearched = nodesSearched
        self.retrievalTime = retrievalTime
        self.estimatedTokens = estimatedTokens
    }
}

// MARK: - Timeline Event

/// Represents a memory in a chronological timeline
public struct TimelineEvent: Identifiable, Equatable {
    public let id: NodeID
    public let node: Node
    public let timestamp: Date
    
    public init(id: NodeID, node: Node, timestamp: Date) {
        self.id = id
        self.node = node
        self.timestamp = timestamp
    }
}

// MARK: - Conversation Context

/// Context for a conversation session with relevant memories
public struct ConversationContext: Equatable {
    /// Session identifier
    public let sessionID: String
    
    /// Messages in this session
    public let messages: [ConversationMessage]
    
    /// Relevant memories retrieved for this context
    public let relevantMemories: [ScoredNode]
    
    /// Formatted context for LLM
    public let formattedContext: String
    
    /// Estimated token count
    public let estimatedTokens: Int
    
    public init(
        sessionID: String,
        messages: [ConversationMessage],
        relevantMemories: [ScoredNode],
        formattedContext: String,
        estimatedTokens: Int
    ) {
        self.sessionID = sessionID
        self.messages = messages
        self.relevantMemories = relevantMemories
        self.formattedContext = formattedContext
        self.estimatedTokens = estimatedTokens
    }
}

/// A single message in a conversation
public struct ConversationMessage: Identifiable, Codable, Equatable {
    public let id: NodeID
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    
    public init(
        id: NodeID = NodeID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// Role in a conversation
public enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - Memory Insights

/// Analytics and insights about stored memories
public struct MemoryInsights: Equatable {
    /// Total number of nodes
    public let totalNodes: Int
    
    /// Total number of relationships
    public let totalRelationships: Int
    
    /// Top entities by frequency
    public let topEntities: [EntityFrequency]
    
    /// Most frequent topics/keywords
    public let frequentTopics: [String: Int]
    
    /// Storage size in bytes
    public let storageSize: Int64
    
    /// Date range of memories
    public let dateRange: DateInterval?
    
    public init(
        totalNodes: Int,
        totalRelationships: Int,
        topEntities: [EntityFrequency],
        frequentTopics: [String: Int],
        storageSize: Int64,
        dateRange: DateInterval?
    ) {
        self.totalNodes = totalNodes
        self.totalRelationships = totalRelationships
        self.topEntities = topEntities
        self.frequentTopics = frequentTopics
        self.storageSize = storageSize
        self.dateRange = dateRange
    }
}

/// Entity with frequency count
public struct EntityFrequency: Equatable {
    public let entity: Entity
    public let count: Int
    
    public init(entity: Entity, count: Int) {
        self.entity = entity
        self.count = count
    }
}

// MARK: - Errors

/// Errors that can occur in SwiftMem operations
public enum SwiftMemError: Error, LocalizedError {
    case storageError(String)
    case embeddingError(String)
    case retrievalError(String)
    case configurationError(String)
    case nodeNotFound(NodeID)
    case edgeNotFound(EdgeID)
    case invalidData(String)
    
    public var errorDescription: String? {
        switch self {
        case .storageError(let message):
            return "Storage error: \(message)"
        case .embeddingError(let message):
            return "Embedding error: \(message)"
        case .retrievalError(let message):
            return "Retrieval error: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .nodeNotFound(let id):
            return "Node not found: \(id)"
        case .edgeNotFound(let id):
            return "Edge not found: \(id)"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        }
    }
}
