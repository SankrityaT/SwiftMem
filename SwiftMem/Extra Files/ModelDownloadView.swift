//
//  ModelDownloadView.swift
//  SwiftMem
//
//  Created by Sankritya on 1/22/26.
//

import SwiftUI
import Combine

#if os(iOS)

/// Ready-to-use SwiftUI view for downloading embedding models
/// Host apps can embed this directly or build their own UI using ModelDownloadManager
public struct ModelDownloadView: View {
    
    @StateObject private var viewModel = ModelDownloadViewModel()
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 60))
                            .foregroundColor(.purple)
                        
                        Text("Embedding Models")
                            .font(.title2.bold())
                        
                        Text("Download a model to enable local memory embeddings")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)
                    
                    // Storage info
                    if viewModel.downloadedModels.count > 0 {
                        HStack {
                            Image(systemName: "internaldrive")
                                .foregroundColor(.blue)
                            Text("\(viewModel.downloadedModels.count) model(s) downloaded")
                            Spacer()
                            Text(viewModel.totalSizeFormatted)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Model list
                    VStack(spacing: 16) {
                        ForEach(ModelDownloadManager.EmbeddingModel.allCases, id: \.self) { model in
                            ModelCard(
                                model: model,
                                isDownloaded: viewModel.downloadedModels.contains(model),
                                progress: viewModel.downloadProgress[model],
                                onDownload: { viewModel.downloadModel(model) },
                                onDelete: { viewModel.deleteModel(model) },
                                onCancel: { viewModel.cancelDownload(model) }
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Embedding Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if viewModel.downloadedModels.count > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button(role: .destructive) {
                                viewModel.deleteAllModels()
                            } label: {
                                Label("Delete All Models", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .task {
                await viewModel.initialize()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
}

// MARK: - Model Card

struct ModelCard: View {
    let model: ModelDownloadManager.EmbeddingModel
    let isDownloaded: Bool
    let progress: ModelDownloadManager.DownloadProgress?
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    
    private var isDownloading: Bool {
        if let progress = progress,
           case .downloading = progress.status {
            return true
        }
        return false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                    
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status badge
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else if model == .nomicV2 {
                    Text("RECOMMENDED")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple)
                        .cornerRadius(4)
                }
            }
            
            // Download progress
            if let progress = progress, isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: progress.percentage)
                        .tint(.purple)
                    
                    HStack {
                        Text("\(Int(progress.percentage * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(formatBytes(progress.bytesDownloaded))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                if isDownloaded {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    
                } else if isDownloading {
                    Button {
                        onCancel()
                    } label: {
                        HStack {
                            Image(systemName: "xmark")
                            Text("Cancel")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    
                } else {
                    Button {
                        onDownload()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model == .nomicV2 ? .purple : .blue)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - View Model

@MainActor
class ModelDownloadViewModel: ObservableObject {
    
    @Published var downloadedModels: [ModelDownloadManager.EmbeddingModel] = []
    @Published var downloadProgress: [ModelDownloadManager.EmbeddingModel: ModelDownloadManager.DownloadProgress] = [:]
    @Published var totalSize: Int64 = 0
    @Published var showError = false
    @Published var errorMessage = ""
    
    private var downloadManager: ModelDownloadManager?
    
    var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    func initialize() async {
        do {
            downloadManager = try ModelDownloadManager()
            await refreshDownloadedModels()
        } catch {
            showError(error.localizedDescription)
        }
    }
    
    func refreshDownloadedModels() async {
        guard let manager = downloadManager else { return }
        
        downloadedModels = await manager.getDownloadedModels()
        let info = await manager.getStorageInfo()
        totalSize = info.totalSize
    }
    
    func downloadModel(_ model: ModelDownloadManager.EmbeddingModel) {
        guard let manager = downloadManager else { return }
        
        Task {
            do {
                _ = try await manager.downloadModel(model) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress[model] = progress
                        
                        if progress.isComplete {
                            await self?.refreshDownloadedModels()
                            self?.downloadProgress.removeValue(forKey: model)
                        }
                    }
                }
            } catch {
                showError("Failed to download \(model.displayName): \(error.localizedDescription)")
                downloadProgress.removeValue(forKey: model)
            }
        }
    }
    
    func cancelDownload(_ model: ModelDownloadManager.EmbeddingModel) {
        guard let manager = downloadManager else { return }
        
        Task {
            await manager.cancelDownload(model)
            downloadProgress.removeValue(forKey: model)
        }
    }
    
    func deleteModel(_ model: ModelDownloadManager.EmbeddingModel) {
        guard let manager = downloadManager else { return }
        
        Task {
            do {
                try await manager.deleteModel(model)
                await refreshDownloadedModels()
            } catch {
                showError("Failed to delete \(model.displayName): \(error.localizedDescription)")
            }
        }
    }
    
    func deleteAllModels() {
        guard let manager = downloadManager else { return }
        
        Task {
            do {
                try await manager.deleteAllModels()
                await refreshDownloadedModels()
            } catch {
                showError("Failed to delete models: \(error.localizedDescription)")
            }
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

#Preview {
    ModelDownloadView()
}

#endif
