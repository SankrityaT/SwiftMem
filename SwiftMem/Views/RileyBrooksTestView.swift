//
//  RileyBrooksTestView.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import SwiftUI
import Combine

struct RileyBrooksTestView: View {
    @StateObject private var viewModel = RileyTestViewModel()
    @State private var customQuestion: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Riley Brooks Memory Test")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Test SwiftMem with real user data + Groq AI")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Load Data Button
                if !viewModel.isDataLoaded && !viewModel.isRunning {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Step 1: Load Riley's Data")
                            .font(.headline)
                        
                        Button(action: {
                            Task {
                                await viewModel.loadRileyData()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.doc.fill")
                                Text("Load Riley's Context")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                    .padding(.horizontal)
                }
                
                // Status message
                if !viewModel.currentStatus.isEmpty && !viewModel.isRunning {
                    Text(viewModel.currentStatus)
                        .font(.headline)
                        .foregroundColor(viewModel.currentStatus.contains("✅") ? .green : .secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                // Ask Questions Interface
                if viewModel.isDataLoaded && !viewModel.isRunning {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Step 2: Ask Questions")
                            .font(.headline)
                        
                        HStack {
                            TextField("Ask about Riley...", text: $customQuestion)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(action: {
                                Task {
                                    await viewModel.askQuestion(customQuestion)
                                    customQuestion = ""
                                }
                            }) {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                            .disabled(customQuestion.isEmpty)
                        }
                        
                        // Quick Questions
                        Text("Quick Questions:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.quickQuestions, id: \.self) { question in
                                    Button(action: {
                                        Task {
                                            await viewModel.askQuestion(question)
                                        }
                                    }) {
                                        Text(question)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .cornerRadius(16)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                    .padding(.horizontal)
                }
                
                // Progress
                if viewModel.isRunning {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text(viewModel.currentStatus)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                }
                
                // Stats - show after data is loaded
                if viewModel.isDataLoaded, let stats = viewModel.stats {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Memory Statistics")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 16) {
                            StatCard(
                                title: "Memories",
                                value: "\(stats.totalMemories)",
                                icon: "brain.head.profile",
                                color: .blue
                            )
                            
                            StatCard(
                                title: "Sessions",
                                value: "\(stats.totalSessions)",
                                icon: "link",
                                color: .green
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                    .padding(.horizontal)
                }
                
                // Q&A Results
                if !viewModel.qaResults.isEmpty {
                    
                    // Q&A Results
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Questions & Answers")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        ForEach(viewModel.qaResults) { result in
                            QACard(result: result)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Riley Brooks Test")
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Q&A Card

struct QACard: View {
    let result: QAResult
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.blue)
                Text(result.question)
                    .font(.headline)
                Spacer()
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            
            // Answer
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text(result.answer)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            
            // Retrieved Context (expandable)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Retrieved Memories (\(result.retrievedMemories.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(result.retrievedMemories.enumerated()), id: \.offset) { index, memory in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(memory.content)
                                    .font(.caption)
                                    .lineLimit(3)
                                
                                Text("Score: \(memory.score, specifier: "%.2f")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
}

// MARK: - View Model

class RileyTestViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var isDataLoaded = false
    @Published var currentStatus = ""
    @Published var qaResults: [QAResult] = []
    @Published var stats: MemoryStats?
    
    private let groqAPIKey = "" // Add your Groq API key here for testing
    private let swiftMemAPI = SwiftMemAPI.shared
    
    let quickQuestions = [
        "What is Riley working on?",
        "What course is Riley taking?",
        "What are Riley's goals?",
        "What does Riley think about agentic AI?",
        "What happened at work?",
        "[TAG: work] What are Riley's work challenges?",
        "[TAG: relationships] How is Riley's relationship?",
        "[TAG: July] What happened in July?"
    ]
    
    func loadRileyData() async {
        print("🚀 [RileyTest] Starting data load...")
        
        await MainActor.run {
            isRunning = true
            currentStatus = "Initializing SwiftMem..."
        }
        
        do {
            // Initialize SwiftMem
            print("⚙️ [RileyTest] Initializing SwiftMem...")
            try await swiftMemAPI.initialize()
            print("✅ [RileyTest] SwiftMem initialized")
            
            await MainActor.run {
                currentStatus = "Loading Riley's context..."
            }
            
            // Load Riley's data from Bundle or use sample data
            let context: RileyBrooksContext
            if let contextURL = Bundle.main.url(forResource: "riley_brooks_context", withExtension: "json") {
                let data = try Data(contentsOf: contextURL)
                context = try JSONDecoder().decode(RileyBrooksContext.self, from: data)
            } else {
                // Use sample data if file not in bundle
                context = RileyBrooksContext(dayEntries: [
                    RileyDayEntry(date: "2025-07-18", daily: RileyDailyData(
                        journalEntries: [
                            RileyJournalEntry(text: "I just discovered how important continuous learning is. I am taking a NeuroTech Agent Developer course right now. Not only am I noticing huge benefits in my job and current project that use this but most importantly also help me think that way to see what we can do. It's a game changer.", tags: []),
                            RileyJournalEntry(text: "Great day. Worked hard and was working on LifePath even during work hours since it's agentic now (a skill I am preparing for at work)", tags: [])
                        ],
                        coachSession: nil
                    )),
                    RileyDayEntry(date: "2025-07-19", daily: RileyDailyData(
                        journalEntries: [
                            RileyJournalEntry(text: "I am not wasting any time not working on LifePath anymore. It's too important.", tags: []),
                            RileyJournalEntry(text: "Very happy with how yesterday went. It was a busy day at work with everything leading up to our Brightwell Capital innovation day. It was a huge success that lead to backing from our boss boss to build an agentic marketplace application.", tags: [])
                        ],
                        coachSession: nil
                    ))
                ])
            }
            
            await MainActor.run {
                currentStatus = "Ingesting \(context.dayEntries.count) days of memories..."
            }
            
            // Ingest all entries
            var count = 0
            print("📥 [RileyTest] Starting ingestion of \(context.dayEntries.count) day entries...")
            
            for entry in context.dayEntries {
                // Extract month/year for date-based tags
                let dateComponents = entry.date.split(separator: "-")
                let year = dateComponents.count > 0 ? String(dateComponents[0]) : "unknown"
                let month = dateComponents.count > 1 ? String(dateComponents[1]) : "unknown"
                let monthName = getMonthName(month)
                
                for journal in entry.daily.journalEntries {
                    print("  📝 Adding journal: \(String(journal.text.prefix(50)))...")
                    
                    // Auto-detect topics from content
                    var tags = [
                        "session:\(entry.date)",
                        "date:\(year)-\(month)",
                        "month:\(monthName)",
                        "type:journal"
                    ]
                    
                    // Add topic tags based on content
                    let contentLower = journal.text.lowercased()
                    if contentLower.contains("work") || contentLower.contains("job") || contentLower.contains("boss") {
                        tags.append("topic:work")
                    }
                    if contentLower.contains("casey") || contentLower.contains("relationship") {
                        tags.append("topic:relationships")
                    }
                    if contentLower.contains("lifepath") || contentLower.contains("project") {
                        tags.append("topic:projects")
                    }
                    if contentLower.contains("weed") || contentLower.contains("high") || contentLower.contains("smoke") {
                        tags.append("topic:substance_use")
                    }
                    if contentLower.contains("stress") || contentLower.contains("anxiety") || contentLower.contains("frustrated") {
                        tags.append("topic:mental_health")
                    }
                    
                    try await swiftMemAPI.add(
                        content: journal.text,
                        userId: "riley_brooks",
                        metadata: ["date": entry.date, "type": "journal"],
                        containerTags: tags
                    )
                    count += 1
                }
                
                if let sessions = entry.daily.coachSession {
                    for session in sessions {
                        print("  💬 Adding coach session: \(String(session.summary.prefix(50)))...")
                        
                        var tags = [
                            "session:\(entry.date)",
                            "date:\(year)-\(month)",
                            "month:\(monthName)",
                            "type:coach_session"
                        ]
                        
                        // Add topic tags for coach sessions
                        let summaryLower = session.summary.lowercased()
                        if summaryLower.contains("work") || summaryLower.contains("career") {
                            tags.append("topic:work")
                        }
                        if summaryLower.contains("relationship") || summaryLower.contains("casey") {
                            tags.append("topic:relationships")
                        }
                        if summaryLower.contains("goal") || summaryLower.contains("vision") {
                            tags.append("topic:goals")
                        }
                        
                        try await swiftMemAPI.add(
                            content: session.summary,
                            userId: "riley_brooks",
                            metadata: ["date": entry.date, "type": "coach_session"],
                            containerTags: tags
                        )
                        count += 1
                    }
                }
            }
            
            print("✅ [RileyTest] Ingested \(count) total memories")
            
            await MainActor.run {
                stats = MemoryStats(totalMemories: count, totalSessions: context.dayEntries.count, storageSize: 0)
                isDataLoaded = true
                isRunning = false
                currentStatus = "✅ Loaded \(count) memories!"
            }
            
        } catch {
            await MainActor.run {
                currentStatus = "❌ Error: \(error.localizedDescription)"
                isRunning = false
            }
        }
    }
    
    func askQuestion(_ question: String) async {
        print("🔍 [RileyTest] Starting question: \(question)")
        
        await MainActor.run {
            isRunning = true
            currentStatus = "Searching memories..."
        }
        
        do {
            // Check if question has tag filter
            var containerTags: [String] = []
            var cleanQuestion = question
            
            if question.contains("[TAG:") {
                // Extract tag from question like "[TAG: work] What are Riley's work challenges?"
                if let tagStart = question.range(of: "[TAG:"),
                   let tagEnd = question.range(of: "]", range: tagStart.upperBound..<question.endIndex) {
                    let tagValue = question[tagStart.upperBound..<tagEnd.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
                    
                    // Map tag to actual container tags
                    if tagValue == "work" {
                        containerTags = ["topic:work"]
                    } else if tagValue == "relationships" {
                        containerTags = ["topic:relationships"]
                    } else if tagValue == "july" {
                        containerTags = ["month:July"]
                    } else if tagValue == "substance" {
                        containerTags = ["topic:substance_use"]
                    }
                    
                    // Remove tag from question
                    cleanQuestion = String(question[tagEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
            
            // Search for relevant memories
            print("🔍 [RileyTest] Searching SwiftMem for: \(cleanQuestion)")
            if !containerTags.isEmpty {
                print("🏷️ [RileyTest] Filtering by tags: \(containerTags)")
            }
            
            let results = try await swiftMemAPI.search(
                query: cleanQuestion,
                userId: "riley_brooks",
                limit: 5,
                containerTags: containerTags
            )
            
            print("📊 [RileyTest] Found \(results.count) memories:")
            for (i, result) in results.enumerated() {
                print("  \(i+1). Score: \(result.score) - \(String(result.content.prefix(100)))...")
            }
            
            await MainActor.run {
                currentStatus = "Generating answer with Groq..."
            }
            
            // Build context from retrieved memories
            let context = results.map { $0.content }.joined(separator: "\n\n")
            print("📝 [RileyTest] Context length: \(context.count) chars")
            print("📝 [RileyTest] Context preview: \(String(context.prefix(200)))...")
            
            // Call Groq API
            print("🤖 [RileyTest] Calling Groq API...")
            let answer = try await callGroqAPI(question: question, context: context)
            print("✅ [RileyTest] Got answer: \(answer)")
            
            // Add to results
            await MainActor.run {
                let qaResult = QAResult(
                    question: question,
                    answer: answer,
                    retrievedMemories: results.map { 
                        RetrievedMemory(content: $0.content, score: Double($0.score))
                    }
                )
                qaResults.insert(qaResult, at: 0) // Add to top
                isRunning = false
                currentStatus = ""
            }
            
        } catch {
            await MainActor.run {
                currentStatus = "❌ Error: \(error.localizedDescription)"
                isRunning = false
            }
        }
    }
    
    private func getMonthName(_ month: String) -> String {
        switch month {
        case "01": return "January"
        case "02": return "February"
        case "03": return "March"
        case "04": return "April"
        case "05": return "May"
        case "06": return "June"
        case "07": return "July"
        case "08": return "August"
        case "09": return "September"
        case "10": return "October"
        case "11": return "November"
        case "12": return "December"
        default: return "Unknown"
        }
    }
    
    private func callGroqAPI(question: String, context: String) async throws -> String {
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        The following are journal entries and memories from Riley Brooks, written in first person ("I", "my", etc.).
        These memories represent Riley's thoughts, experiences, and reflections.
        
        Answer the question based on Riley's memories below. Be specific and reference the actual content.
        
        Riley's Memories:
        \(context)
        
        Question: \(question)
        
        Answer:
        """
        
        let body: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 200
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GroqResponse.self, from: data)
        
        return response.choices.first?.message.content ?? "No answer"
    }
}

// MARK: - Models

struct QAResult: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
    let retrievedMemories: [RetrievedMemory]
}

struct RetrievedMemory: Identifiable {
    let id = UUID()
    let content: String
    let score: Double
}

#Preview {
    NavigationStack {
        RileyBrooksTestView()
    }
}
