//
//  EmbeddingEngine.swift
//  SwiftMem
//
//  Created on 12/7/24.
//  Universal embedding engine supporting multiple backends
//

import Foundation

// MARK: - Embedder Protocol

/// Protocol for any embedding provider (local or API-based)
public protocol Embedder: Sendable {
    /// Generate embedding for a single text
    func embed(_ text: String) async throws -> [Float]
    
    /// Generate embeddings for multiple texts (batch operation)
    func embedBatch(_ texts: [String]) async throws -> [[Float]]
    
    /// Embedding dimensions
    var dimensions: Int { get }
    
    /// Model identifier
    var modelIdentifier: String { get }
}

// MARK: - Embedding Engine

/// Manages embedding generation with caching and batch processing
public actor EmbeddingEngine {
    
    // MARK: - Properties
    
    private let embedder: Embedder
    private let config: SwiftMemConfig
    
    // MARK: - Public Access
    
    /// Get the underlying embedder (for advanced use cases like calling AI)
    public var underlyingEmbedder: Embedder {
        embedder
    }
    
    // Cache for embeddings (text hash -> embedding)
    private var cache: [String: [Float]] = [:]
    private let maxCacheSize = 1000
    
    // Statistics
    private var embeddingCount: Int = 0
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    
    // MARK: - Initialization
    
    /// Initialize with a specific embedder
    public init(embedder: Embedder, config: SwiftMemConfig) {
        self.embedder = embedder
        self.config = config
    }
    
    /// Convenience initializer that creates embedder from config
    public init(config: SwiftMemConfig) async throws {
        self.config = config
        
        // Create embedder based on model type
        switch config.embeddingModel.modelPath {
        case let path where path.starts(with: "text-embedding-"):
            // OpenAI models
            guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
                throw SwiftMemError.configurationError("OPENAI_API_KEY not found in environment")
            }
            self.embedder = OpenAIEmbedder(
                apiKey: apiKey,
                model: config.embeddingModel.modelPath,
                dimensions: config.embeddingModel.dimensions
            )
            
        case let path where path.starts(with: "voyage-"):
            // Voyage AI models
            guard let apiKey = ProcessInfo.processInfo.environment["VOYAGE_API_KEY"] else {
                throw SwiftMemError.configurationError("VOYAGE_API_KEY not found in environment")
            }
            self.embedder = VoyageEmbedder(
                apiKey: apiKey,
                model: config.embeddingModel.modelPath,
                dimensions: config.embeddingModel.dimensions
            )
            
        case let path where path.starts(with: "embed-"):
            // Cohere models
            guard let apiKey = ProcessInfo.processInfo.environment["COHERE_API_KEY"] else {
                throw SwiftMemError.configurationError("COHERE_API_KEY not found in environment")
            }
            self.embedder = CohereEmbedder(
                apiKey: apiKey,
                model: config.embeddingModel.modelPath,
                dimensions: config.embeddingModel.dimensions
            )
            
        case let path where path.hasSuffix(".mlmodelc") || path.hasSuffix(".mlpackage"):
            // CoreML models
            self.embedder = try CoreMLEmbedder(
                modelPath: config.embeddingModel.modelPath,
                dimensions: config.embeddingModel.dimensions
            )
            
        case let path where path.hasSuffix(".gguf"):
            // GGUF/llama.cpp models
            self.embedder = try GGUFEmbedder(
                modelPath: config.embeddingModel.modelPath,
                dimensions: config.embeddingModel.dimensions
            )
            
        default:
            // Default to MLX for HuggingFace models
            self.embedder = try await MLXEmbedder(
                modelPath: config.embeddingModel.modelPath,
                dimensions: config.embeddingModel.dimensions
            )
        }
    }
    
    // MARK: - Embedding Operations
    
    /// Generate embedding for text with caching
    public func embed(_ text: String) async throws -> [Float] {
        // Truncate if needed
        let processedText = truncateText(text, maxLength: config.maxEmbeddingLength)
        
        // Check cache
        let cacheKey = cacheKeyFor(processedText)
        if let cached = cache[cacheKey] {
            cacheHits += 1
            return cached
        }
        
        // Generate embedding
        cacheMisses += 1
        let embedding = try await embedder.embed(processedText)
        
        // Validate dimensions
        guard embedding.count == config.embeddingDimensions else {
            throw SwiftMemError.embeddingError("Dimension mismatch: expected \(config.embeddingDimensions), got \(embedding.count)")
        }
        
        // Cache result
        addToCache(cacheKey, embedding: embedding)
        embeddingCount += 1
        
        return embedding
    }
    
    /// Generate embeddings for multiple texts (optimized batch processing)
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        
        // Process texts
        let processedTexts = texts.map { truncateText($0, maxLength: config.maxEmbeddingLength) }
        
        // Check cache for all texts
        var results: [[Float]?] = Array(repeating: nil, count: texts.count)
        var uncachedIndices: [Int] = []
        var uncachedTexts: [String] = []
        
        for (index, text) in processedTexts.enumerated() {
            let cacheKey = cacheKeyFor(text)
            if let cached = cache[cacheKey] {
                results[index] = cached
                cacheHits += 1
            } else {
                uncachedIndices.append(index)
                uncachedTexts.append(text)
            }
        }
        
        // Generate embeddings for uncached texts
        if !uncachedTexts.isEmpty {
            cacheMisses += uncachedTexts.count
            
            // Process in batches if needed
            let batchSize = config.batchSize
            var allEmbeddings: [[Float]] = []
            
            for batchStart in stride(from: 0, to: uncachedTexts.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, uncachedTexts.count)
                let batch = Array(uncachedTexts[batchStart..<batchEnd])
                
                let batchEmbeddings = try await embedder.embedBatch(batch)
                allEmbeddings.append(contentsOf: batchEmbeddings)
            }
            
            // Validate and cache
            for (i, embedding) in allEmbeddings.enumerated() {
                guard embedding.count == config.embeddingDimensions else {
                    throw SwiftMemError.embeddingError("Dimension mismatch in batch")
                }
                
                let originalIndex = uncachedIndices[i]
                let text = processedTexts[originalIndex]
                results[originalIndex] = embedding
                
                addToCache(cacheKeyFor(text), embedding: embedding)
                embeddingCount += 1
            }
        }
        
        // All results should be filled now
        return results.compactMap { $0 }
    }
    
    // MARK: - Cache Management
    
    private func cacheKeyFor(_ text: String) -> String {
        // Use hash for cache key (memory efficient)
        return String(text.hashValue)
    }
    
    private func addToCache(_ key: String, embedding: [Float]) {
        // LRU eviction if cache is full
        if cache.count >= maxCacheSize {
            // Remove random key (simple approximation of LRU)
            if let firstKey = cache.keys.first {
                cache.removeValue(forKey: firstKey)
            }
        }
        
        cache[key] = embedding
    }
    
    /// Clear embedding cache
    public func clearCache() {
        cache.removeAll()
        cacheHits = 0
        cacheMisses = 0
    }
    
    /// Get cache statistics
    public func getCacheStats() -> (size: Int, hits: Int, misses: Int, hitRate: Double) {
        let total = cacheHits + cacheMisses
        let hitRate = total > 0 ? Double(cacheHits) / Double(total) : 0
        return (cache.count, cacheHits, cacheMisses, hitRate)
    }
    
    /// Get embedding statistics
    public func getStats() -> (totalEmbeddings: Int, cacheSize: Int, cacheHitRate: Double) {
        let stats = getCacheStats()
        return (embeddingCount, stats.size, stats.hitRate)
    }
    
    // MARK: - Text Processing
    
    private func truncateText(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength {
            return text
        }
        
        let endIndex = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<endIndex])
    }
}

