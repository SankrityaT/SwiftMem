//
//  Config.swift
//  SwiftMem
//
//  Configuration system for SwiftMem
//

import Foundation

// MARK: - Main Configuration

/// Configuration for SwiftMem graph memory system
public struct SwiftMemConfig {
    
    // MARK: - Embedding Settings
    
    /// Which embedding model to use
    public var embeddingModel: EmbeddingModelType
    
    /// Dimensions of the embedding vectors
    public var embeddingDimensions: Int
    
    /// Maximum text length to embed (characters)
    public var maxEmbeddingLength: Int
    
    // MARK: - Vector Search Settings
    
    /// Minimum similarity score for vector search (0.0 to 1.0)
    public var similarityThreshold: Double
    
    /// Type of vector index to use
    public var vectorIndexType: VectorIndexType
    
    /// Number of results to return in vector search
    public var defaultTopK: Int
    
    // MARK: - Graph Settings
    
    /// Automatically create edges between similar nodes above this threshold
    public var autoLinkSimilarityThreshold: Double
    
    /// Maximum depth for graph traversal
    public var maxGraphDepth: Int
    
    /// Minimum edge weight to consider during traversal
    public var minEdgeWeight: Double
    
    /// Default relationship types
    public var defaultRelationshipTypes: [String]
    
    // MARK: - Retrieval Settings
    
    /// Default retrieval strategy
    public var defaultRetrievalStrategy: RetrievalStrategy
    
    /// Weight for recency in retrieval scoring (0.0 = ignore time, 1.0 = only recent)
    public var recencyWeight: Double
    
    /// Maximum number of results to return by default
    public var defaultMaxResults: Int
    
    /// Decay factor for recency (higher = faster decay)
    public var recencyDecayFactor: Double
    
    // MARK: - Performance Settings
    
    /// Maximum number of nodes to keep in memory cache
    public var maxCacheSize: Int
    
    /// Batch size for bulk operations
    public var batchSize: Int
    
    /// Maximum time to spend on a single query (seconds)
    public var maxQueryTime: TimeInterval
    
    /// Enable performance logging
    public var enablePerformanceLogging: Bool
    
    // MARK: - Storage Settings
    
    /// Location for database files
    public var storageLocation: StorageLocation
    
    /// Enable automatic backups
    public var enableAutoBackup: Bool
    
    /// Backup frequency (in seconds, nil = disabled)
    public var backupFrequency: TimeInterval?
    
    /// Maximum storage size in bytes (nil = unlimited)
    public var maxStorageSize: Int64?
    
    // MARK: - Privacy Settings
    
    /// Enable telemetry (always false for privacy)
    public var enableTelemetry: Bool
    
    /// Automatically delete memories older than this (nil = never)
    public var autoDeleteAfter: TimeInterval?
    
    // MARK: - Entity Extraction Settings
    
    /// Enable automatic entity extraction
    public var enableEntityExtraction: Bool
    
    /// Minimum confidence for entity extraction (0.0 to 1.0)
    public var entityExtractionConfidence: Double
    
    /// Entity types to extract
    public var entityTypesToExtract: Set<EntityType>
    
    // MARK: - Initialization
    
