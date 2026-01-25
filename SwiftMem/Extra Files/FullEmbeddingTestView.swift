//
//  FullEmbeddingTestView.swift
//  SwiftMem
//
//  Created by Sankritya on 1/22/26.
//

import SwiftUI
import OnDeviceCatalyst
import Combine

struct FullEmbeddingTestView: View {
    @StateObject private var viewModel = FullEmbeddingTestViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Status
                    StatusCard(status: viewModel.status, step: viewModel.currentStep)
                    
                    // Step 1: Using NLEmbedding (no download needed)
                    StepCard(
                        number: 1,
                        title: "Embedding Model (NLEmbedding)",
                        isComplete: true,
                        isActive: false
                    ) {
                        Text("✅ Using Apple NLEmbedding (512-dim)")
                            .foregroundColor(.green)
                        Text("Built-in, no download needed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Step 2: Load Riley JSON
                    StepCard(
                        number: 2,
                        title: "Load Riley Brooks JSON",
                        isComplete: viewModel.jsonLoaded,
                        isActive: viewModel.currentStep == 2
                    ) {
                        if viewModel.jsonLoaded {
                            Text("✅ Loaded \(viewModel.entryCount) entries")
                                .foregroundColor(.green)
                        } else {
                            Button("Load riley_brooks_context.json") {
                                viewModel.loadRileyJSON()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!viewModel.modelDownloaded)
                        }
                    }
                    
                    // Step 3: Generate Embeddings
                    StepCard(
                        number: 3,
                        title: "Generate Embeddings",
                        isComplete: viewModel.embeddingsGenerated,
                        isActive: viewModel.currentStep == 3
                    ) {
                        if viewModel.embeddingsGenerated {
                            Text("✅ Generated \(viewModel.embeddingCount) embeddings")
                                .foregroundColor(.green)
                            Text("Avg time: \(viewModel.avgEmbeddingTime)ms")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if viewModel.isEmbedding {
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Embedding \(viewModel.embeddingProgress)/\(viewModel.entryCount)...")
                                    .font(.caption)
                            }
                        } else {
                            Button("Generate Embeddings") {
                                viewModel.generateEmbeddings()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!viewModel.jsonLoaded || viewModel.isEmbedding)
                        }
                    }
                    
                    // Step 4: Test Retrieval
                    StepCard(
                        number: 4,
                        title: "Test Retrieval with Groq",
                        isComplete: false,
                        isActive: viewModel.currentStep == 4
                    ) {
                        VStack(spacing: 12) {
                            TextField("Ask a question about Riley...", text: $viewModel.testQuery)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!viewModel.embeddingsGenerated)
                            
                            Button("Search & Ask Groq") {
                                viewModel.testRetrieval()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!viewModel.embeddingsGenerated || viewModel.testQuery.isEmpty)
                            
                            if viewModel.isTesting {
                                ProgressView("Testing...")
                            }
                            
                            if !viewModel.retrievedEntries.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Retrieved \(viewModel.retrievedEntries.count) relevant entries:")
                                        .font(.caption.bold())
                                    
                                    ForEach(viewModel.retrievedEntries.indices, id: \.self) { i in
                                        Text("• \(viewModel.retrievedEntries[i])")
                                            .font(.caption)
                                            .lineLimit(2)
                                    }
                                }
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                            
                            if !viewModel.groqResponse.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Groq Response:")
                                        .font(.caption.bold())
                                    Text(viewModel.groqResponse)
                                        .font(.body)
                                }
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Full Embedding Test")
        }
    }
}

struct StatusCard: View {
    let status: String
    let step: Int
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Step \(step)/4")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(status)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let isComplete: Bool
    let isActive: Bool
    let content: Content
    
    init(
        number: Int,
        title: String,
        isComplete: Bool,
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.number = number
        self.title = title
        self.isComplete = isComplete
        self.isActive = isActive
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(isComplete ? Color.green : (isActive ? Color.blue : Color.gray))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text("\(number)")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    )
                
