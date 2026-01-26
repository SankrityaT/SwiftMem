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
    
    /// Convenience initializer that creates NLEmbedder by default
    public init(config: SwiftMemConfig) async throws {
        self.config = config
        self.embedder = NLEmbedder()
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
