//
//  GGUFEmbedder.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-02-26.
//

import Foundation
import OnDeviceCatalyst

/// Embedder that uses GGUF embedding models via OnDeviceCatalyst
/// Supports models like gte-Qwen2-1.5B-instruct (1536-dim), nomic-embed-text-v1.5 (768-dim), etc.
///
/// **Recommended Models:**
/// - gte-Qwen2-1.5B-instruct: 1536 dims, 32k context, SOTA performance (~1GB)
///   Download: https://huggingface.co/mav23/gte-Qwen2-1.5B-instruct-GGUF
/// - nomic-embed-text-v1.5: 768 dims, 8k context, efficient (~550MB)
///   Download: https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF
public actor GGUFEmbedder: Embedder {
    public let dimensions: Int
    public let modelIdentifier: String
    
    private let modelProfile: ModelProfile
    private let embeddingSettings: InstanceSettings
    
    /// Initialize with a GGUF embedding model
    /// - Parameters:
    ///   - modelPath: Path to the GGUF model file
    ///   - dimensions: Embedding dimensions (1536 for gte-Qwen2-1.5B, 768 for nomic-embed-text-v1.5)
    ///   - architecture: Model architecture (use .qwen25 for gte-Qwen2, .mistral for nomic-embed)
    ///   - modelIdentifier: Model identifier for caching
    public init(
        modelPath: String,
        dimensions: Int = 1536,
        architecture: ModelArchitecture = .qwen25,
        modelIdentifier: String = "gte-qwen2-1.5b"
    ) throws {
        self.dimensions = dimensions
        self.modelIdentifier = modelIdentifier
        
        // Verify model file exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw GGUFEmbedderError.modelNotFound(modelPath)
        }
        
        // Create model profile for embedding
        self.modelProfile = try ModelProfile(
            filePath: modelPath,
            name: modelIdentifier,
            architecture: architecture
        )
        
        // Use embedding-optimized settings
        self.embeddingSettings = .embedding()
    }
    
    public func embed(_ text: String) async throws -> [Float] {
        do {
            let embedding = try await Catalyst.shared.getEmbedding(
                text: text,
                using: modelProfile,
                settings: embeddingSettings
            )
            
            // Verify dimensions match
            guard embedding.count == dimensions else {
                throw GGUFEmbedderError.dimensionMismatch(
                    expected: dimensions,
                    got: embedding.count
                )
            }
            
            return embedding
        } catch let error as CatalystError {
            throw GGUFEmbedderError.embeddingFailed(error.localizedDescription)
        } catch {
            throw error
        }
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        do {
            return try await Catalyst.shared.getEmbeddingBatch(
                texts: texts,
                using: modelProfile,
                settings: embeddingSettings
            )
        } catch let error as CatalystError {
            throw GGUFEmbedderError.embeddingFailed(error.localizedDescription)
        } catch {
            throw error
        }
    }
}

// MARK: - Errors

enum GGUFEmbedderError: LocalizedError {
    case modelNotFound(String)
    case dimensionMismatch(expected: Int, got: Int)
    case embeddingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Embedding model not found at: \(path)"
        case .dimensionMismatch(let expected, let got):
            return "Dimension mismatch: expected \(expected), got \(got)"
        case .embeddingFailed(let message):
            return "Embedding extraction failed: \(message)"
        }
    }
}