                Text(title)
                    .font(.headline)
                
                Spacer()
            }
            
            content
        }
        .padding()
        .background(isActive ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

@MainActor
class FullEmbeddingTestViewModel: ObservableObject {
    @Published var status = "Ready to start - Using NLEmbedding"
    @Published var currentStep = 2  // Skip to step 2 since NLEmbedding is always ready
    
    // Step 1: Download (not needed for NLEmbedding)
    @Published var modelDownloaded = true
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 1.0
    @Published var modelName = "NLEmbedding"
    
    // Step 2: Load JSON
    @Published var jsonLoaded = false
    @Published var entryCount = 0
    
    // Step 3: Generate Embeddings
    @Published var embeddingsGenerated = false
    @Published var isEmbedding = false
    @Published var embeddingProgress = 0
    @Published var embeddingCount = 0
    @Published var avgEmbeddingTime = 0
    
    // Step 4: Test Retrieval
    @Published var testQuery = "What is Riley working on?"
    @Published var isTesting = false
    @Published var retrievedEntries: [String] = []
    @Published var groqResponse = ""
    
    private var downloadManager: ModelDownloadManager?
    private var embeddingModel: LlamaInstance?
    private var embedder: Embedder?
    private var entries: [String] = []
    private var embeddings: [[Float]] = []
    
    init() {
        Task {
            downloadManager = try? ModelDownloadManager()
            if let manager = downloadManager {
                modelDownloaded = await manager.isModelDownloaded(.bgeSmall)
                if modelDownloaded {
                    modelName = "bge-small"
                    status = "Model already downloaded"
                    currentStep = 2
                }
            }
        }
    }
    
    func downloadModel() {
        guard let manager = downloadManager else { return }
        
        Task {
            isDownloading = true
            status = "Downloading model..."
            
            do {
                let path = try await manager.downloadModel(.bgeSmall) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress.percentage
                        if progress.isComplete {
                            self?.modelDownloaded = true
                            self?.isDownloading = false
                            self?.modelName = "bge-small"
                            self?.status = "Model downloaded successfully"
                            self?.currentStep = 2
                        }
                    }
                }
                print("Model downloaded to: \(path.path)")
            } catch {
                status = "Download failed: \(error.localizedDescription)"
                isDownloading = false
            }
        }
    }
    
    func loadRileyJSON() {
        Task {
            status = "Loading JSON..."
            
            // Try to load from bundle
            if let bundleURL = Bundle.main.url(forResource: "riley_brooks_context", withExtension: "json") {
                do {
                    let data = try Data(contentsOf: bundleURL)
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    await parseJSON(json)
                    return
                } catch {
                    print("Failed to load from bundle: \(error)")
                }
            }
            
            // Fallback: Use sample data for testing
            print("Using sample data for testing")
            entries = [
                "I just discovered how important continuous learning is. I am taking an NeuroTech Agent Developer course right now.",
                "Great day. Worked hard and was working on LifePath even during work hours since it's agentic now.",
                "I came into this conversation wrestling with a strategic dilemma for my LifePath project.",
                "It's crazy to think about the circle. You're going to surround yourself with in your future yourself.",
                "I am not wasting any time not working on LifePath anymore. It's too important.",
                "Very happy with how yesterday went. It was a busy day at work with everything leading up to our Brightwell Capital innovation day.",
                "I'm learning agentic (the hot topic nowadays) and I'm happy with this.",
                "The key to making this decision lies in understanding my users' priorities.",
                "I have some early validation with daily active users—albeit just two—but that's a huge step for me.",
                "I want to build something that delivers exceptional user experience."
            ]
            
            entryCount = entries.count
            jsonLoaded = true
            status = "Loaded \(entryCount) sample entries"
            currentStep = 3
        }
    }
    
    func parseJSON(_ json: [String: Any]?) async {
        do {
            var allEntries: [String] = []
                
                // Extract journal entries
                if let dayEntries = json?["dayEntries"] as? [[String: Any]] {
                    for day in dayEntries {
                        if let daily = day["daily"] as? [String: Any],
                           let journals = daily["journalEntries"] as? [[String: Any]] {
                            for journal in journals {
                                if let text = journal["text"] as? String {
                                    allEntries.append(text)
                                }
                            }
                        }
                        
                        // Extract coach session summaries
                        if let daily = day["daily"] as? [String: Any],
                           let sessions = daily["coachSession"] as? [[String: Any]] {
                            for session in sessions {
                                if let summary = session["summary"] as? String {
                                    allEntries.append(summary)
                                }
                            }
                        }
                    }
                }
                
            entries = allEntries
            entryCount = allEntries.count
            jsonLoaded = true
            status = "Loaded \(entryCount) entries from file"
            currentStep = 3
            
        } catch {
            status = "Failed to parse JSON: \(error.localizedDescription)"
        }
    }
    
    func generateEmbeddings() {
        Task {
            status = "Using NLEmbedding (Apple's built-in embedder)..."
            isEmbedding = true
            
            do {
                print("🔄 Creating NLEmbedding embedder...")
                embedder = NLEmbedder()
                print("✅ NLEmbedder created (512 dimensions)")
                
                // Generate embeddings
                status = "Generating embeddings..."
                print("🔄 Starting embedding generation for \(entries.count) entries")
                var totalTime: TimeInterval = 0
                
                for (index, entry) in entries.enumerated() {
                    embeddingProgress = index + 1
                    print("📝 Embedding \(index + 1)/\(entries.count): \(entry.prefix(50))...")
                    
                    do {
                        let start = Date()
                        print("⏱️ Calling embedder.embed()...")
                        let embedding = try await embedder!.embed(entry)
                        let time = Date().timeIntervalSince(start)
                        totalTime += time
                        print("✅ Embedding \(index + 1) completed in \(Int(time * 1000))ms, dims: \(embedding.count)")
                        
                        embeddings.append(embedding)
                    } catch {
                        print("❌ Failed to embed entry \(index + 1): \(error)")
                        // Continue with next entry instead of stopping
                        continue
                    }
                }
                
                embeddingCount = embeddings.count
                avgEmbeddingTime = Int((totalTime / Double(embeddingCount)) * 1000)
                embeddingsGenerated = true
                isEmbedding = false
                status = "✅ Generated \(embeddingCount) embeddings"
                currentStep = 4
                
            } catch {
                print("❌ Fatal error in generateEmbeddings: \(error)")
                status = "Failed: \(error.localizedDescription)"
                isEmbedding = false
                embedder = nil
            }
        }
    }
    
    func testRetrieval() {
        guard let embedder = embedder else { return }
        
        Task {
            isTesting = true
            status = "Searching..."
            
            do {
                // Embed query
                let queryEmbedding = try await embedder.embed(testQuery)
                
                // Find top 3 most similar
                var similarities: [(index: Int, score: Float)] = []
                for (index, embedding) in embeddings.enumerated() {
                    let score = cosineSimilarity(queryEmbedding, embedding)
                    similarities.append((index, score))
                }
                
                similarities.sort { $0.score > $1.score }
                let top3 = similarities.prefix(3)
                
                retrievedEntries = top3.map { entries[$0.index] }
                
                // Call Groq with context
                let context = retrievedEntries.joined(separator: "\n\n")
                status = "Asking Groq..."
                
                let groqKey = "" // Add your Groq API key here
                let groqEmbedder = GroqEmbedder(apiKey: groqKey)
                
                let response = try await groqEmbedder.generateResponse(
                    prompt: testQuery,
                    context: context
                )
                
                groqResponse = response
                status = "✅ Test complete"
                isTesting = false
                
            } catch {
                status = "Test failed: \(error.localizedDescription)"
                isTesting = false
            }
        }
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0
        
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        
        return dot / (sqrt(magA) * sqrt(magB))
    }
}

#Preview {
    FullEmbeddingTestView()
}