    public init(
        embeddingModel: EmbeddingModelType = .miniLM,
        embeddingDimensions: Int = 384,
        maxEmbeddingLength: Int = 512,
        similarityThreshold: Double = 0.7,
        vectorIndexType: VectorIndexType = .basic,
        defaultTopK: Int = 10,
        autoLinkSimilarityThreshold: Double = 0.8,
        maxGraphDepth: Int = 3,
        minEdgeWeight: Double = 0.3,
        defaultRelationshipTypes: [String] = ["related_to", "caused_by", "followed_by", "similar_to"],
        defaultRetrievalStrategy: RetrievalStrategy = .hybrid,
        recencyWeight: Double = 0.3,
        defaultMaxResults: Int = 5,
        recencyDecayFactor: Double = 0.1,
        maxCacheSize: Int = 1000,
        batchSize: Int = 10,
        maxQueryTime: TimeInterval = 5.0,
        enablePerformanceLogging: Bool = false,
        storageLocation: StorageLocation = .documents,
        enableAutoBackup: Bool = false,
        backupFrequency: TimeInterval? = nil,
        maxStorageSize: Int64? = nil,
        enableTelemetry: Bool = false,
        autoDeleteAfter: TimeInterval? = nil,
        enableEntityExtraction: Bool = true,
        entityExtractionConfidence: Double = 0.6,
        entityTypesToExtract: Set<EntityType> = Set(EntityType.allCases)
    ) {
        self.embeddingModel = embeddingModel
        self.embeddingDimensions = embeddingDimensions
        self.maxEmbeddingLength = maxEmbeddingLength
        self.similarityThreshold = similarityThreshold
        self.vectorIndexType = vectorIndexType
        self.defaultTopK = defaultTopK
        self.autoLinkSimilarityThreshold = autoLinkSimilarityThreshold
        self.maxGraphDepth = maxGraphDepth
        self.minEdgeWeight = minEdgeWeight
        self.defaultRelationshipTypes = defaultRelationshipTypes
        self.defaultRetrievalStrategy = defaultRetrievalStrategy
        self.recencyWeight = recencyWeight
        self.defaultMaxResults = defaultMaxResults
        self.recencyDecayFactor = recencyDecayFactor
        self.maxCacheSize = maxCacheSize
        self.batchSize = batchSize
        self.maxQueryTime = maxQueryTime
        self.enablePerformanceLogging = enablePerformanceLogging
        self.storageLocation = storageLocation
        self.enableAutoBackup = enableAutoBackup
        self.backupFrequency = backupFrequency
        self.maxStorageSize = maxStorageSize
        self.enableTelemetry = enableTelemetry
        self.autoDeleteAfter = autoDeleteAfter
        self.enableEntityExtraction = enableEntityExtraction
        self.entityExtractionConfidence = entityExtractionConfidence
        self.entityTypesToExtract = entityTypesToExtract
    }
    
    // MARK: - Validation
    
    /// Validates the configuration and throws errors if invalid
    public func validate() throws {
        // Embedding dimensions must be positive
        guard embeddingDimensions > 0 else {
            throw SwiftMemError.configurationError("Embedding dimensions must be positive")
        }
        
        // Similarity threshold must be between 0 and 1
        guard (0.0...1.0).contains(similarityThreshold) else {
            throw SwiftMemError.configurationError("Similarity threshold must be between 0.0 and 1.0")
        }
        
        // Auto-link threshold must be between 0 and 1
        guard (0.0...1.0).contains(autoLinkSimilarityThreshold) else {
            throw SwiftMemError.configurationError("Auto-link similarity threshold must be between 0.0 and 1.0")
        }
        
        // Graph depth must be positive
        guard maxGraphDepth > 0 else {
            throw SwiftMemError.configurationError("Max graph depth must be positive")
        }
        
        // Min edge weight must be between 0 and 1
        guard (0.0...1.0).contains(minEdgeWeight) else {
            throw SwiftMemError.configurationError("Min edge weight must be between 0.0 and 1.0")
        }
        
        // Recency weight must be between 0 and 1
        guard (0.0...1.0).contains(recencyWeight) else {
            throw SwiftMemError.configurationError("Recency weight must be between 0.0 and 1.0")
        }
        
        // Default max results must be positive
        guard defaultMaxResults > 0 else {
            throw SwiftMemError.configurationError("Default max results must be positive")
        }
        
        // Cache size must be positive
        guard maxCacheSize > 0 else {
            throw SwiftMemError.configurationError("Max cache size must be positive")
        }
        
        // Batch size must be positive
        guard batchSize > 0 else {
            throw SwiftMemError.configurationError("Batch size must be positive")
        }
        
        // Entity extraction confidence must be between 0 and 1
        guard (0.0...1.0).contains(entityExtractionConfidence) else {
            throw SwiftMemError.configurationError("Entity extraction confidence must be between 0.0 and 1.0")
        }
    }
}

