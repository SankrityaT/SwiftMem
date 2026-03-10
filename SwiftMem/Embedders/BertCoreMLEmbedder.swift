//
//  BertCoreMLEmbedder.swift
//  SwiftMem
//
//  CoreML-based sentence embedder using swift-embeddings.
//  Runs on ANE/CPU (not Metal GPU), safe to use alongside MLX models.
//

import Foundation
import Embeddings

/// Embedding model presets for CoreML inference via swift-embeddings.
/// These run on Apple Neural Engine / CPU — zero GPU memory.
public enum CoreMLEmbeddingModel: String, Sendable {
    case bgeSmallEN = "BAAI/bge-small-en-v1.5"
    case miniLM = "sentence-transformers/all-MiniLM-L6-v2"

    public var dimensions: Int {
        switch self {
        case .bgeSmallEN: return 384
        case .miniLM: return 384
        }
    }

    public var displayName: String {
        switch self {
        case .bgeSmallEN: return "bge-small-en-v1.5"
        case .miniLM: return "all-MiniLM-L6-v2"
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
public actor BertCoreMLEmbedder: Embedder {
    public let dimensions: Int
    public let modelIdentifier: String

    private let modelBundle: Bert.ModelBundle

    public init(modelBundle: Bert.ModelBundle, model: CoreMLEmbeddingModel) {
        self.modelBundle = modelBundle
        self.dimensions = model.dimensions
        self.modelIdentifier = "coreml-\(model.rawValue)"
    }

    /// Load a pre-trained BERT model from HuggingFace Hub.
    /// Downloads on first use (~25-120 MB), cached permanently.
    public static func load(model: CoreMLEmbeddingModel) async throws -> BertCoreMLEmbedder {
        print("⬇️ [BertCoreMLEmbedder] Loading \(model.displayName) from HuggingFace...")
        let bundle = try await Bert.loadModelBundle(from: model.rawValue)
        print("✅ [BertCoreMLEmbedder] Loaded \(model.displayName) (\(model.dimensions)d)")
        return BertCoreMLEmbedder(modelBundle: bundle, model: model)
    }

    public func embed(_ text: String) async throws -> [Float] {
        let output = modelBundle.encode(text)
        let result = await output.cast(to: Float.self).shapedArray(of: Float.self).scalars
        guard result.count >= dimensions else {
            throw CoreMLEmbedderError.dimensionMismatch(expected: dimensions, got: result.count)
        }
        return Array(result.prefix(dimensions))
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
}

enum CoreMLEmbedderError: LocalizedError {
    case dimensionMismatch(expected: Int, got: Int)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .dimensionMismatch(let expected, let got):
            return "CoreML embedding dimension mismatch: expected \(expected), got \(got)"
        case .loadFailed(let message):
            return "CoreML embedding model load failed: \(message)"
        }
    }
}
