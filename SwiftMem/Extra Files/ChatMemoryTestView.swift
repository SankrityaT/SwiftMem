//
//  ChatMemoryTestView.swift
//  SwiftMem - Live Chat Memory Test
//
//  Tests real-time memory creation and retrieval during conversation
//

import SwiftUI

struct ChatMemoryTestView: View {
    // 🔑 PASTE YOUR GROQ API KEY HERE
    private let groqAPIKey = "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"
    
    // SwiftMem components
        @State private var graphStore: GraphStore?
        @State private var vectorStore: VectorStore?
        @State private var embeddingEngine: EmbeddingEngine?
        @State private var retrieval: RetrievalEngine?
        
        // Chat state
        @State private var messages: [ChatMessage] = []
        @State private var inputText = ""
        @State private var isProcessing = false
        @State private var memoryCount = 0
        @State private var lastRetrievedMemories: [String] = []
        
        // Debug
        @State private var showMemoryTimeline = false
        @State private var allMemories: [Node] = []
        
        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    // Header with memory count
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Live Memory Chat")
                                .font(.headline)
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    Image(systemName: "brain.head.profile")
                                        .foregroundColor(.purple)
                                    Text("\(memoryCount) memories")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if graphStore == nil {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.circle")
                                            .foregroundColor(.orange)
                                        Text("Not initialized")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Ready")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            Task {
                                // Refresh memories before showing timeline
                                if let graphStore = graphStore {
                                    allMemories = try await graphStore.getNodes(limit: 100)
                                    memoryCount = try await graphStore.getNodeCount()
                                }
                                showMemoryTimeline.toggle()
                            }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    
                    // Chat messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(messages) { message in
                                    ChatBubbleView(message: message)
                                        .id(message.id)
                                }
                                
                                if isProcessing {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Thinking...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let lastMessage = messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // Input bar
                    VStack(spacing: 8) {
                        if !lastRetrievedMemories.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                                Text("Retrieved \(lastRetrievedMemories.count) memories")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        HStack(spacing: 12) {
                            TextField("Message...", text: $inputText, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...4)
                                .disabled(isProcessing || graphStore == nil)
                            
                            Button {
                                sendMessage()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(inputText.isEmpty || isProcessing ? .gray : .blue)
                            }
                            .disabled(inputText.isEmpty || isProcessing || graphStore == nil)
                        }
                        .padding()
                    }
                    .background(Color.secondary.opacity(0.05))
                }
                .navigationTitle("Chat Memory Test")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                initializeMemorySystem()
                            } label: {
                                Label("Reset Chat DB", systemImage: "arrow.clockwise")
                            }
                            
                            Button(role: .destructive) {
                                wipeAllDatabases()
                            } label: {
                                Label("Wipe ALL Databases", systemImage: "trash.fill")
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Reset")
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            clearChat()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(messages.isEmpty)
                    }
                }
                .sheet(isPresented: $showMemoryTimeline) {
                    MemoryTimelineView(memories: allMemories)
                }
                .task {
                    if graphStore == nil {
                        await initializeMemorySystem()
                    }
                }
            }
        }
        
        // MARK: - Memory System
        
        func initializeMemorySystem() {
            Task {
                do {
                    messages = []
                    memoryCount = 0
                    allMemories = []
                    
                    let config = SwiftMemConfig.default
                    
                    // Clear old database
                    let dbURL = try config.storageLocation.url(filename: "swiftmem_chat.db")
                    try? FileManager.default.removeItem(at: dbURL)
                    
                    // Create components
                    graphStore = try await GraphStore.create(config: config)
                    vectorStore = VectorStore(config: config)
                    let embedder = GroqEmbedder(apiKey: groqAPIKey)
                    embeddingEngine = EmbeddingEngine(embedder: embedder, config: config)
                    
                    retrieval = RetrievalEngine(
                        graphStore: graphStore!,
                        vectorStore: vectorStore!,
                        embeddingEngine: embeddingEngine!,
                        config: config
                    )
                    
                    // Add welcome message
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: "Hey! I'm your AI assistant with memory. Tell me about yourself, your projects, or anything - I'll remember our conversation!",
                        isMemoryCreated: false
                    ))
                    
                } catch {
                    print("Failed to initialize: \(error)")
                }
            }
        }
        
        func clearChat() {
            messages = []
            lastRetrievedMemories = []
        }
        
        func wipeAllDatabases() {
            Task {
                do {
                    let config = SwiftMemConfig.default
                    
                    // Clear ALL database files
                    let dbFiles = ["swiftmem_chat.db", "swiftmem_riley.db", "swiftmem_graph.db"]
                    
                    for filename in dbFiles {
                        let dbURL = try config.storageLocation.url(filename: filename)
                        try? FileManager.default.removeItem(at: dbURL)
                        try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("shm"))
                        try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("wal"))
                    }
                    
                    // Reinitialize
                    await initializeMemorySystem()
                    
                } catch {
                    print("Failed to wipe databases: \(error)")
                }
            }
        }
        
        // MARK: - Chat Logic
        
        func sendMessage() {
            guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            
            let userMessage = inputText
            inputText = ""
            
            // Add user message to chat
            messages.append(ChatMessage(
                role: .user,
                content: userMessage,
                isMemoryCreated: false
            ))
            
            Task {
                isProcessing = true
                lastRetrievedMemories = []
                
                do {
                    // STEP 1: Store user message as memory
                    try await storeUserMessage(userMessage)
                    
                    // STEP 2: Retrieve relevant memories
                    let relevantMemories = try await retrieveMemories(for: userMessage)
                    
                    // STEP 3: Generate AI response with context
                    let aiResponse = try await generateAIResponse(
                        userMessage: userMessage,
                        context: relevantMemories
                    )
                    
                    // STEP 4: Add AI response to chat
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: aiResponse,
                        isMemoryCreated: false,
                        retrievedMemoryCount: relevantMemories.count
                    ))
                    
                    // STEP 5: Store AI response as memory (optional but good for context)
                    try await storeAIResponse(aiResponse)
                    
                    // Update memory count
                    memoryCount = try await graphStore!.getNodeCount()
                    allMemories = try await graphStore!.getNodes(limit: 100)
                    
                } catch {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: "Sorry, I encountered an error: \(error.localizedDescription)",
                        isMemoryCreated: false
                    ))
                }
                
                isProcessing = false
            }
        }
        
        // MARK: - Memory Operations
        
        func storeUserMessage(_ message: String) async throws {
            guard let graphStore = graphStore,
                  let vectorStore = vectorStore,
                  let embeddingEngine = embeddingEngine else {
                throw SwiftMemError.storageError("Memory system not initialized")
            }
            
            // Create memory node
            let node = Node(
                content: message,
                type: .episodic,
                metadata: [
                    "role": .string("user"),
                    "timestamp": .string(ISO8601DateFormatter().string(from: Date()))
                ]
            )
            
            // Store node
            try await graphStore.storeNodes([node])
            
            // Generate and store embedding
            let embedding = try await embeddingEngine.embed(message)
            try await vectorStore.addVector(embedding, for: node.id)
            
            // Mark message as having memory created
            if let index = messages.firstIndex(where: { $0.content == message && $0.role == .user }) {
                messages[index].isMemoryCreated = true
            }
        }
        
        func storeAIResponse(_ response: String) async throws {
            guard let graphStore = graphStore,
                  let vectorStore = vectorStore,
                  let embeddingEngine = embeddingEngine else {
                return
            }
            
            // Only store substantive responses (not errors or short replies)
            guard response.count > 50 else { return }
            
            let node = Node(
                content: response,
                type: .semantic,
                metadata: [
                    "role": .string("assistant"),
                    "timestamp": .string(ISO8601DateFormatter().string(from: Date()))
                ]
            )
            
            try await graphStore.storeNodes([node])
            let embedding = try await embeddingEngine.embed(response)
            try await vectorStore.addVector(embedding, for: node.id)
        }
        
        func retrieveMemories(for query: String) async throws -> [Node] {
            guard let retrieval = retrieval else {
                return []
            }
            
            // Retrieve relevant memories
            let result = try await retrieval.query(
                query,
                maxResults: 5,
                strategy: .graph  // Use graph for now since embeddings are simple
            )
            
            // Store for display
            lastRetrievedMemories = result.nodes.map { String($0.node.content.prefix(60)) + "..." }
            
            return result.nodes.map { $0.node }
        }
        
        func generateAIResponse(userMessage: String, context: [Node]) async throws -> String {
            guard let embeddingEngine = embeddingEngine,
                  let embedder = await embeddingEngine.underlyingEmbedder as? GroqEmbedder else {
                throw SwiftMemError.embeddingError("Groq embedder not available")
            }
            
            // Format context from memories
            let formattedContext = context.isEmpty ? "No previous context available." : """
            Here's what I remember from our conversation:
            
            \(context.enumerated().map { "\($0.offset + 1). \($0.element.content)" }.joined(separator: "\n"))
            """
            
            // Call Groq AI
            let response = try await embedder.generateResponse(
                prompt: userMessage,
                context: formattedContext
            )
            
            return response
        }
    }

    // MARK: - Supporting Types

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: ChatRole
        let content: String
        var isMemoryCreated: Bool
        var retrievedMemoryCount: Int = 0
    }

    enum ChatRole {
        case user
        case assistant
    }

    // MARK: - Chat Bubble View

    struct ChatBubbleView: View {
        let message: ChatMessage
        
        var body: some View {
            HStack {
                if message.role == .user {
                    Spacer()
                }
                
                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                    Text(message.content)
                        .padding(12)
                        .background(message.role == .user ? Color.blue : Color.secondary.opacity(0.2))
                        .foregroundColor(message.role == .user ? .white : .primary)
                        .cornerRadius(16)
                    
                    HStack(spacing: 8) {
                        if message.isMemoryCreated {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("Stored")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if message.retrievedMemoryCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundColor(.purple)
                                Text("\(message.retrievedMemoryCount) memories")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
                
                if message.role == .assistant {
                    Spacer()
                }
            }
        }
    }

    // MARK: - Memory Timeline View

    struct MemoryTimelineView: View {
        let memories: [Node]
        @Environment(\.dismiss) var dismiss
        
        var body: some View {
            NavigationStack {
                List {
                    ForEach(memories.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: iconForType(memories[index].type))
                                    .foregroundColor(colorForType(memories[index].type))
                                Text(memories[index].type.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(timeAgo(memories[index].createdAt))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(memories[index].content)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle("Memory Timeline (\(memories.count))")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        
        func iconForType(_ type: MemoryType) -> String {
            switch type {
            case .episodic: return "bubble.left"
            case .semantic: return "brain"
            case .procedural: return "list.bullet"
            case .emotional: return "heart"
            case .goal: return "target"
            case .conversation: return "message"
            case .general: return "doc.text"
            }
        }
        
        func colorForType(_ type: MemoryType) -> Color {
            switch type {
            case .episodic: return .blue
            case .semantic: return .purple
            case .procedural: return .green
            case .emotional: return .pink
            case .goal: return .orange
            case .conversation: return .cyan
            case .general: return .gray
            }
        }
        
        func timeAgo(_ date: Date) -> String {
            let seconds = Date().timeIntervalSince(date)
            
            if seconds < 60 {
                return "just now"
            } else if seconds < 3600 {
                let mins = Int(seconds / 60)
                return "\(mins)m ago"
            } else if seconds < 86400 {
                let hours = Int(seconds / 3600)
                return "\(hours)h ago"
            } else {
                let days = Int(seconds / 86400)
                return "\(days)d ago"
            }
        }
    }

    #Preview {
        ChatMemoryTestView()
    }






    