// MARK: - Preset Configurations

extension SwiftMemConfig {
    
    /// Default configuration - balanced for most use cases
    public static let `default` = SwiftMemConfig()
    
    /// Optimized for mobile devices (lower memory, faster)
    public static let mobile = SwiftMemConfig(
        embeddingModel: .miniLM,
        embeddingDimensions: 384,
        maxEmbeddingLength: 256,
        similarityThreshold: 0.75,
        vectorIndexType: .basic,
        defaultTopK: 5,
        maxGraphDepth: 2,
        defaultMaxResults: 3,
        maxCacheSize: 500,
        batchSize: 5,
        enablePerformanceLogging: false
    )
    
    /// Optimized for high accuracy (slower, more memory)
    public static let highAccuracy = SwiftMemConfig(
        embeddingModel: .bgeBase,
        embeddingDimensions: 768,
        maxEmbeddingLength: 1024,
        similarityThreshold: 0.6,
        vectorIndexType: .hnsw,
        defaultTopK: 20,
        autoLinkSimilarityThreshold: 0.85,
        maxGraphDepth: 4,
        defaultMaxResults: 10,
        maxCacheSize: 2000,
        batchSize: 20,
        enablePerformanceLogging: true
    )
    
    /// Optimized for coaching/therapy apps (privacy-focused)
    public static let coaching = SwiftMemConfig(
        embeddingModel: .miniLM,
        embeddingDimensions: 384,
        similarityThreshold: 0.7,
        autoLinkSimilarityThreshold: 0.8,
        maxGraphDepth: 3,
        recencyWeight: 0.4, // Higher weight on recent conversations
        defaultMaxResults: 5,
        enableAutoBackup: true,
        backupFrequency: 3600, // Every hour
        enableTelemetry: false, // Never for privacy
        enableEntityExtraction: true
    )
    
    /// Optimized for chatbots (fast retrieval)
    public static let chatbot = SwiftMemConfig(
        embeddingModel: .miniLM,
        embeddingDimensions: 384,
        similarityThreshold: 0.75,
        defaultTopK: 5,
        maxGraphDepth: 2,
        recencyWeight: 0.5, // Strong recency bias
        defaultMaxResults: 3,
        maxCacheSize: 1000,
        batchSize: 10,
        maxQueryTime: 1.0, // Fast response needed
        enableEntityExtraction: false // Skip for speed
    )
    
    /// Optimized for note-taking apps
    public static let notes = SwiftMemConfig(
        embeddingModel: .bgeSmall,
        embeddingDimensions: 384,
        similarityThreshold: 0.65,
        defaultTopK: 10,
        autoLinkSimilarityThreshold: 0.75,
        maxGraphDepth: 3,
        recencyWeight: 0.2, // Less emphasis on recency
        defaultMaxResults: 8,
        enableEntityExtraction: true,
        entityTypesToExtract: [.person, .location, .organization, .date, .topic]
    )
}

// MARK: - Supporting Types

/// Type of embedding model to use
public struct EmbeddingModelType: Codable, Equatable {
    public let modelPath: String
    public let dimensions: Int
    
    public init(modelPath: String, dimensions: Int) {
        self.modelPath = modelPath
        self.dimensions = dimensions
    }
    
    // MARK: - Presets (commonly used models)
    
    /// Smallest, fastest model (~25MB, 384 dimensions)
    /// Best for: Mobile devices, fast inference
    public static let miniLM = EmbeddingModelType(
        modelPath: "sentence-transformers/all-MiniLM-L6-v2",
        dimensions: 384
    )
    
    /// Small model with good accuracy (~120MB, 384 dimensions)
    /// Best for: Balanced performance and accuracy
    public static let bgeSmall = EmbeddingModelType(
        modelPath: "BAAI/bge-small-en-v1.5",
        dimensions: 384
    )
    
