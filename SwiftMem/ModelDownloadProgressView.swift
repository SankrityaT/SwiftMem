//
//  ModelDownloadProgressView.swift
//  SwiftMem
//
//  Shows download progress for GGUF embedding models during first launch.
//  Usage: .overlay(ModelDownloadProgressView(state: SwiftMemDownloadState.shared))
//

import SwiftUI

/// Full-screen overlay displayed while an embedding model is downloading or verifying.
struct ModelDownloadProgressView: View {

    var state: SwiftMemDownloadState

    var body: some View {
        if state.isActive {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    icon

                    VStack(spacing: 8) {
                        titleText
                        subtitleText
                    }

                    progressSection

                    Text("This happens only once. The model will be cached for future launches.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(28)
                .frame(maxWidth: 360)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(32)
            }
            .animation(.easeInOut(duration: 0.3), value: state.isActive)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var icon: some View {
        switch state.phase {
        case .verifying:
            Image(systemName: "checkmark.shield")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.orange)
        default:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
        }
    }

    @ViewBuilder
    private var titleText: some View {
        switch state.phase {
        case .downloading:
            Text("Downloading AI Model")
                .font(.headline)
        case .verifying:
            Text("Verifying Model")
                .font(.headline)
        case .failed:
            Text("Download Failed")
                .font(.headline)
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        switch state.phase {
        case .downloading(let name, _, _, _), .verifying(let name):
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .failed(let err):
            Text(err)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        switch state.phase {
        case .downloading(_, let progress, let downloaded, let total):
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(.blue)

                HStack {
                    Text("\(downloaded) MB / \(total) MB")
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .fontWeight(.medium)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        case .verifying:
            ProgressView()
                .tint(.blue)
        default:
            EmptyView()
        }
    }
}
