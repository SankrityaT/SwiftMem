//
//  AdvancedTypes.swift
//  SwiftMem
//
//  SOTA Architecture Data Models
//  Future-proof design ready for LLM enhancement
//

import Foundation

// MARK: - Fact Triple (Knowledge Graph Foundation)

/// A structured fact extracted from memory content
/// Subject-Predicate-Object triple for deterministic contradiction detection
public struct Fact: Codable, Hashable, Identifiable {
    public let id: UUID

    /// The subject of the fact (e.g., "user", "mom", "boss")
    public let subject: String

    /// The relationship/predicate (e.g., "lives_in", "birthday", "likes")
    public let predicate: String

    /// The value/object (e.g., "NYC", "June 15", "morning runs")
    public let object: String

    /// Category of predicate for contradiction rules
    public let predicateCategory: PredicateCategory

    /// Confidence in extraction (0.0 to 1.0)
    public let confidence: Float

    /// Source memory this fact was extracted from
    public let sourceMemoryId: UUID

    /// When this fact became valid (for temporal reasoning)
    public let validFrom: Date?

    /// When this fact expires (for time-bound facts)
    public let validUntil: Date?

    /// How this fact was detected
    public let detectionMethod: FactDetectionMethod

    public init(
        id: UUID = UUID(),
        subject: String,
        predicate: String,
        object: String,
        predicateCategory: PredicateCategory,
        confidence: Float = 0.8,
        sourceMemoryId: UUID,
        validFrom: Date? = nil,
        validUntil: Date? = nil,
        detectionMethod: FactDetectionMethod = .patternMatch
    ) {
        self.id = id
        self.subject = subject.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.predicate = predicate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.object = object.trimmingCharacters(in: .whitespacesAndNewlines)
        self.predicateCategory = predicateCategory
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.sourceMemoryId = sourceMemoryId
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.detectionMethod = detectionMethod
    }

    /// Normalized key for fast lookup (subject + predicate)
    public var lookupKey: String {
        "\(subject):\(predicate)"
    }
}

/// Categories of predicates for contradiction detection rules
public enum PredicateCategory: String, Codable, CaseIterable {
    /// Location-based facts (can only be in one place) - MUTUALLY EXCLUSIVE
    case location           // lives_in, works_at, located_in

    /// Relationship facts (typically singular) - MUTUALLY EXCLUSIVE
    case relationship       // mother_of, partner_of, boss_is

    /// Preference facts (can have multiple) - NOT EXCLUSIVE
    case preference         // likes, dislikes, prefers

    /// Attribute facts (singular values) - MUTUALLY EXCLUSIVE
    case attribute          // age, birthday, job_title, name

    /// State facts (current emotional/physical state) - NOT EXCLUSIVE
    case state              // feeling, health_status, energy_level

    /// Goal facts (can have multiple) - NOT EXCLUSIVE
    case goal               // wants_to, planning_to, working_on

    /// Temporal facts (events with time) - NOT EXCLUSIVE
    case temporal           // started, ended, scheduled_for

    /// Belief/opinion facts - NOT EXCLUSIVE
    case belief             // thinks, believes, values

    /// Habit/routine facts - NOT EXCLUSIVE
    case habit              // usually, always, never

    /// Whether facts in this category are mutually exclusive
    public var isMutuallyExclusive: Bool {
        switch self {
        case .location, .relationship, .attribute:
            return true
        case .preference, .state, .goal, .temporal, .belief, .habit:
            return false
        }
    }
}

/// How a fact was detected
public enum FactDetectionMethod: String, Codable {
    case patternMatch       // Regex/rule-based extraction
    case entityOverlap      // Same entities mentioned
    case llmExtraction      // Future: LLM-based extraction
    case userConfirmed      // User explicitly confirmed
    case inferred           // Derived from other facts
}

// MARK: - Enhanced Entity Model

/// Represents an extracted entity with tracking
public struct TrackedEntity: Codable, Hashable, Identifiable {
    public let id: UUID

    /// Primary name of the entity
    public let name: String

    /// Normalized name for matching (lowercase, trimmed)
    public let normalizedName: String

    /// Type of entity
    public let type: TrackedEntityType

    /// Alternative names/aliases
    public var aliases: Set<String>

    /// When this entity was first mentioned
    public let firstMentioned: Date

    /// Number of times this entity has been mentioned
    public var mentionCount: Int

    /// Related facts about this entity
    public var relatedFactIds: [UUID]

