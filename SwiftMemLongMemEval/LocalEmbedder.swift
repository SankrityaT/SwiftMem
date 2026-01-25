//
//  LocalEmbedder.swift
//  SwiftMemLongMemEval
//
//  Created by Sankritya on 2026-01-23.
//  Local embedder using Apple's NLEmbedding
//

import Foundation
import NaturalLanguage

/// Local embedder using Apple's NLEmbedding - 100% on-device, no API calls
public struct LocalEmbedder: Embedder {
    public let dimensions: Int
    public let modelIdentifier: String = "apple-nlembedding"
    
    private let embedding: NLEmbedding?
    
    public init() {
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
        self.dimensions = embedding?.dimension ?? 512
        print("✅ LocalEmbedder initialized with \(dimensions) dimensions (100% local)")
    }
    
    public func embed(_ text: String) async throws -> [Float] {
        guard let embedding = embedding else {
            throw EmbedderError.notAvailable
        }
        
        guard let vector = embedding.vector(for: text) else {
            throw EmbedderError.failed
        }
        
        return vector.map { Float($0) }
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        for text in texts {
            results.append(try await embed(text))
        }
        return results
    }
}

enum EmbedderError: Error {
    case notAvailable
    case failed
}