// MARK: - MLX Embedder

/// MLX-based local embedder (on-device, GPU accelerated)
public struct MLXEmbedder: Embedder {
    public let dimensions: Int
    public let modelIdentifier: String
    
    // TODO: Integrate with MLXEmbedders package when added
    // For now, this is a placeholder that will be implemented
    
    public init(modelPath: String, dimensions: Int) async throws {
        self.modelIdentifier = modelPath
        self.dimensions = dimensions
        
        // Will load MLX model here
        throw SwiftMemError.configurationError("MLX embedder not yet implemented - add MLXEmbedders package")
    }
    
    public func embed(_ text: String) async throws -> [Float] {
        // Will use MLX model for inference
        throw SwiftMemError.configurationError("MLX embedder not yet implemented")
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        // Batch inference with MLX
        throw SwiftMemError.configurationError("MLX embedder not yet implemented")
    }
}

// MARK: - CoreML Embedder

/// CoreML-based local embedder (on-device, Neural Engine accelerated)
public struct CoreMLEmbedder: Embedder {
    public let dimensions: Int
    public let modelIdentifier: String
    
    // TODO: Load CoreML model
    
    public init(modelPath: String, dimensions: Int) throws {
        self.modelIdentifier = modelPath
        self.dimensions = dimensions
        
        // Will load CoreML model here
        throw SwiftMemError.configurationError("CoreML embedder not yet implemented - convert model to CoreML")
    }
    
    public func embed(_ text: String) async throws -> [Float] {
        // Will use CoreML model for inference
        throw SwiftMemError.configurationError("CoreML embedder not yet implemented")
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        // CoreML batch prediction
        throw SwiftMemError.configurationError("CoreML embedder not yet implemented")
    }
}

// MARK: - GGUF Embedder

/// GGUF/llama.cpp-based local embedder
public struct GGUFEmbedder: Embedder {
    public let dimensions: Int
    public let modelIdentifier: String
    
    // TODO: Integrate with llama.cpp
    
    public init(modelPath: String, dimensions: Int) throws {
        self.modelIdentifier = modelPath
        self.dimensions = dimensions
        
        // Will load GGUF model here
        throw SwiftMemError.configurationError("GGUF embedder not yet implemented - integrate llama.cpp")
    }
    
