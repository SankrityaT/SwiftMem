//
//  RileyBrooksTest.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//  Test SwiftMem with Riley Brooks context + Groq API
//

import Foundation

/// Test SwiftMem with real user data (Riley Brooks) and Groq API
public actor RileyBrooksTest {
    
    private let swiftMemAPI: SwiftMemAPI
    private let groqAPIKey: String
    
    public init(groqAPIKey: String) {
        self.swiftMemAPI = SwiftMemAPI.shared
        self.groqAPIKey = groqAPIKey
    }
    
    /// Run the full test: ingest Riley's data, ask questions, verify with Groq
    public func runTest() async throws {
        print("🧪 Riley Brooks SwiftMem Test")
        print(String(repeating: "=", count: 50))
        
        // 1. Initialize SwiftMem
        print("\n1️⃣ Initializing SwiftMem...")
        try await swiftMemAPI.initialize()
        print("✅ SwiftMem initialized")
        
        // 2. Load Riley's context
        print("\n2️⃣ Loading Riley Brooks context...")
        let contextURL = URL(fileURLWithPath: "/Users/sankritya/IosApp/SwiftMem/SwiftMem/SwiftMem/Extra Files/riley_brooks_context.json")
        let data = try Data(contentsOf: contextURL)
        let context = try JSONDecoder().decode(RileyBrooksContext.self, from: data)
        print("✅ Loaded \(context.dayEntries.count) day entries")
        
        // 3. Ingest into SwiftMem
        print("\n3️⃣ Ingesting memories...")
        var memoryCount = 0
        
        for entry in context.dayEntries {
            // Ingest journal entries
            for journal in entry.daily.journalEntries {
                try await swiftMemAPI.add(
                    content: journal.text,
                    userId: "riley_brooks",
                    metadata: ["date": entry.date, "type": "journal"]
                )
                memoryCount += 1
            }
            
            // Ingest coach sessions
            if let sessions = entry.daily.coachSession {
                for session in sessions {
                    try await swiftMemAPI.add(
                        content: session.summary,
                        userId: "riley_brooks",
                        metadata: ["date": entry.date, "type": "coach_session"]
                    )
                    memoryCount += 1
                }
            }
        }
        
        print("✅ Ingested \(memoryCount) memories")
        
        // 4. Test retrieval with questions
        print("\n4️⃣ Testing retrieval...")
        let testQuestions = [
            "What is Riley working on?",
            "What course is Riley taking?",
            "What are Riley's career goals?",
            "What project is Riley building?",
            "What does Riley think about agentic AI?"
        ]
        
        for (i, question) in testQuestions.enumerated() {
            print("\n📝 Question \(i+1): \(question)")
            
            // Retrieve relevant memories
            let results = try await swiftMemAPI.search(
                query: question,
                userId: "riley_brooks",
                limit: 3
            )
            
            print("   Retrieved \(results.count) memories:")
            for (j, result) in results.enumerated() {
                let preview = String(result.content.prefix(100))
                print("   \(j+1). [\(String(format: "%.2f", result.score))] \(preview)...")
            }
            
            // Use Groq to answer based on retrieved context
            let answer = try await answerWithGroq(
                question: question,
                context: results.map { $0.content }
            )
            
            print("   🤖 Answer: \(answer)")
        }
        
        // 5. Get stats
        print("\n5️⃣ Memory Statistics:")
        let stats = try await swiftMemAPI.getStats()
        print("   Total memories: \(stats.totalMemories)")
        print("   Total relationships: \(stats.totalRelationships)")
        print("   Average connections: \(String(format: "%.2f", stats.averageDegree))")
        
        print("\n✅ Test complete!")
    }
    
    /// Answer question using Groq API
    private func answerWithGroq(question: String, context: [String]) async throws -> String {
        let contextStr = context.joined(separator: "\n\n")
        
        let prompt = """
        Based on the following context about Riley Brooks, answer the question concisely.
        
        Context:
        \(contextStr)
        
        Question: \(question)
        
        Answer:
        """
        
        // Call Groq API
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 150
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GroqResponse.self, from: data)
        
        return response.choices.first?.message.content ?? "No answer"
    }
}

// MARK: - Data Models

struct RileyBrooksContext: Codable {
    let dayEntries: [RileyDayEntry]
}

struct RileyDayEntry: Codable {
    let date: String
    let daily: RileyDailyData
}

struct RileyDailyData: Codable {
    let journalEntries: [RileyJournalEntry]
    let coachSession: [RileyCoachSession]?
}

struct RileyJournalEntry: Codable {
    let text: String
    let tags: [String]
}

struct RileyCoachSession: Codable {
    let title: String
    let summary: String
}

struct GroqResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String
    }
}