    /// User ID this entity belongs to
    public let userId: String

    public init(
        id: UUID = UUID(),
        name: String,
        type: TrackedEntityType,
        aliases: Set<String> = [],
        firstMentioned: Date = Date(),
        mentionCount: Int = 1,
        relatedFactIds: [UUID] = [],
        userId: String
    ) {
        self.id = id
        self.name = name
        self.normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        self.aliases = aliases
        self.firstMentioned = firstMentioned
        self.mentionCount = mentionCount
        self.relatedFactIds = relatedFactIds
        self.userId = userId
    }

    /// Check if a string matches this entity
    public func matches(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedName == normalized || aliases.contains(normalized)
    }
}

/// Types of tracked entities
public enum TrackedEntityType: String, Codable, CaseIterable {
    case person
    case place
    case organization
    case date
    case duration
    case goal
    case emotion
    case activity
    case thing
    case event
    case topic
}

// MARK: - Temporal Model

/// Temporal information extracted from memory content
public struct TemporalInfo: Codable, Equatable {
    /// When the memory was stored in the system
    public let storageTime: Date

    /// When the event/fact actually happened (if extractable)
    public let eventTime: Date?

    /// Granularity of the event time
    public let eventTimeGranularity: TimeGranularity

    /// Whether this is an ongoing state vs. a point-in-time event
    public let isOngoing: Bool

    /// Raw temporal markers found in text
    public let temporalMarkers: [String]

    /// Temporal type (past, present, future)
    public let temporalType: TemporalType

    public init(
        storageTime: Date = Date(),
        eventTime: Date? = nil,
        eventTimeGranularity: TimeGranularity = .unknown,
        isOngoing: Bool = false,
        temporalMarkers: [String] = [],
        temporalType: TemporalType = .present
    ) {
        self.storageTime = storageTime
        self.eventTime = eventTime
        self.eventTimeGranularity = eventTimeGranularity
        self.isOngoing = isOngoing
        self.temporalMarkers = temporalMarkers
        self.temporalType = temporalType
    }

    /// The effective time to use for temporal queries
    public var effectiveTime: Date {
        eventTime ?? storageTime
    }
}

/// Granularity of extracted time
public enum TimeGranularity: String, Codable {
    case exact       // "June 15, 2025 at 3pm"
    case day         // "June 15"
    case week        // "last week"
    case month       // "in January"
    case year        // "in 2024"
    case approximate // "a few months ago"
    case unknown     // Could not determine
}

/// Temporal type for a memory
public enum TemporalType: String, Codable, Equatable {
    case past       // Already happened
    case present    // Current/ongoing state
    case future     // Planned/scheduled
    case habitual   // Recurring pattern
    case specific   // Specific date/time mentioned
}

/// Temporal context for a fact
public struct TemporalContext: Codable, Equatable {
    public let type: TemporalType
    public let date: Date?
    public let text: String
    
    public init(type: TemporalType, date: Date? = nil, text: String) {
        self.type = type
        self.date = date
        self.text = text
    }
}

// MARK: - Emotional Valence

/// Emotional information extracted from memory
public struct EmotionalValence: Codable, Equatable {
    /// Primary detected emotion
    public let primary: Emotion

    /// Intensity of the emotion (0-1)
    public let intensity: Float

    /// Secondary emotions detected
    public let secondaryEmotions: [Emotion]

    /// Sentiment polarity (-1 to 1, negative to positive)
    public let sentiment: Float

    public init(
        primary: Emotion = .neutral,
        intensity: Float = 0.5,
        secondaryEmotions: [Emotion] = [],
        sentiment: Float = 0.0
    ) {
        self.primary = primary
        self.intensity = min(max(intensity, 0.0), 1.0)
        self.secondaryEmotions = secondaryEmotions
        self.sentiment = min(max(sentiment, -1.0), 1.0)
    }

    /// Whether this has significant emotional content
    public var isEmotional: Bool {
        primary != .neutral && intensity > 0.3
    }
}

/// Emotion types for life coaching context
public enum Emotion: String, Codable, CaseIterable {
    // Positive emotions
    case joy
    case excitement
    case hope
    case pride
    case gratitude
    case love
    case calm
    case confident
    case motivated

    // Negative emotions
    case sadness
    case anger
    case fear
    case anxiety
    case frustration
    case overwhelmed
    case guilt
    case shame
    case disappointment

    // Neutral
    case neutral

