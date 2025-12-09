//
//  NLEmbedder.swift
//  SwiftMem
//
//  Created by Sankritya on 12/9/25.
//
//  Native Apple NLEmbedding-based embedder for 100% local operation.
//  Uses Apple's built-in sentence embeddings - no model download required.
//

import Foundation
import NaturalLanguage

/// Native Apple NLEmbedding-based embedder.
/// 100% local, no model download required, uses iOS built-in embeddings.
public struct NLEmbedder: Embedder, @unchecked Sendable {
    
    public let language: NLLanguage
    public let dimensions: Int
    public var modelIdentifier: String { "apple-nlembedding-\(language.rawValue)" }
    
    private let embedding: NLEmbedding?
    
    /// Initialize with a specific language. Defaults to English.
    /// - Parameter language: The language for embeddings. Must be one of the 7 supported languages.
    public init(language: NLLanguage = .english) {
        self.language = language
        self.embedding = NLEmbedding.sentenceEmbedding(for: language)
        
        // Get dimension from the embedding, or use default
        if let emb = self.embedding {
            self.dimensions = emb.dimension
            print("✅ [NLEmbedder] Initialized with \(emb.dimension) dimensions for \(language.rawValue)")
        } else {
            // Fallback - sentence embeddings might not be available
            // Try word embedding as fallback
            if let wordEmb = NLEmbedding.wordEmbedding(for: language) {
                self.dimensions = wordEmb.dimension
                print("⚠️ [NLEmbedder] Using word embedding fallback with \(wordEmb.dimension) dimensions")
            } else {
                self.dimensions = 512 // Safe default
                print("⚠️ [NLEmbedder] No embedding available for \(language.rawValue), using default dimensions")
            }
        }
    }
    
    public func embed(_ text: String) async throws -> [Float] {
        // Try sentence embedding first
        if let emb = embedding, let vector = emb.vector(for: text) {
            return vector.map { Float($0) }
        }
        
        // Fallback: Use word embedding and average
        if let wordEmb = NLEmbedding.wordEmbedding(for: language) {
            return averageWordEmbedding(text: text, embedding: wordEmb)
        }
        
        // Last resort: return zero vector
        print("⚠️ [NLEmbedder] Could not embed text, returning zero vector")
        return [Float](repeating: 0.0, count: dimensions)
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            let emb = try await embed(text)
            results.append(emb)
        }
        return results
    }
    
    // MARK: - Private
    
    /// Average word embeddings for a sentence (fallback when sentence embedding unavailable)
    private func averageWordEmbedding(text: String, embedding: NLEmbedding) -> [Float] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        var vectors: [[Double]] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            if let vector = embedding.vector(for: word) {
                vectors.append(vector)
            }
            return true
        }
        
        guard !vectors.isEmpty else {
            return [Float](repeating: 0.0, count: dimensions)
        }
        
        // Average all word vectors
        var avgVector = [Double](repeating: 0.0, count: dimensions)
        for vector in vectors {
            for (i, val) in vector.enumerated() where i < dimensions {
                avgVector[i] += val
            }
        }
        
        let count = Double(vectors.count)
        return avgVector.map { Float($0 / count) }
    }
}

// MARK: - Convenience

extension NLEmbedder {
    /// Check if sentence embedding is available for a language
    public static func isSentenceEmbeddingAvailable(for language: NLLanguage) -> Bool {
        return NLEmbedding.sentenceEmbedding(for: language) != nil
    }
    
    /// Check if word embedding is available for a language
    public static func isWordEmbeddingAvailable(for language: NLLanguage) -> Bool {
        return NLEmbedding.wordEmbedding(for: language) != nil
    }
    
    /// Supported languages for embeddings
    public static var supportedLanguages: [NLLanguage] {
        [.english, .spanish, .french, .italian, .german, .portuguese, .simplifiedChinese]
    }
}
