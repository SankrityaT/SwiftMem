//
//  EmbedderFactory.swift
//  SwiftMem
//
//  Created by Sankritya on 1/22/26.
//

import Foundation

#if canImport(OnDeviceCatalyst)
import OnDeviceCatalyst
#endif

/// Factory for creating embedders with automatic fallback chain
public enum EmbedderFactory {
    
    // MARK: - Embedder Options
    
    /// Configuration for embedder selection
    public struct EmbedderConfig {
        /// Preferred embedding strategy
        public var preferredStrategy: EmbeddingStrategy
        
        /// Fallback to next available option if preferred fails
        public var enableFallback: Bool
        
        /// API keys for cloud providers
        public var apiKeys: [String: String]
        
        /// Path to local GGUF embedding model (e.g., bge-small)
        public var localEmbeddingModelPath: String?
        
        /// Existing chat model instance (can be used for embeddings as fallback)
        public var chatModelInstance: Any?
        
        public init(
            preferredStrategy: EmbeddingStrategy = .auto,
            enableFallback: Bool = true,
            apiKeys: [String: String] = [:],
            localEmbeddingModelPath: String? = nil,
            chatModelInstance: Any? = nil
        ) {
            self.preferredStrategy = preferredStrategy
            self.enableFallback = enableFallback
            self.apiKeys = apiKeys
            self.localEmbeddingModelPath = localEmbeddingModelPath
            self.chatModelInstance = chatModelInstance
        }
    }
    
    /// Embedding strategy options
    public enum EmbeddingStrategy: Equatable {
        /// Automatically select best available option
        case auto
        
        /// Use dedicated local GGUF embedding model (bge-small, etc.)
        case dedicatedLocal
        
        /// Use existing chat model for embeddings (Qwen, Llama, etc.)
        case chatModelEmbeddings
        
        /// Use cloud API (OpenAI, Cohere, Voyage)
        case cloudAPI(provider: CloudProvider)
        
        /// Use Apple's built-in NLEmbedding
        case appleNL
        
        public enum CloudProvider: Equatable {
            case openAI
            case cohere
            case voyage
            case groq
        }
    }
    
    // MARK: - Factory Method
    
    /// Create the best available embedder based on configuration
    public static func createEmbedder(config: EmbedderConfig) async throws -> (embedder: any Embedder, dimensions: Int) {
        
        // Try preferred strategy first
        if let result = try await attemptStrategy(config.preferredStrategy, config: config) {
            print("✅ [EmbedderFactory] Using \(config.preferredStrategy)")
            return result
        }
        
        // Fallback chain if enabled
        guard config.enableFallback else {
            throw SwiftMemError.configurationError("Preferred embedder strategy failed and fallback is disabled")
        }
        
        print("⚠️ [EmbedderFactory] Preferred strategy failed, trying fallbacks...")
        
        // Fallback order: Apple NL (reliable) → dedicated local → chat model → cloud API
        let fallbackStrategies: [EmbeddingStrategy] = [
            .appleNL,
            .dedicatedLocal,
            .chatModelEmbeddings,
            .cloudAPI(provider: .openAI)
        ]
        
        for strategy in fallbackStrategies {
            if strategy == config.preferredStrategy { continue } // Skip already tried
            
            if let result = try await attemptStrategy(strategy, config: config) {
                print("✅ [EmbedderFactory] Fallback successful: \(strategy)")
                return result
            }
        }
        
        throw SwiftMemError.configurationError("No embedder available. Install a local model or provide API keys.")
    }
    
    // MARK: - Strategy Implementations
    