    /// Whether this is a positive emotion
    public var isPositive: Bool {
        switch self {
        case .joy, .excitement, .hope, .pride, .gratitude, .love, .calm, .confident, .motivated:
            return true
        default:
            return false
        }
    }
}

// MARK: - Memory Layer

/// Memory layer for multi-tier storage architecture
public enum MemoryLayer: String, Codable, CaseIterable {
    /// Current session context - in-memory only, instant access
    case working

    /// Recent memories (last 7 days) - SQLite hot table, high priority
    case shortTerm

    /// Older memories - may be compressed, lower priority
    case longTerm

    /// Core facts about user - never decays, pinned
    case core

    /// Superseded memories kept for history
    case archived

    /// Default decay rate for this layer
    public var defaultDecayRate: Float {
        switch self {
        case .working: return 0.0      // No decay in session
        case .shortTerm: return 0.03   // Moderate decay
        case .longTerm: return 0.05    // Faster decay
        case .core: return 0.0         // No decay
        case .archived: return 0.0     // No decay (already superseded)
        }
    }

    /// Priority for retrieval (higher = more important)
    public var retrievalPriority: Int {
        switch self {
        case .core: return 100
        case .working: return 90
        case .shortTerm: return 70
        case .longTerm: return 50
        case .archived: return 10
        }
    }
}

// MARK: - Enhanced Memory Node

/// Enhanced memory node with SOTA architecture fields
public struct EnhancedMemoryNode: Identifiable, Codable, Equatable {
    public let id: UUID

    // Content
    public let content: String
    public let embedding: [Float]

    // Structured extraction
    public var facts: [Fact]
    public var entities: [TrackedEntity]
    public var temporalInfo: TemporalInfo
    public var emotionalValence: EmotionalValence

    // Classification
    public let memoryType: MemoryType
    public var layer: MemoryLayer
    public var importance: Float

    // Lifecycle tracking
    public let createdAt: Date
    public var lastAccessedAt: Date?
    public var accessCount: Int
    public var usefulRetrievals: Int
    public var totalRetrievals: Int

    // Relationships
    public var supersededBy: UUID?
    public var goalId: UUID?
    public var containerTags: [String]

    // User
    public let userId: String

    public init(
        id: UUID = UUID(),
        content: String,
        embedding: [Float],
        facts: [Fact] = [],
        entities: [TrackedEntity] = [],
        temporalInfo: TemporalInfo = TemporalInfo(),
        emotionalValence: EmotionalValence = EmotionalValence(),
        memoryType: MemoryType = .general,
        layer: MemoryLayer = .shortTerm,
        importance: Float = 0.5,
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil,
        accessCount: Int = 0,
        usefulRetrievals: Int = 0,
        totalRetrievals: Int = 0,
        supersededBy: UUID? = nil,
        goalId: UUID? = nil,
        containerTags: [String] = [],
        userId: String
    ) {
        self.id = id
        self.content = content
        self.embedding = embedding
        self.facts = facts
        self.entities = entities
        self.temporalInfo = temporalInfo
        self.emotionalValence = emotionalValence
        self.memoryType = memoryType
        self.layer = layer
        self.importance = min(max(importance, 0.0), 1.0)
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.accessCount = accessCount
        self.usefulRetrievals = usefulRetrievals
        self.totalRetrievals = totalRetrievals
        self.supersededBy = supersededBy
        self.goalId = goalId
        self.containerTags = containerTags
        self.userId = userId
    }

    /// Calculate utility score based on retrieval success
    public var utilityScore: Float {
        guard totalRetrievals > 0 else { return 0.5 }
        return Float(usefulRetrievals) / Float(totalRetrievals)
    }

    /// Whether this memory is superseded
    public var isSuperseded: Bool {
        supersededBy != nil
    }

    /// Record a retrieval
    public mutating func recordRetrieval(wasUseful: Bool) {
        lastAccessedAt = Date()
        accessCount += 1
        totalRetrievals += 1
        if wasUseful {
            usefulRetrievals += 1
        }
    }
}

// MARK: - Goal Cluster (Life Coaching)

/// A cluster of memories organized around a user goal
public struct GoalCluster: Identifiable, Codable {
    public let id: UUID

    /// The goal memory itself
    public let goalMemoryId: UUID

    /// Goal content (cached for quick access)
    public let goalContent: String

    /// When the goal was created
    public let createdAt: Date

    /// Progress memories (positive updates)
    public var progressMemoryIds: [UUID]

