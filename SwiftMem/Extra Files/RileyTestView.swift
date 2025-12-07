//
//  RileyTestView.swift
//  SwiftMem - Riley Brooks Data Test (FIXED)
//

import SwiftUI

struct RileyTestView: View {
    // 🔑 PASTE YOUR GROQ API KEY HERE
    private let groqAPIKey = ""
    
    // Store components to reuse across tests
    @State private var graphStore: GraphStore?
    @State private var vectorStore: VectorStore?
    @State private var embeddingEngine: EmbeddingEngine?
    @State private var retrieval: RetrievalEngine?
    
    @State private var testResults: [String] = []
    @State private var testQuery = "What are my goals and what am I working on?"
    @State private var aiResponse = ""
    @State private var isLoading = false
    @State private var memoryCount = 0
    
    // Context viewing
    @State private var lastContext = ""
    @State private var showContext = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SwiftMem Integration Test")
                            .font(.largeTitle)
                            .bold()
                        Text("Testing with Riley Brooks journal data")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if memoryCount > 0 {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("\(memoryCount) memories loaded")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    // Test Buttons
                    VStack(spacing: 12) {
                        
                        Button("🔍 Search for 'Casey' in DB") {
                            Task {
                                if let graphStore = graphStore {
                                    // Get ALL nodes
                                    let allNodes = try await graphStore.getNodes(limit: 700)
                                    
                                    // Filter for Casey
                                    let caseyNodes = allNodes.filter {
                                        $0.content.lowercased().contains("casey")
                                    }
                                    
                                    testResults.append("📊 Found \(caseyNodes.count) nodes mentioning Casey")
                                    for node in caseyNodes.prefix(3) {
                                        testResults.append("   - \(String(node.content.prefix(100)))")
                                    }
                                }
                            }
                        }
                        Button {
                            loadRileyData()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text("1. Load Riley's Journal Data")
                                Spacer()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isLoading)
                        
                        Button {
                            testRetrieval()
                        } label: {
                            HStack {
                                Image(systemName: "sparkle.magnifyingglass")
                                Text("2. Test Semantic Search")
                                Spacer()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(graphStore == nil ? Color.gray : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isLoading || graphStore == nil)
                        
                        Button {
                            testAIWithContext()
                        } label: {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                Text("3. Ask Groq AI with Context")
                                Spacer()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(retrieval == nil ? Color.gray : Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isLoading || retrieval == nil)
                        
                        Divider()
                        
                        Button {
                            runFullTest()
                        } label: {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("▶ Run Complete Test Suite")
                                Spacer()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isLoading)
                        
                        // Debug button
                        Button {
                            debugStorage()
                        } label: {
                            HStack {
                                Image(systemName: "ladybug")
                                Text("🔍 Debug Storage")
                                Spacer()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.secondary.opacity(0.3))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                        .disabled(graphStore == nil)
                    }
                    
                    // Query Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ask Riley's AI")
                            .font(.headline)
                        TextField("Ask about goals, habits, relationships...", text: $testQuery)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)
                    
                    // AI Response
                    if !aiResponse.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.purple)
                                Text("AI Response")
                                    .font(.headline)
                            }
                            
                            Text(aiResponse)
                                .padding()
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Context Viewer
                    if !lastContext.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                showContext.toggle()
                            } label: {
                                HStack {
                                    Image(systemName: showContext ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Retrieved Context")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(lastContext.count) chars")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            
                            if showContext {
                                ScrollView {
                                    Text(lastContext)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 300)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(12)
                    }
                    
                    // Test Results
                    if !testResults.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Test Results")
                                .font(.headline)
                            
                            ForEach(testResults.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 8) {
                                    if testResults[index].hasPrefix("✅") {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    } else if testResults[index].hasPrefix("❌") {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    } else if testResults[index].hasPrefix("📊") {
                                        Image(systemName: "chart.bar.fill")
                                            .foregroundColor(.blue)
                                    } else if testResults[index].hasPrefix("🔍") {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(.orange)
                                    } else {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(testResults[index])
                                        .font(.system(.body, design: .monospaced))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(12)
                    }
                    
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Processing...")
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("SwiftMem Test")
        }
    }
    
    // MARK: - Test Functions
    
    func loadRileyData() {
        Task {
            isLoading = true
            testResults = []
            memoryCount = 0
            
            do {
                testResults.append("Loading Riley Brooks journal data...")
                
                // Load Riley's JSON
                guard let url = Bundle.main.url(forResource: "riley_brooks_context", withExtension: "json"),
                      let data = try? Data(contentsOf: url) else {
                    throw SwiftMemError.storageError("Failed to load riley_brooks_context.json - make sure it's in your bundle!")
                }
                
                testResults.append("✅ Found riley_brooks_context.json")
                
                // Parse to nodes
                let nodes = try RileyBrooksParser.parseToNodes(from: data)
                memoryCount = nodes.count
                testResults.append("✅ Parsed \(nodes.count) memories from journal")
                
                // Stats breakdown
                let journalCount = nodes.filter { $0.type == .episodic }.count
                let coachingCount = nodes.filter { $0.type == .semantic && $0.metadata["source"] == .string("coaching") }.count
                let emotionalCount = nodes.filter { $0.type == .emotional }.count
                
                testResults.append("   📊 \(journalCount) journal entries")
                testResults.append("   📊 \(coachingCount) coaching sessions")
                testResults.append("   📊 \(emotionalCount) mood/performance logs")
                
                // Setup SwiftMem (REUSE THESE!)
                let config = SwiftMemConfig.default
                
                // Clear old database
                let dbURL = try config.storageLocation.url(filename: "swiftmem_graph.db")
                try? FileManager.default.removeItem(at: dbURL)
                try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("wal"))
                try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("shm"))
                
                // Create components and STORE them
                self.graphStore = try await GraphStore.create(config: config)
                self.vectorStore = VectorStore(config: config)
                let embedder = GroqEmbedder(apiKey: groqAPIKey)
                self.embeddingEngine = EmbeddingEngine(embedder: embedder, config: config)
                
                testResults.append("✅ Initialized SwiftMem components")
                
                // Store nodes
                try await graphStore!.storeNodes(nodes)
                testResults.append("✅ Stored all memories in GraphStore")
                
                // Generate embeddings
                testResults.append("Generating semantic embeddings...")
                let startTime = Date()
                
                for (index, node) in nodes.enumerated() {
                    let embedding = try await embeddingEngine!.embed(node.content)
                    try await vectorStore!.addVector(embedding, for: node.id)
                    
                    if (index + 1) % 50 == 0 {
                        testResults.append("   Progress: \(index + 1)/\(nodes.count)...")
                    }
                }
                
                let duration = Date().timeIntervalSince(startTime)
                testResults.append("✅ Generated \(nodes.count) embeddings")
                testResults.append("📊 Time: \(String(format: "%.1f", duration))s (\(String(format: "%.0f", (duration / Double(nodes.count)) * 1000))ms/embedding)")
                
                // Create retrieval engine
                self.retrieval = RetrievalEngine(
                    graphStore: graphStore!,
                    vectorStore: vectorStore!,
                    embeddingEngine: embeddingEngine!,
                    config: config
                )
                
                testResults.append("\n🎉 Riley's memories loaded and ready!")
                
            } catch {
                testResults.append("❌ Error: \(error.localizedDescription)")
            }
            
            isLoading = false
        }
    }
    
