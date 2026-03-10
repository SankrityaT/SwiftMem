//
//  SwiftMemDownloadState.swift
//  SwiftMem
//
//  Observable download state for embedding model downloads.
//  Observe SwiftMemDownloadState.shared in SwiftUI to show a progress overlay
//  while the GGUF model is downloading on first launch.
//

import Foundation
import Observation
import OnDeviceCatalyst

/// Observable download state for the embedding model.
/// - Usage: pass `SwiftMemDownloadState.shared` to `ModelDownloadProgressView` in your root view.
@MainActor
@Observable
public final class SwiftMemDownloadState {

    public static let shared = SwiftMemDownloadState()

    public enum Phase: Equatable {
        case idle
        case downloading(modelName: String, progress: Double, downloadedMB: Int, totalMB: Int)
        case verifying(modelName: String)
        case ready
        case failed(String)
    }

    public var phase: Phase = .idle

    /// True while a download or verification is in progress
    public var isActive: Bool {
        switch phase {
        case .idle, .ready: return false
        default: return true
        }
    }

    private init() {}

    /// Update state from a DownloadProgress event (called from EmbeddingEngine factory)
    func update(_ event: DownloadProgress) {
        switch event {
        case .starting(let name):
            phase = .downloading(modelName: name, progress: 0, downloadedMB: 0, totalMB: 0)
        case .downloading(let name, let prog, let dl, let total):
            phase = .downloading(modelName: name, progress: prog, downloadedMB: dl, totalMB: total)
        case .verifying(let name):
            phase = .verifying(modelName: name)
        case .completed, .alreadyCached:
            phase = .ready
        case .failed(_, let err):
            phase = .failed(err)
        }
    }
}