    /// Blocker memories (obstacles mentioned)
    public var blockerMemoryIds: [UUID]

    /// Motivation memories (why they want this)
    public var motivationMemoryIds: [UUID]

    /// Related insight memories from AI
    public var insightMemoryIds: [UUID]

    /// Emotional trajectory (date, valence pairs)
    public var emotionalTrajectory: [(Date, EmotionalValence)]

    /// User ID
    public let userId: String

    public init(
        id: UUID = UUID(),
        goalMemoryId: UUID,
        goalContent: String,
        createdAt: Date = Date(),
        progressMemoryIds: [UUID] = [],
        blockerMemoryIds: [UUID] = [],
        motivationMemoryIds: [UUID] = [],
        insightMemoryIds: [UUID] = [],
        emotionalTrajectory: [(Date, EmotionalValence)] = [],
        userId: String
    ) {
        self.id = id
        self.goalMemoryId = goalMemoryId
        self.goalContent = goalContent
        self.createdAt = createdAt
        self.progressMemoryIds = progressMemoryIds
        self.blockerMemoryIds = blockerMemoryIds
        self.motivationMemoryIds = motivationMemoryIds
        self.insightMemoryIds = insightMemoryIds
        self.emotionalTrajectory = emotionalTrajectory
        self.userId = userId
    }

    // Custom Codable for tuple array
    enum CodingKeys: String, CodingKey {
        case id, goalMemoryId, goalContent, createdAt
        case progressMemoryIds, blockerMemoryIds, motivationMemoryIds, insightMemoryIds
        case emotionalTrajectoryDates, emotionalTrajectoryValences
        case userId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        goalMemoryId = try container.decode(UUID.self, forKey: .goalMemoryId)
        goalContent = try container.decode(String.self, forKey: .goalContent)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        progressMemoryIds = try container.decode([UUID].self, forKey: .progressMemoryIds)
        blockerMemoryIds = try container.decode([UUID].self, forKey: .blockerMemoryIds)
        motivationMemoryIds = try container.decode([UUID].self, forKey: .motivationMemoryIds)
        insightMemoryIds = try container.decode([UUID].self, forKey: .insightMemoryIds)
        userId = try container.decode(String.self, forKey: .userId)

        let dates = try container.decode([Date].self, forKey: .emotionalTrajectoryDates)
        let valences = try container.decode([EmotionalValence].self, forKey: .emotionalTrajectoryValences)
        emotionalTrajectory = Array(zip(dates, valences))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(goalMemoryId, forKey: .goalMemoryId)
        try container.encode(goalContent, forKey: .goalContent)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(progressMemoryIds, forKey: .progressMemoryIds)
        try container.encode(blockerMemoryIds, forKey: .blockerMemoryIds)
        try container.encode(motivationMemoryIds, forKey: .motivationMemoryIds)
        try container.encode(insightMemoryIds, forKey: .insightMemoryIds)
        try container.encode(userId, forKey: .userId)

        try container.encode(emotionalTrajectory.map { $0.0 }, forKey: .emotionalTrajectoryDates)
        try container.encode(emotionalTrajectory.map { $0.1 }, forKey: .emotionalTrajectoryValences)
    }
}

// MARK: - Contradiction Result

/// Result of contradiction detection
public struct ContradictionResult: Equatable {
    public let type: ContradictionType
    public let existingFact: Fact?
    public let newFact: Fact?
    public let resolution: ContradictionResolution?
    public let confidence: Float

    public init(
        type: ContradictionType,
        existingFact: Fact? = nil,
        newFact: Fact? = nil,
        resolution: ContradictionResolution? = nil,
        confidence: Float = 0.0
    ) {
        self.type = type
        self.existingFact = existingFact
        self.newFact = newFact
        self.resolution = resolution
        self.confidence = confidence
    }

    public static let noContradiction = ContradictionResult(type: .noContradiction)
}

/// Types of contradictions
public enum ContradictionType: String, Codable {
    case noContradiction
    case directContradiction      // Same subject+predicate, different object
    case impliedContradiction     // Similar predicates suggest conflict
    case temporalContradiction    // Time-based conflict
}

/// How to resolve a contradiction
public enum ContradictionResolution: String, Codable {
    case newSupersedes    // New info replaces old
    case keepExisting     // Old info is more reliable
    case needsUserInput   // Ambiguous, ask user
    case coexist          // Both can be true (e.g., multiple homes)
}

// MARK: - Query Types