    private static func attemptStrategy(
        _ strategy: EmbeddingStrategy,
        config: EmbedderConfig
    ) async throws -> (embedder: any Embedder, dimensions: Int)? {
        
        switch strategy {
        case .auto:
            // Auto mode tries strategies in order of preference
            // Prefer NLEmbedding since it's reliable and always available
            return try await createEmbedder(config: EmbedderConfig(
                preferredStrategy: .appleNL,
                enableFallback: true,
                apiKeys: config.apiKeys,
                localEmbeddingModelPath: config.localEmbeddingModelPath,
                chatModelInstance: config.chatModelInstance
            ))
            
        case .dedicatedLocal:
            return try await createDedicatedLocalEmbedder(config: config)
            
        case .chatModelEmbeddings:
            return try await createChatModelEmbedder(config: config)
            
        case .cloudAPI(let provider):
            return try await createCloudEmbedder(provider: provider, config: config)
            
        case .appleNL:
            return try await createAppleNLEmbedder()
        }
    }
    
    // MARK: - Dedicated Local Embedder (Best Option)
    
    private static func createDedicatedLocalEmbedder(
        config: EmbedderConfig
    ) async throws -> (embedder: any Embedder, dimensions: Int)? {
        
        #if canImport(OnDeviceCatalyst)
        guard let modelPath = config.localEmbeddingModelPath else {
            print("⚠️ [EmbedderFactory] No local embedding model path provided")
            return nil
        }
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            print("⚠️ [EmbedderFactory] Embedding model not found at: \(modelPath)")
            return nil
        }
        
        print("🔄 [EmbedderFactory] Loading dedicated embedding model: \(modelPath)")
        
        // Load the embedding model
        let profile = try ModelProfile(filePath: modelPath)
        let settings = InstanceSettings(
            contextLength: 512,  // Embeddings don't need large context
            batchSize: 512,
            gpuLayers: 99,  // Use GPU for speed
            cpuThreads: 4,
            enableMemoryMapping: true,
            enableMemoryLocking: false,
            useFlashAttention: false
        )
        let predictionConfig = PredictionConfig.balanced
        
        let llamaInstance = LlamaInstance(
            profile: profile,
            settings: settings,
            predictionConfig: predictionConfig
        )
        
        // Initialize
        for await progress in llamaInstance.initialize() {
            print("  \(progress.message)")
            if case .failed(let error) = progress {
                print("❌ [EmbedderFactory] Failed to load embedding model: \(error)")
                return nil
            }
        }
        
        // Get dimensions - use a default for embedding models or try to infer
        // Most embedding models are 384 or 768 dimensions
        let dimensions: Int
        if modelPath.contains("nomic") {
            dimensions = 768
        } else if modelPath.contains("bge-base") {
            dimensions = 768
        } else if modelPath.contains("mxbai") {
            dimensions = 1024
        } else {
            dimensions = 384  // Default for bge-small and most small models
        }
        
        let embedder = OnDeviceCatalystEmbedder(
            llama: llamaInstance,
            dimensions: dimensions,
            modelIdentifier: profile.name
        )
        
        print("✅ [EmbedderFactory] Loaded dedicated embedding model (\(dimensions) dims)")
        return (embedder, dimensions)
        
