//
//  OnDeviceCatalystEmbedder.swift
//  SwiftMem
//
//  Created by Sankritya on 12/9/25.
//  Thin adapter to use an existing OnDeviceCatalyst LlamaInstance as a SwiftMem Embedder.
//

#if canImport(OnDeviceCatalyst)
import Foundation
import OnDeviceCatalyst

/// Adapter that lets SwiftMem use an OnDeviceCatalyst LlamaInstance
/// as its embedding backend. This lives outside both core packages
/// so that SwiftMem stays model-agnostic and OnDeviceCatalyst stays
/// focused on llama.cpp / GGUF concerns.
public struct OnDeviceCatalystEmbedder: Embedder {
    /// Underlying model instance from OnDeviceCatalyst.
    public let llama: LlamaInstance
    
    /// Fixed embedding dimensionality for this model.
    /// You can determine this from the model profile or via
    /// LlamaBridge.getEmbeddingSize(...) when constructing
    /// the embedder.
    public let dimensions: Int
    
    /// Identifier for this embedding model (e.g. filename or friendly name).
    public let modelIdentifier: String
    
    public init(
        llama: LlamaInstance,
        dimensions: Int,
        modelIdentifier: String
    ) {
        self.llama = llama
        self.dimensions = dimensions
        self.modelIdentifier = modelIdentifier
    }
    
    // MARK: - Embedder
    
    public func embed(_ text: String) async throws -> [Float] {
        // LlamaInstance.embed(text:) is synchronous but potentially heavy;
        // callers should be prepared to run this off the main thread.
        return try llama.embed(text: text)
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        // For safety, run sequentially against a single LlamaInstance,
        // since the underlying llama.cpp context is not designed for
        // concurrent mutation.
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        
        for text in texts {
            let emb = try llama.embed(text: text)
            results.append(emb)
        }
        
        return results
    }
}
#endif