/// Types of queries for adaptive retrieval
public enum QueryType: String, Codable {
    case factual         // "What's my mom's birthday?" - keyword heavy
    case conceptual      // "How do I feel about work?" - vector heavy
    case temporal        // "What did I say last week?" - recency heavy
    case goalProgress    // "How am I doing on fitness?" - goal-centric
    case exploratory     // "Tell me about my patterns" - broad search
    case emotional       // "When was I happy?" - emotion-centric
}

/// Weights for hybrid search based on query type
public struct RetrievalWeights: Equatable {
    public let vector: Float
    public let keyword: Float
    public let recency: Float
    public let importance: Float
    public let utility: Float
    public let factMatch: Float

    public init(
        vector: Float = 0.35,
        keyword: Float = 0.15,
        recency: Float = 0.15,
        importance: Float = 0.15,
        utility: Float = 0.10,
        factMatch: Float = 0.10
    ) {
        self.vector = vector
        self.keyword = keyword
        self.recency = recency
        self.importance = importance
        self.utility = utility
        self.factMatch = factMatch
    }

    /// Get weights optimized for a query type
    public static func forQueryType(_ type: QueryType) -> RetrievalWeights {
        switch type {
        case .factual:
            return RetrievalWeights(vector: 0.20, keyword: 0.40, recency: 0.10, importance: 0.10, utility: 0.05, factMatch: 0.15)
        case .conceptual:
            return RetrievalWeights(vector: 0.50, keyword: 0.10, recency: 0.10, importance: 0.15, utility: 0.10, factMatch: 0.05)
        case .temporal:
            return RetrievalWeights(vector: 0.15, keyword: 0.15, recency: 0.45, importance: 0.10, utility: 0.05, factMatch: 0.10)
        case .goalProgress:
            return RetrievalWeights(vector: 0.25, keyword: 0.15, recency: 0.20, importance: 0.20, utility: 0.10, factMatch: 0.10)
        case .exploratory:
            return RetrievalWeights(vector: 0.35, keyword: 0.15, recency: 0.20, importance: 0.15, utility: 0.10, factMatch: 0.05)
        case .emotional:
            return RetrievalWeights(vector: 0.30, keyword: 0.20, recency: 0.15, importance: 0.15, utility: 0.10, factMatch: 0.10)
        }
    }
}

// MARK: - Relationship with Detection Method

/// Enhanced relationship type with goal-centric additions
public enum EnhancedRelationType: String, Codable, CaseIterable {
    // Knowledge updates
    case updates
    case supersedes
    case contradicts
    case extends

    // Temporal
    case precedes
    case followedBy
    case sameTimeframe

    // Semantic
    case relatedTo
    case similarTo
    case partOf
    case supports
    case causedBy

    // Goal-centric (life coaching)
    case progressToward    // Progress on a goal
    case blockerFor        // Obstacle to goal
    case motivationFor     // Why user wants goal
    case insightAbout      // AI insight about pattern
}

/// How a relationship was detected
public enum RelationshipDetectionMethod: String, Codable {
    case embeddingSimilarity
    case factContradiction
    case entityOverlap
    case temporalProximity
    case goalKeywordMatch
    case llmClassification    // Future
    case userSpecified
}

// MARK: - LLM Abstraction (Future-Proof)

/// Capabilities of an LLM service (for future local model improvements)
public struct LLMCapabilities {
    public let canReason: Bool
    public let canExtractJSON: Bool
    public let maxContextTokens: Int
    public let speedTier: LLMSpeedTier

    public init(
        canReason: Bool = false,
        canExtractJSON: Bool = false,
        maxContextTokens: Int = 8192,
        speedTier: LLMSpeedTier = .medium
    ) {
        self.canReason = canReason
        self.canExtractJSON = canExtractJSON
        self.maxContextTokens = maxContextTokens
        self.speedTier = speedTier
    }

    /// Current Qwen 2.5-3B capabilities
    public static let qwen3B = LLMCapabilities(
        canReason: false,
        canExtractJSON: false,
        maxContextTokens: 8192,
        speedTier: .medium
    )

    /// Future Qwen 7B capabilities (estimated)
    public static let qwen7B = LLMCapabilities(
        canReason: true,
        canExtractJSON: true,
        maxContextTokens: 32768,
        speedTier: .medium
    )
}

public enum LLMSpeedTier: String, Codable {
    case fast     // <500ms, use freely
    case medium   // 500ms-2s, use selectively
    case slow     // >2s, use sparingly
}
