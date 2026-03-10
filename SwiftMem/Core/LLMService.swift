//
//  LLMService.swift
//  SwiftMem
//
//  Shared LLM service actor wrapping OnDeviceCatalyst for completion tasks
//

import Foundation
import OnDeviceCatalyst

/// Shared actor providing on-device LLM completion capabilities
/// Used for fact extraction, reranking, and classification
public actor LLMService {

    private var modelProfile: ModelProfile?
    private let config: LLMConfig
    private var isReady = false

    public init(config: LLMConfig) {
        self.config = config
    }

    // MARK: - Initialization

    /// Load the completion model. Returns true if LLM is available.
    /// Resolves preset models (auto-downloads from HuggingFace) or uses explicit path.
    public func initialize() async -> Bool {
        // Resolve model path: preset > explicit path
        var modelPath = config.completionModelPath
        var architecture = config.completionArchitecture
        var modelName: String?

        // Try preset model (auto-download)
        if modelPath == nil, let preset = config.completionModel {
            do {
                modelPath = try await ModelDownloader.shared.resolve(preset)
                architecture = preset.architecture
                modelName = preset.rawValue
                print("✅ [LLMService] Resolved preset: \(preset.displayName)")
            } catch {
                print("⚠️ [LLMService] Failed to resolve preset \(preset.rawValue): \(error.localizedDescription)")
                return false
            }
        }

        guard let resolvedPath = modelPath else {
            print("ℹ️ [LLMService] No completion model configured")
            return false
        }

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            print("⚠️ [LLMService] Completion model not found at: \(resolvedPath)")
            return false
        }

        do {
            let arch = architecture ?? ModelArchitecture.detectFromPath(resolvedPath)
            let name = modelName ?? URL(fileURLWithPath: resolvedPath).deletingPathExtension().lastPathComponent

            let profile = try ModelProfile(
                filePath: resolvedPath,
                name: name,
                architecture: arch
            )

            // Validate model loads successfully
            let result = await Catalyst.loadModelSafely(
                profile: profile,
                settings: .balanced,
                predictionConfig: .balanced
            )

            switch result {
            case .success:
                self.modelProfile = profile
                self.isReady = true
                print("✅ [LLMService] Completion model loaded: \(profile.name)")
                return true
            case .failure(let error):
                print("⚠️ [LLMService] Failed to load completion model: \(error.localizedDescription)")
                return false
            }
        } catch {
            print("⚠️ [LLMService] Failed to create model profile: \(error.localizedDescription)")
            return false
        }
    }

    /// Whether the LLM service is available for use
    public var isAvailable: Bool { isReady }

    // MARK: - Completion

    /// Run a completion with timeout. Returns nil on any failure (graceful degradation).
    public func complete(
        prompt: String,
        systemPrompt: String = "You are a helpful AI assistant.",
        maxTokens: Int = 512
    ) async -> String? {
        guard let profile = modelProfile, isReady else { return nil }

        do {
            let predictionConfig = PredictionConfig(
                temperature: 0.1,
                topK: 40,
                topP: 0.9,
                minP: 0.0,
                typicalP: 1.0,
                repetitionPenalty: 1.1,
                repetitionPenaltyRange: 64,
                frequencyPenalty: 0.0,
                presencePenalty: 0.0,
                mirostatMode: 0,
                mirostatTau: 5.0,
                mirostatEta: 0.1,
                maxTokens: maxTokens,
                stopSequences: []
            )

            let result: String? = try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask {
                    let response = try await Catalyst.shared.complete(
                        prompt: prompt,
                        systemPrompt: systemPrompt,
                        using: profile,
                        settings: .balanced,
                        predictionConfig: predictionConfig
                    )
                    return response
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.config.llmTimeout * 1_000_000_000))
                    return nil // Timeout sentinel
                }

                // Take whichever finishes first
                if let first = try await group.next() {
                    group.cancelAll()
                    return first
                }
                return nil
            }

            return result
        } catch {
            print("⚠️ [LLMService] Completion failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - HyDE (Hypothetical Document Embedding)

    /// Generate a hypothetical memory document for query expansion (HyDE).
    /// Given "what food do I prefer?" returns a plausible memory like "User loves sushi and avoids spicy food."
    /// Returns nil on any failure — caller blends result 50/50 with original query embedding.
    public func generateHypotheticalDocument(query: String, maxTokens: Int = 150) async -> String? {
        let prompt = """
        Given this search query about a person's memories, write a single plausible stored memory that would answer it.
        Write as a concise factual statement (1-2 sentences). Be specific.

        Query: \(query)

        Memory:
        """
        return await complete(
            prompt: prompt,
            systemPrompt: "You are a memory content generator. Write realistic, specific memory facts in 1-2 sentences.",
            maxTokens: maxTokens
        )
    }

    // MARK: - Cleanup

    /// Release the loaded model to free memory
    public func release() async {
        if let profile = modelProfile {
            await Catalyst.shared.releaseInstance(for: profile.id)
            self.modelProfile = nil
            self.isReady = false
            print("🗑️ [LLMService] Released completion model")
        }
    }
}