    func testRetrieval() {
        Task {
            isLoading = true
            
            do {
                guard let retrieval = retrieval else {
                    testResults.append("❌ Load data first!")
                    isLoading = false
                    return
                }
                
                testResults.append("\n🔍 Testing semantic retrieval...")
                
                // Test query using STORED retrieval engine
                let startTime = Date()
                let result = try await retrieval.query(
                    testQuery,
                    maxResults: 5,
                    strategy: .hybrid
                )
                let duration = Date().timeIntervalSince(startTime)
                
                testResults.append("✅ Retrieved \(result.nodes.count) relevant memories")
                testResults.append("📊 Query time: \(String(format: "%.0f", duration * 1000))ms")
                testResults.append("📊 Context size: \(result.formattedContext.count) chars")
                
                if result.nodes.isEmpty {
                    testResults.append("⚠️ No results - trying graph-only strategy...")
                    
                    // Try graph-only as fallback
                    let graphResult = try await retrieval.query(
                        testQuery,
                        maxResults: 5,
                        strategy: .graph
                    )
                    
                    testResults.append("📊 Graph-only found: \(graphResult.nodes.count) results")
                    
                    if !graphResult.nodes.isEmpty {
                        testResults.append("\n🔍 Top results (graph):")
                        for (index, scoredNode) in graphResult.nodes.prefix(5).enumerated() {
                            let preview = String(scoredNode.node.content.prefix(80))
                            let score = String(format: "%.3f", scoredNode.score)
                            testResults.append("   \(index + 1). [\(score)] \(preview)...")
                        }
                    }
                } else {
                    testResults.append("\n🔍 Top results:")
                    for (index, scoredNode) in result.nodes.prefix(5).enumerated() {
                        let preview = String(scoredNode.node.content.prefix(80))
                        let score = String(format: "%.3f", scoredNode.score)
                        testResults.append("   \(index + 1). [\(score)] \(preview)...")
                    }
                }
                
            } catch {
                testResults.append("❌ Retrieval error: \(error.localizedDescription)")
            }
            
            isLoading = false
        }
    }
    
