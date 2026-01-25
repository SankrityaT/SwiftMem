//
//  EmbeddingTestView.swift
//  SwiftMem
//
//  Created by Sankritya on 1/22/26.
//

import SwiftUI
import UniformTypeIdentifiers
import OnDeviceCatalyst

struct EmbeddingTestView: View {
    @State private var status = "Ready"
    @State private var embeddingModel: LlamaInstance?
    @State private var embedder: OnDeviceCatalystEmbedder?
    @State private var testResults: [TestResult] = []
    @State private var isProcessing = false
    @State private var showFilePicker = false
    @State private var modelPath = ""
    
    struct TestResult: Identifiable {
        let id = UUID()
        let text: String
        let embedding: [Float]
        let time: TimeInterval
        
        var preview: String {
            let first5 = embedding.prefix(5).map { String(format: "%.4f", $0) }.joined(separator: ", ")
            return "[\(first5)...]"
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Status
                HStack {
                    Circle()
                        .fill(embeddingModel != nil ? Color.green : Color.orange)
                        .frame(width: 12, height: 12)
                    Text(status)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                
                // Model path
                if !modelPath.isEmpty {
                    Text("Model: \(URL(fileURLWithPath: modelPath).lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Actions
                VStack(spacing: 12) {
                    Button("1. Load Embedding Model") {
                        showFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(embeddingModel != nil)
                    
                    Button("2. Test Single Embedding") {
                        testSingleEmbedding()
                    }
                    .buttonStyle(.bordered)
                    .disabled(embedder == nil || isProcessing)
                    
                    Button("3. Import JSON & Test Batch") {
                        importJSON()
                    }
                    .buttonStyle(.bordered)
                    .disabled(embedder == nil || isProcessing)
                }
                
                // Results
                if !testResults.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Results (\(testResults.count))")
                                .font(.headline)
                            
                            ForEach(testResults) { result in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.text)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    
                                    Text("Dims: \(result.embedding.count) • Time: \(Int(result.time * 1000))ms")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(result.preview)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Embedding Test")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }
    
    func handleFileSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first else { return }
        
        modelPath = url.path
        
        Task {
            isProcessing = true
            status = "Loading model..."
            
            do {
                let profile = try ModelProfile(filePath: url.path)
                let settings = InstanceSettings(
                    contextLength: 512,
                    batchSize: 512,
                    gpuLayers: 99,
                    cpuThreads: 4,
                    enableMemoryMapping: true,
                    enableMemoryLocking: false,
                    useFlashAttention: false
                )
                
                embeddingModel = LlamaInstance(
                    profile: profile,
                    settings: settings,
                    predictionConfig: .balanced
                )
                
                for await progress in embeddingModel!.initialize() {
                    status = progress.message
                }
                
                // Infer dimensions from model filename
                let dims: Int
                let filename = url.lastPathComponent.lowercased()
                if filename.contains("nomic") {
                    dims = 768
                } else if filename.contains("bge-base") {
                    dims = 768
                } else if filename.contains("mxbai") {
                    dims = 1024
                } else {
                    dims = 384  // Default for bge-small and most small models
                }
                
                embedder = OnDeviceCatalystEmbedder(
                    llama: embeddingModel!,
                    dimensions: dims,
                    modelIdentifier: profile.name
                )
                
                status = "✅ Ready (\(dims) dims)"
                
            } catch {
                status = "❌ Failed: \(error.localizedDescription)"
            }
            
            isProcessing = false
        }
    }
    
    func testSingleEmbedding() {
        guard let embedder = embedder else { return }
        
        Task {
            isProcessing = true
            status = "Generating embedding..."
            
            let testText = "This is a test sentence for embedding generation."
            let start = Date()
            
            do {
                let embedding = try await embedder.embed(testText)
                let time = Date().timeIntervalSince(start)
                
                testResults.insert(
                    TestResult(text: testText, embedding: embedding, time: time),
                    at: 0
                )
                
                status = "✅ Generated \(embedding.count)D vector in \(Int(time * 1000))ms"
                
            } catch {
                status = "❌ Error: \(error.localizedDescription)"
            }
            
            isProcessing = false
        }
    }
    
    func importJSON() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.allowsMultipleSelection = false
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            
            let coordinator = JSONPickerCoordinator(onPick: { url in
                processJSON(url)
            })
            picker.delegate = coordinator
            
            // Keep coordinator alive
            objc_setAssociatedObject(picker, "coordinator", coordinator, .OBJC_ASSOCIATION_RETAIN)
            
            root.present(picker, animated: true)
        }
    }
    
    func processJSON(_ url: URL) {
        guard let embedder = embedder else { return }
        
        Task {
            isProcessing = true
            status = "Processing JSON..."
            
            do {
                let data = try Data(contentsOf: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
                
                var texts: [String] = []
                for item in json {
                    if let text = item["text"] as? String {
                        texts.append(text)
                    } else if let content = item["content"] as? String {
                        texts.append(content)
                    }
                }
                
                guard !texts.isEmpty else {
                    status = "❌ No text fields found in JSON"
                    isProcessing = false
                    return
                }
                
                status = "Embedding \(texts.count) items..."
                let start = Date()
                
                for (index, text) in texts.prefix(10).enumerated() {
                    let embedding = try await embedder.embed(text)
                    let time = Date().timeIntervalSince(start) / Double(index + 1)
                    
                    testResults.insert(
                        TestResult(text: text, embedding: embedding, time: time),
                        at: 0
                    )
                }
                
                let totalTime = Date().timeIntervalSince(start)
                status = "✅ Processed \(min(texts.count, 10)) items in \(String(format: "%.2f", totalTime))s"
                
            } catch {
                status = "❌ Error: \(error.localizedDescription)"
            }
            
            isProcessing = false
        }
    }
}

class JSONPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void
    
    init(onPick: @escaping (URL) -> Void) {
        self.onPick = onPick
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        onPick(url)
    }
}

#Preview {
    EmbeddingTestView()
}