        #else
        print("⚠️ [EmbedderFactory] OnDeviceCatalyst not available")
        return nil
        #endif
    }
    
    // MARK: - Chat Model Embedder (Fallback)
    
    private static func createChatModelEmbedder(
        config: EmbedderConfig
    ) async throws -> (embedder: any Embedder, dimensions: Int)? {
        
        #if canImport(OnDeviceCatalyst)
        guard let chatInstance = config.chatModelInstance as? LlamaInstance else {
            print("⚠️ [EmbedderFactory] No chat model instance provided")
            return nil
        }
        
        guard chatInstance.isReady else {
            print("⚠️ [EmbedderFactory] Chat model not ready")
            return nil
        }
        
        print("🔄 [EmbedderFactory] Using chat model for embeddings (not optimal)")
        
        // Get dimensions from chat model
        // Note: This requires access to the model pointer, which we'll need to expose
        let dimensions = 384 // Default fallback, should query from model
        
        let embedder = OnDeviceCatalystEmbedder(
            llama: chatInstance,
            dimensions: dimensions,
            modelIdentifier: chatInstance.profile.name
        )
        
        print("⚠️ [EmbedderFactory] Using chat model for embeddings (slower, not ideal)")
        return (embedder, dimensions)
        
        #else
        print("⚠️ [EmbedderFactory] OnDeviceCatalyst not available")
        return nil
        #endif
    }
    
    // MARK: - Cloud API Embedders
    
    private static func createCloudEmbedder(
        provider: EmbeddingStrategy.CloudProvider,
        config: EmbedderConfig
    ) async throws -> (embedder: any Embedder, dimensions: Int)? {
        
        switch provider {
        case .openAI:
            guard let apiKey = config.apiKeys["openai"] else {
                print("⚠️ [EmbedderFactory] OpenAI API key not provided")
                return nil
            }
            let embedder = OpenAIEmbedder(
                apiKey: apiKey,
                model: "text-embedding-3-small",
                dimensions: 1536
            )
            print("✅ [EmbedderFactory] Using OpenAI embeddings (cloud)")
            return (embedder, 1536)
            
        case .cohere:
            guard let apiKey = config.apiKeys["cohere"] else {
                print("⚠️ [EmbedderFactory] Cohere API key not provided")
                return nil
            }
            let embedder = CohereEmbedder(
                apiKey: apiKey,
                model: "embed-english-v3.0",
                dimensions: 1024
            )
            print("✅ [EmbedderFactory] Using Cohere embeddings (cloud)")
            return (embedder, 1024)
            
        case .voyage:
            guard let apiKey = config.apiKeys["voyage"] else {
                print("⚠️ [EmbedderFactory] Voyage API key not provided")
                return nil
            }
            let embedder = VoyageEmbedder(
                apiKey: apiKey,
                model: "voyage-2",
                dimensions: 1024
            )
            print("✅ [EmbedderFactory] Using Voyage embeddings (cloud)")
            return (embedder, 1024)
            
        case .groq:
            print("⚠️ [EmbedderFactory] Groq doesn't have real embeddings API")
            return nil
        }
    }
    
    // MARK: - Apple NLEmbedding (Last Resort)
    
    private static func createAppleNLEmbedder() async throws -> (embedder: any Embedder, dimensions: Int)? {
        let embedder = NLEmbedder()
        
        if embedder.dimensions > 0 {
            print("✅ [EmbedderFactory] Using Apple NLEmbedding (built-in)")
            return (embedder, embedder.dimensions)
        } else {
            print("⚠️ [EmbedderFactory] Apple NLEmbedding not available")
            return nil
        }
    }
}

// MARK: - Convenience Extensions

extension EmbedderFactory.EmbedderConfig {
    /// Fully local configuration (no cloud APIs)
    public static func fullyLocal(
        embeddingModelPath: String? = nil,
        chatModel: Any? = nil
    ) -> Self {
        return EmbedderFactory.EmbedderConfig(
            preferredStrategy: .auto,
            enableFallback: true,
            apiKeys: [:],
            localEmbeddingModelPath: embeddingModelPath,
            chatModelInstance: chatModel
        )
    }
    
    /// Cloud-first configuration
    public static func cloudFirst(apiKeys: [String: String]) -> Self {
        return EmbedderFactory.EmbedderConfig(
            preferredStrategy: .cloudAPI(provider: .openAI),
            enableFallback: true,
            apiKeys: apiKeys
        )
    }
    
    /// Hybrid configuration (local preferred, cloud fallback)
    public static func hybrid(
        embeddingModelPath: String?,
        apiKeys: [String: String]
    ) -> Self {
        return EmbedderFactory.EmbedderConfig(
            preferredStrategy: .auto,
            enableFallback: true,
            apiKeys: apiKeys,
            localEmbeddingModelPath: embeddingModelPath
        )
    }
}
