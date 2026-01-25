//
//  ModelDownloadManager.swift
//  SwiftMem
//
//  Created by Sankritya on 1/22/26.
//

import Foundation

/// Manager for downloading and caching embedding models
/// Designed for use in Swift Package - host apps control when/how to download
public actor ModelDownloadManager {
    
    // MARK: - Model Registry
    
    /// Available embedding models
    public enum EmbeddingModel: String, CaseIterable {
        case nomicV2 = "nomic-embed-text-v2"
        case bgeSmall = "bge-small-en-v1.5"
        case bgeBase = "bge-base-en-v1.5"
        case mxbaiLarge = "mxbai-embed-large"
        case allMiniLM = "all-MiniLM-L6-v2"
        
        public var displayName: String {
            switch self {
            case .nomicV2: return "Nomic Embed v2 (Recommended)"
            case .bgeSmall: return "BGE Small (Lightweight)"
            case .bgeBase: return "BGE Base (Balanced)"
            case .mxbaiLarge: return "MxBai Large (High Quality)"
            case .allMiniLM: return "MiniLM (Minimal)"
            }
        }
        
        public var description: String {
            switch self {
            case .nomicV2: return "140MB • 768 dims • 8k context • SOTA 2026"
            case .bgeSmall: return "45MB • 384 dims • 512 context • Fast"
            case .bgeBase: return "220MB • 768 dims • 512 context • Quality"
            case .mxbaiLarge: return "340MB • 1024 dims • 512 context • Best"
            case .allMiniLM: return "25MB • 384 dims • 512 context • Minimal"
            }
        }
        
        public var downloadURL: URL {
            switch self {
            case .nomicV2:
                return URL(string: "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf")!
            case .bgeSmall:
                return URL(string: "https://huggingface.co/CompendiumLabs/bge-small-en-v1.5-gguf/resolve/main/bge-small-en-v1.5-q4_k_m.gguf")!
            case .bgeBase:
                return URL(string: "https://huggingface.co/CompendiumLabs/bge-base-en-v1.5-gguf/resolve/main/bge-base-en-v1.5-q4_k_m.gguf")!
            case .mxbaiLarge:
                return URL(string: "https://huggingface.co/mixedbread-ai/mxbai-embed-large-v1/resolve/main/gguf/mxbai-embed-large-v1-q4_k_m.gguf")!
            case .allMiniLM:
                return URL(string: "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/gguf/all-MiniLM-L6-v2-Q4_K_M.gguf")!
            }
        }
        
        public var expectedSize: Int64 {
            switch self {
            case .nomicV2: return 140_000_000  // 140MB
            case .bgeSmall: return 45_000_000   // 45MB
            case .bgeBase: return 220_000_000   // 220MB
            case .mxbaiLarge: return 340_000_000 // 340MB
            case .allMiniLM: return 25_000_000   // 25MB
            }
        }
        
        public var dimensions: Int {
            switch self {
            case .nomicV2: return 768
            case .bgeSmall: return 384
            case .bgeBase: return 768
            case .mxbaiLarge: return 1024
            case .allMiniLM: return 384
            }
        }
        
        public var filename: String {
            return "\(rawValue).gguf"
        }
    }
    
    // MARK: - Download Progress
    
    public struct DownloadProgress {
        public let model: EmbeddingModel
        public let bytesDownloaded: Int64
        public let totalBytes: Int64
        public let percentage: Double
        public let status: DownloadStatus
        
        public enum DownloadStatus {
            case pending
            case downloading
            case completed
            case failed(Error)
            case cancelled
        }
        
        public var isComplete: Bool {
            if case .completed = status { return true }
            return false
        }
    }
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private var activeDownloads: [EmbeddingModel: URLSessionDownloadTask] = [:]
    private var downloadSessions: [EmbeddingModel: URLSession] = [:]
    
    // Storage location for models
    private let modelsDirectory: URL
    
    // MARK: - Initialization
    
    public init(storageLocation: URL? = nil) throws {
        // Default to Application Support if not specified
        if let customLocation = storageLocation {
            self.modelsDirectory = customLocation
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.modelsDirectory = appSupport.appendingPathComponent("SwiftMem/Models", isDirectory: true)
        }
        
        // Create models directory
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Check if a model is already downloaded
    public func isModelDownloaded(_ model: EmbeddingModel) -> Bool {
        let modelPath = modelsDirectory.appendingPathComponent(model.filename)
        return fileManager.fileExists(atPath: modelPath.path)
    }
    
    /// Get the file path for a downloaded model
    public func getModelPath(_ model: EmbeddingModel) -> URL? {
        let modelPath = modelsDirectory.appendingPathComponent(model.filename)
        return fileManager.fileExists(atPath: modelPath.path) ? modelPath : nil
    }
    
    /// Get all downloaded models
    public func getDownloadedModels() -> [EmbeddingModel] {
        return EmbeddingModel.allCases.filter { isModelDownloaded($0) }
    }
    
    /// Get storage info
    public func getStorageInfo() -> (totalSize: Int64, modelCount: Int) {
        let models = getDownloadedModels()
        var totalSize: Int64 = 0
        
        for model in models {
            if let path = getModelPath(model),
               let attrs = try? fileManager.attributesOfItem(atPath: path.path),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }
        
        return (totalSize, models.count)
    }
    
    /// Download a model with progress tracking
    public func downloadModel(
        _ model: EmbeddingModel,
        progressHandler: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        
        // Check if already downloaded
        if let existingPath = getModelPath(model) {
            print("✅ [ModelDownloadManager] Model already downloaded: \(model.rawValue)")
            progressHandler(DownloadProgress(
                model: model,
                bytesDownloaded: model.expectedSize,
                totalBytes: model.expectedSize,
                percentage: 1.0,
                status: .completed
            ))
            return existingPath
        }
        
        // Check if already downloading
        if activeDownloads[model] != nil {
            throw SwiftMemError.configurationError("Model \(model.rawValue) is already being downloaded")
        }
        
        print("🔄 [ModelDownloadManager] Starting download: \(model.rawValue)")
        print("   URL: \(model.downloadURL)")
        print("   Expected size: \(ByteCountFormatter.string(fromByteCount: model.expectedSize, countStyle: .file))")
        
        // Create download task
        let destinationURL = modelsDirectory.appendingPathComponent(model.filename)
        
        return try await withCheckedThrowingContinuation { continuation in
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300 // 5 minutes
            config.timeoutIntervalForResource = 3600 // 1 hour
            
            let session = URLSession(configuration: config)
            downloadSessions[model] = session
            
            let task = session.downloadTask(with: model.downloadURL) { [weak self] tempURL, response, error in
                Task {
                    await self?.handleDownloadCompletion(
                        model: model,
                        tempURL: tempURL,
                        response: response,
                        error: error,
                        destinationURL: destinationURL,
                        progressHandler: progressHandler,
                        continuation: continuation
                    )
                }
            }
            
            activeDownloads[model] = task
            
            // Start download
            task.resume()
            
            progressHandler(DownloadProgress(
                model: model,
                bytesDownloaded: 0,
                totalBytes: model.expectedSize,
                percentage: 0.0,
                status: .downloading
            ))
        }
    }
    
    /// Cancel an active download
    public func cancelDownload(_ model: EmbeddingModel) {
        activeDownloads[model]?.cancel()
        activeDownloads.removeValue(forKey: model)
        downloadSessions[model]?.invalidateAndCancel()
        downloadSessions.removeValue(forKey: model)
        print("❌ [ModelDownloadManager] Cancelled download: \(model.rawValue)")
    }
    
    /// Delete a downloaded model
    public func deleteModel(_ model: EmbeddingModel) throws {
        guard let modelPath = getModelPath(model) else {
            throw SwiftMemError.configurationError("Model \(model.rawValue) not found")
        }
        
        try fileManager.removeItem(at: modelPath)
        print("🗑️ [ModelDownloadManager] Deleted model: \(model.rawValue)")
    }
    
    /// Delete all downloaded models
    public func deleteAllModels() throws {
        let models = getDownloadedModels()
        for model in models {
            try deleteModel(model)
        }
        print("🗑️ [ModelDownloadManager] Deleted all models")
    }
    
    // MARK: - Private Helpers
    
    private func handleDownloadCompletion(
        model: EmbeddingModel,
        tempURL: URL?,
        response: URLResponse?,
        error: Error?,
        destinationURL: URL,
        progressHandler: @escaping (DownloadProgress) -> Void,
        continuation: CheckedContinuation<URL, Error>
    ) async {
        
        // Clean up
        activeDownloads.removeValue(forKey: model)
        downloadSessions[model]?.invalidateAndCancel()
        downloadSessions.removeValue(forKey: model)
        
        // Handle error
        if let error = error {
            print("❌ [ModelDownloadManager] Download failed: \(error.localizedDescription)")
            progressHandler(DownloadProgress(
                model: model,
                bytesDownloaded: 0,
                totalBytes: model.expectedSize,
                percentage: 0.0,
                status: .failed(error)
            ))
            continuation.resume(throwing: error)
            return
        }
        
        // Validate temp file
        guard let tempURL = tempURL else {
            let error = SwiftMemError.configurationError("No temporary file URL")
            progressHandler(DownloadProgress(
                model: model,
                bytesDownloaded: 0,
                totalBytes: model.expectedSize,
                percentage: 0.0,
                status: .failed(error)
            ))
            continuation.resume(throwing: error)
            return
        }
        
        do {
            // Validate file size
            let attrs = try fileManager.attributesOfItem(atPath: tempURL.path)
            let fileSize = attrs[.size] as? Int64 ?? 0
            
            print("✅ [ModelDownloadManager] Download completed")
            print("   File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
            
            // Move to final location
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.moveItem(at: tempURL, to: destinationURL)
            
            print("✅ [ModelDownloadManager] Model saved: \(destinationURL.path)")
            
            progressHandler(DownloadProgress(
                model: model,
                bytesDownloaded: fileSize,
                totalBytes: fileSize,
                percentage: 1.0,
                status: .completed
            ))
            
            continuation.resume(returning: destinationURL)
            
        } catch {
            print("❌ [ModelDownloadManager] Failed to save model: \(error.localizedDescription)")
            progressHandler(DownloadProgress(
                model: model,
                bytesDownloaded: 0,
                totalBytes: model.expectedSize,
                percentage: 0.0,
                status: .failed(error)
            ))
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - Convenience Extensions

extension ModelDownloadManager {
    
    /// Download the recommended model (nomic-v2)
    public func downloadRecommended(
        progressHandler: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        return try await downloadModel(.nomicV2, progressHandler: progressHandler)
    }
    
    /// Get the best available model (downloaded or fallback)
    public func getBestAvailableModel() -> (model: EmbeddingModel, path: URL)? {
        // Priority order: nomic-v2 > bge-base > mxbai > bge-small > all-minilm
        let priority: [EmbeddingModel] = [.nomicV2, .bgeBase, .mxbaiLarge, .bgeSmall, .allMiniLM]
        
        for model in priority {
            if let path = getModelPath(model) {
                return (model, path)
            }
        }
        
        return nil
    }
}
