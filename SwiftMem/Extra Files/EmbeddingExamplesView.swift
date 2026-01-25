//
//  EmbeddingExamplesView.swift
//  SwiftMem
//
//  Created by Sankritya on 1/22/26.
//

import SwiftUI

#if os(iOS)

struct EmbeddingExamplesView: View {
    @State private var selectedExample: ExampleType = .dedicatedLocal
    @State private var status: String = "Ready"
    @State private var isProcessing = false
    @State private var embeddingInfo: String = ""
    
    enum ExampleType: String, CaseIterable {
        case dedicatedLocal = "Dedicated Local (bge-small)"
        case chatModelFallback = "Chat Model Fallback (Qwen)"
        case cloudAPI = "Cloud API (OpenAI)"
        case appleNL = "Apple NLEmbedding"
        case autoSelect = "Auto-Select (Smart)"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Example selector
                Picker("Embedding Strategy", selection: $selectedExample) {
                    ForEach(ExampleType.allCases, id: \.self) { example in
                        Text(example.rawValue).tag(example)
                    }
                }
                .pickerStyle(.menu)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                
                // Status
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: isProcessing ? "hourglass" : "checkmark.circle.fill")
                            .foregroundColor(isProcessing ? .orange : .green)
                        Text(status)
                            .font(.headline)
                    }
                    
                    if !embeddingInfo.isEmpty {
                        Text(embeddingInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                
                // Example code
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Example Code")
                            .font(.headline)
                        
                        Text(getExampleCode())
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                
                Spacer()
                
                // Test button
                Button {
                    testEmbedding()
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isProcessing ? "Testing..." : "Test Embedding")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isProcessing)
            }
            .padding()
            .navigationTitle("Embedding Examples")
        }
    }
    
    func getExampleCode() -> String {
        switch selectedExample {
        case .dedicatedLocal:
            return """
// Best option: Dedicated embedding model
let config = EmbedderFactory.EmbedderConfig.fullyLocal(
    embeddingModelPath: "/path/to/bge-small-en-v1.5-q4_k_m.gguf"
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)

var swiftMemConfig = SwiftMemConfig.default
swiftMemConfig.embeddingDimensions = dims

let swiftMem = try await SwiftMemClient.makeOnDisk(
    config: swiftMemConfig,
    embedder: embedder
)
"""
            
        case .chatModelFallback:
            return """
// Fallback: Use your chat model (Qwen) for embeddings
let qwen = LlamaInstance(...)  // Your existing chat model
for await _ in qwen.initialize() { }

let config = EmbedderFactory.EmbedderConfig.fullyLocal(
    chatModel: qwen
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)

// Now SwiftMem uses Qwen for embeddings
// ⚠️ Slower and less optimal than dedicated model
"""
            
        case .cloudAPI:
            return """
// Cloud API: Fast but requires internet
let config = EmbedderFactory.EmbedderConfig.cloudFirst(
    apiKeys: ["openai": "sk-..."]
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)

// Uses OpenAI's text-embedding-3-small
// Fast, high quality, but costs money
"""
            
        case .appleNL:
            return """
// Apple NLEmbedding: Built-in, no download
let config = EmbedderFactory.EmbedderConfig(
    preferredStrategy: .appleNL,
    enableFallback: false
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)

// Uses iOS built-in embeddings
// Good quality, 512 dimensions
"""
            
        case .autoSelect:
            return """
// Auto-select: Tries best option automatically
// Order: dedicated local → chat model → cloud → Apple NL

let config = EmbedderFactory.EmbedderConfig(
    preferredStrategy: .auto,
    enableFallback: true,
    apiKeys: ["openai": "sk-..."],  // Optional
    localEmbeddingModelPath: "/path/to/bge-small.gguf"  // Optional
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)

// Automatically picks the best available option
// Perfect for production apps
"""
        }
    }
    
    func testEmbedding() {
        Task {
            isProcessing = true
            status = "Testing..."
            embeddingInfo = ""
            
            do {
                let config: EmbedderFactory.EmbedderConfig
                
                switch selectedExample {
                case .dedicatedLocal:
                    config = .fullyLocal(
                        embeddingModelPath: nil  // User needs to provide path
                    )
                    
                case .chatModelFallback:
                    config = .fullyLocal(
                        chatModel: nil  // User needs to provide instance
                    )
                    
                case .cloudAPI:
                    config = .cloudFirst(
                        apiKeys: [:]  // User needs to provide keys
                    )
                    
                case .appleNL:
                    config = EmbedderFactory.EmbedderConfig(
                        preferredStrategy: .appleNL,
                        enableFallback: false
                    )
                    
                case .autoSelect:
                    config = EmbedderFactory.EmbedderConfig(
                        preferredStrategy: .auto,
                        enableFallback: true
                    )
                }
                
                let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)
                
                // Test embedding
                let testText = "This is a test sentence for embedding generation."
                let embedding = try await embedder.embed(testText)
                
                status = "Success!"
                embeddingInfo = """
                Model: \(embedder.modelIdentifier)
                Dimensions: \(dims)
                Vector length: \(embedding.count)
                First 5 values: \(embedding.prefix(5).map { String(format: "%.4f", $0) }.joined(separator: ", "))
                """
                
            } catch {
                status = "Failed"
                embeddingInfo = error.localizedDescription
            }
            
            isProcessing = false
        }
    }
}

#Preview {
    EmbeddingExamplesView()
}

#endif