    public func embed(_ text: String) async throws -> [Float] {
        // Will use llama.cpp for inference
        throw SwiftMemError.configurationError("GGUF embedder not yet implemented")
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        // Batch with llama.cpp
        throw SwiftMemError.configurationError("GGUF embedder not yet implemented")
    }
}

// MARK: - OpenAI Embedder

/// OpenAI API-based embedder
public struct OpenAIEmbedder: Embedder {
    public let dimensions: Int
    public let modelIdentifier: String
    
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/embeddings"
    
    public init(apiKey: String, model: String, dimensions: Int) {
        self.apiKey = apiKey
        self.modelIdentifier = model
        self.dimensions = dimensions
    }
    
    public func embed(_ text: String) async throws -> [Float] {
        let embeddings = try await embedBatch([text])
        guard let first = embeddings.first else {
            throw SwiftMemError.embeddingError("No embedding returned from OpenAI")
        }
        return first
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard let url = URL(string: baseURL) else {
            throw SwiftMemError.embeddingError("Invalid OpenAI URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "input": texts,
            "model": modelIdentifier,
            "dimensions": dimensions
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SwiftMemError.embeddingError("Invalid response from OpenAI")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SwiftMemError.embeddingError("OpenAI API error (\(httpResponse.statusCode)): \(errorMessage)")
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw SwiftMemError.embeddingError("Failed to parse OpenAI response")
        }
        
        var embeddings: [[Float]] = []
        for item in dataArray {
            guard let embedding = item["embedding"] as? [Double] else {
                throw SwiftMemError.embeddingError("Invalid embedding format")
            }
            embeddings.append(embedding.map { Float($0) })
        }
        
        return embeddings
    }
}

// MARK: - Voyage AI Embedder

/// Voyage AI API-based embedder
public struct VoyageEmbedder: Embedder {
    public let dimensions: Int
    public let modelIdentifier: String
    
    private let apiKey: String
    private let baseURL = "https://api.voyageai.com/v1/embeddings"
    
    public init(apiKey: String, model: String, dimensions: Int) {
        self.apiKey = apiKey
        self.modelIdentifier = model
        self.dimensions = dimensions
    }
    
    public func embed(_ text: String) async throws -> [Float] {
        let embeddings = try await embedBatch([text])
        guard let first = embeddings.first else {
            throw SwiftMemError.embeddingError("No embedding returned from Voyage AI")
        }
        return first
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard let url = URL(string: baseURL) else {
            throw SwiftMemError.embeddingError("Invalid Voyage AI URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "input": texts,
            "model": modelIdentifier
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SwiftMemError.embeddingError("Invalid response from Voyage AI")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SwiftMemError.embeddingError("Voyage AI error (\(httpResponse.statusCode)): \(errorMessage)")
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw SwiftMemError.embeddingError("Failed to parse Voyage AI response")
        }
        
        var embeddings: [[Float]] = []
        for item in dataArray {
            guard let embedding = item["embedding"] as? [Double] else {
                throw SwiftMemError.embeddingError("Invalid embedding format")
            }
            embeddings.append(embedding.map { Float($0) })
        }
        
        return embeddings
    }
}

// MARK: - Cohere Embedder

/// Cohere API-based embedder
public struct CohereEmbedder: Embedder {
    public let dimensions: Int
    public let modelIdentifier: String
    
    private let apiKey: String
    private let baseURL = "https://api.cohere.ai/v1/embed"
    
    public init(apiKey: String, model: String, dimensions: Int) {
        self.apiKey = apiKey
        self.modelIdentifier = model
        self.dimensions = dimensions
    }
    
    public func embed(_ text: String) async throws -> [Float] {
        let embeddings = try await embedBatch([text])
        guard let first = embeddings.first else {
            throw SwiftMemError.embeddingError("No embedding returned from Cohere")
        }
        return first
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard let url = URL(string: baseURL) else {
            throw SwiftMemError.embeddingError("Invalid Cohere URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "texts": texts,
            "model": modelIdentifier,
            "input_type": "search_document"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SwiftMemError.embeddingError("Invalid response from Cohere")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SwiftMemError.embeddingError("Cohere API error (\(httpResponse.statusCode)): \(errorMessage)")
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddingsArray = json["embeddings"] as? [[Double]] else {
            throw SwiftMemError.embeddingError("Failed to parse Cohere response")
        }
        
        return embeddingsArray.map { $0.map { Float($0) } }
    }
}

// MARK: - Mock Embedder (for testing)

/// Mock embedder for testing (generates random vectors)
public struct MockEmbedder: Embedder {
    public let dimensions: Int
    public let modelIdentifier: String
    
    public init(dimensions: Int) {
        self.dimensions = dimensions
        self.modelIdentifier = "mock-embedder"
    }
    
    public func embed(_ text: String) async throws -> [Float] {
        // Generate deterministic random vector based on text hash
        var generator = SeededRandomGenerator(seed: UInt64(abs(text.hashValue)))
        return (0..<dimensions).map { _ in Float.random(in: -1...1, using: &generator) }
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        for text in texts {
            results.append(try await embed(text))
        }
        return results
    }
}

// MARK: - Utilities

/// Seeded random number generator for deterministic testing
private struct SeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