    func testAIWithContext() {
        Task {
            isLoading = true
            aiResponse = ""
            
            do {
                guard let retrieval = retrieval,
                      let embeddingEngine = embeddingEngine else {
                    testResults.append("❌ Load data first!")
                    isLoading = false
                    return
                }
                
                testResults.append("\n🤖 Calling Groq AI with context...")
                
                // Retrieve context
                var result = try await retrieval.query(
                    testQuery,
                    maxResults: 20,
                    strategy: .hybrid  // Use graph for testing since embeddings might not match
                )
                
                if result.nodes.isEmpty {
                    let graphResult = try await retrieval.query(
                        testQuery,
                        maxResults: 20,
                        strategy: .graph
                    )
                    testResults.append("⚠️ Hybrid retrieval found 0 memories, using graph-only fallback (\(graphResult.nodes.count) results)")
                    result = graphResult
                }
                
                // Store context for viewing
                lastContext = result.formattedContext
                
                testResults.append("✅ Retrieved \(result.nodes.count) memories as context")
                
                // Call Groq
                guard let embedder = await embeddingEngine.underlyingEmbedder as? GroqEmbedder else {
                    throw SwiftMemError.embeddingError("Wrong embedder type")
                }
                
                let aiStartTime = Date()
                let response = try await embedder.generateResponse(
                    prompt: testQuery,
                    context: result.formattedContext
                )
                let aiDuration = Date().timeIntervalSince(aiStartTime)
                
                aiResponse = response
                
                testResults.append("✅ AI response generated")
                testResults.append("📊 AI latency: \(String(format: "%.2f", aiDuration))s")
                testResults.append("📊 Response length: \(response.count) chars")
                
            } catch {
                testResults.append("❌ AI error: \(error.localizedDescription)")
                if error.localizedDescription.contains("401") {
                    testResults.append("   Check your Groq API key!")
                }
            }
            
            isLoading = false
        }
    }
    
    func debugStorage() {
        Task {
            do {
                guard let graphStore = graphStore,
                      let vectorStore = vectorStore else {
                    testResults.append("❌ No storage initialized!")
                    return
                }
                
                testResults.append("\n🔍 Storage Debug:")
                
                let nodeCount = try await graphStore.getNodeCount()
                let vectorCount = await vectorStore.getVectorCount()
                
                testResults.append("📊 Nodes in GraphStore: \(nodeCount)")
                testResults.append("📊 Vectors in VectorStore: \(vectorCount)")
                
                // Get sample nodes
                let nodes = try await graphStore.getNodes(limit: 3)
                testResults.append("📊 Sample nodes:")
                for (index, node) in nodes.enumerated() {
                    let preview = String(node.content.prefix(60))
                    testResults.append("   \(index + 1). \(preview)...")
                }
                
            } catch {
                testResults.append("❌ Debug error: \(error.localizedDescription)")
            }
        }
    }
    
    func runFullTest() {
        Task {
            await loadRileyData()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await testRetrieval()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await testAIWithContext()
        }
    }
}

#Preview {
    RileyTestView()
}