    /// Base model with higher accuracy (~220MB, 768 dimensions)
    /// Best for: Desktop apps, maximum accuracy
    public static let bgeBase = EmbeddingModelType(
        modelPath: "BAAI/bge-base-en-v1.5",
        dimensions: 768
    )
    
    // MARK: - Custom Models
    
    /// Create a custom embedding model configuration
    /// - Parameters:
    ///   - modelPath: Path or identifier for the model (can be HuggingFace ID, local path, etc.)
    ///   - dimensions: Dimension of the embedding vectors
    /// - Returns: Custom embedding model configuration
    ///
    /// Example:
    /// ```swift
    /// let myModel = EmbeddingModelType.custom(
    ///     modelPath: "my-org/my-custom-model",
    ///     dimensions: 512
    /// )
    /// ```
    public static func custom(modelPath: String, dimensions: Int) -> EmbeddingModelType {
        return EmbeddingModelType(modelPath: modelPath, dimensions: dimensions)
    }
}

/// Type of vector index
public enum VectorIndexType: String, Codable {
    /// Basic linear search (slower but exact)
    case basic
    
    /// HNSW (Hierarchical Navigable Small World) - fast approximate search
    case hnsw
    
    public var description: String {
        switch self {
        case .basic:
            return "Basic linear search"
        case .hnsw:
            return "HNSW approximate nearest neighbor"
        }
    }
}

/// Storage location for database files
public enum StorageLocation: Equatable {
    /// Store in Documents directory (user-accessible)
    case documents
    
    /// Store in Application Support directory (app-only)
    case applicationSupport
    
    /// Store in Caches directory (can be purged by system)
    case caches
    
    /// Custom directory path
    case custom(URL)
    
    /// Get the actual file URL for storage
    public func url(filename: String) throws -> URL {
        let baseURL: URL
        
        switch self {
        case .documents:
            baseURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            
        case .applicationSupport:
            baseURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            
        case .caches:
            baseURL = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            
        case .custom(let url):
            baseURL = url
        }
        
        // Create SwiftMem subdirectory
        let swiftMemDir = baseURL.appendingPathComponent("SwiftMem", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: swiftMemDir.path) {
            try FileManager.default.createDirectory(
                at: swiftMemDir,
                withIntermediateDirectories: true
            )
        }
        
        return swiftMemDir.appendingPathComponent(filename)
    }
    
    public static func == (lhs: StorageLocation, rhs: StorageLocation) -> Bool {
        switch (lhs, rhs) {
        case (.documents, .documents),
             (.applicationSupport, .applicationSupport),
             (.caches, .caches):
            return true
        case (.custom(let lhsURL), .custom(let rhsURL)):
            return lhsURL == rhsURL
        default:
            return false
        }
    }
}

// MARK: - Configuration Builder

/// Builder pattern for creating configurations
public class SwiftMemConfigBuilder {
    private var config = SwiftMemConfig.default
    
    public init() {}
    
    public func embeddingModel(_ model: EmbeddingModelType) -> Self {
        config.embeddingModel = model
        return self
    }
    
    public func similarityThreshold(_ threshold: Double) -> Self {
        config.similarityThreshold = threshold
        return self
    }
    
    public func maxGraphDepth(_ depth: Int) -> Self {
        config.maxGraphDepth = depth
        return self
    }
    
    public func recencyWeight(_ weight: Double) -> Self {
        config.recencyWeight = weight
        return self
    }
    
    public func storageLocation(_ location: StorageLocation) -> Self {
        config.storageLocation = location
        return self
    }
    
    public func enableBackup(_ frequency: TimeInterval?) -> Self {
        config.enableAutoBackup = frequency != nil
        config.backupFrequency = frequency
        return self
    }
    
    public func maxResults(_ count: Int) -> Self {
        config.defaultMaxResults = count
        return self
    }
    
    public func build() throws -> SwiftMemConfig {
        try config.validate()
        return config
    }
}
