//
//  GroqMemoryEval.swift
//  SwiftMem — LongMemEval-style retrieval quality test
//
//  Flow per question:
//    1. Search SwiftMem with the question
//    2. Pack top-K memories into a context block
//    3. Ask Groq to answer from only that context
//    4. Check if expected keywords appear in the answer
//
//  Question types mirror LongMemEval categories:
//    • single-hop  — direct recall of one fact
//    • multi-hop   — answer requires combining two memories
//    • temporal    — recency / time-aware
//    • update      — newer fact should override older one
//    • absence     — correct answer is "no" / "unknown"
//

import Foundation
import SwiftUI

// MARK: - Data Models

struct EvalQuestion {
    let id: Int
    let type: QuestionType
    let question: String
    let expectedKeywords: [String]   // any match → pass (lowercased)
    let negativeKeywords: [String]   // any match → fail (for absence tests)

    enum QuestionType: String {
        case singleHop   = "Single-hop"
        case multiHop    = "Multi-hop"
        case temporal    = "Temporal"
        case update      = "Update"
        case absence     = "Absence"
    }

    init(_ id: Int, _ type: QuestionType, _ question: String,
         expected: [String], negative: [String] = []) {
        self.id = id; self.type = type; self.question = question
        self.expectedKeywords = expected; self.negativeKeywords = negative
    }
}

struct EvalResult: Identifiable {
    let id = UUID()
    let question: EvalQuestion
    let retrieved: [String]          // memory snippets shown to Groq
    let answer: String               // Groq's raw answer
    let passed: Bool
    let failReason: String?
    let tokensUsed: Int
    let durationMs: Double
}

// MARK: - Eval Actor

actor GroqMemoryEval {

    // ── Seed memories (planted into SwiftMem before questions) ───────────────

    // daysAgo: nil = now, positive = N days in the past (for temporal eval)
    static let seedMemories: [(content: String, tags: [String], daysAgo: Double?)] = [
        ("My name is Jordan and I am 31 years old",                          ["eval"], nil),
        ("I work as an iOS engineer at a startup called NovaMind in Austin", ["eval"], nil),
        ("My favourite language is Swift and I also enjoy Python",           ["eval"], nil),
        ("I have a border collie named Luna",                                ["eval"], nil),
        ("I attended WWDC in June and gave a talk about on-device ML",       ["eval"], nil),
        ("I prefer green tea over coffee every morning",                     ["eval"], nil),
        ("My brother Liam lives in Toronto and works in finance",            ["eval"], nil),
        ("I used to live in Chicago before moving to Austin last year",      ["eval"], nil),
        ("My current side project is a Swift memory SDK called SwiftMem",    ["eval"], nil),
        // Store 5 days ago (Wed) — falls inside "last week" [Mon–Sun] regardless
        // of whether the calendar uses Sunday or Monday as week start.
        ("I went hiking in Yosemite last weekend with Luna",                 ["eval"], 5),
    ]

    // ── Question bank ─────────────────────────────────────────────────────────

    static let questions: [EvalQuestion] = [
        EvalQuestion(1, .singleHop,
            "What is my job and where do I work?",
            expected: ["novamind", "ios", "engineer", "austin"]),

        EvalQuestion(2, .singleHop,
            "What pet do I have and what is its name?",
            expected: ["luna", "border collie", "dog"]),

        EvalQuestion(3, .singleHop,
            "What programming languages do I like?",
            expected: ["swift", "python"]),

        EvalQuestion(4, .multiHop,
            "What city does my brother live in and what does he do for work?",
            expected: ["toronto", "finance", "liam"]),

        EvalQuestion(5, .temporal,
            "What did I do last weekend?",
            expected: ["yosemite", "hiking", "luna"]),

        EvalQuestion(6, .update,
            "Where do I currently live?",
            expected: ["austin"],
            // Only fail if Groq says Chicago is the CURRENT home — mentioning it as old location is fine
            negative: ["live in chicago", "living in chicago", "currently in chicago"]),

        EvalQuestion(7, .absence,
            "Do I have a cat?",
            expected: ["no", "don't", "do not", "not found", "border collie", "dog", "only"],
            negative: ["yes, i have a cat", "i have a cat"]),

        EvalQuestion(8, .singleHop,
            "What am I building as a side project?",
            expected: ["swiftmem", "memory sdk", "swift memory"]),

        EvalQuestion(9, .temporal,
            "What conference did I attend and what did I speak about?",
            expected: ["wwdc", "on-device", "ml", "machine learning", "talk"]),

        EvalQuestion(10, .multiHop,
            "What do I drink in the mornings and what language is my side project in?",
            expected: ["green tea", "swift"]),
    ]

    // ── Config ────────────────────────────────────────────────────────────────

    private let apiKey: String
    private let model = "llama-3.3-70b-versatile"
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let retrievalTopK = 6
    /// Seconds between Groq calls — keeps us well under 30 RPM (10 calls ÷ 60s = 10 RPM)
    private let callDelay: UInt64 = 2_000_000_000

    init(apiKey: String) { self.apiKey = apiKey }

    // ── Main eval entry ───────────────────────────────────────────────────────

    func run(api: SwiftMemAPI, userId: String,
             progress: @Sendable @escaping (String) -> Void) async -> [EvalResult] {

        // 1. Seed memories
        progress("Seeding \(Self.seedMemories.count) eval memories…")
        for seed in Self.seedMemories {
            let date = seed.daysAgo.map { Date().addingTimeInterval(-$0 * 86400) }
            try? await api.add(content: seed.content, userId: userId,
                               metadata: nil, containerTags: seed.tags,
                               conversationDate: date)
        }
        print("🌱 [MemEval] Seeded \(Self.seedMemories.count) memories")

        // 2. Run each question
        var results: [EvalResult] = []
        for q in Self.questions {
            progress("Q\(q.id)/\(Self.questions.count): \(q.question.prefix(40))…")

            let start = Date()

            // Retrieve
            let hits = (try? await api.search(query: q.question, userId: userId,
                                              limit: retrievalTopK,
                                              containerTags: ["eval"])) ?? []
            let snippets = hits.map { $0.content }
            let context  = snippets.enumerated()
                .map { "[\($0.offset + 1)] \($0.element)" }
                .joined(separator: "\n")

            // Ask Groq
            let (answer, tokens) = await askGroq(question: q.question, context: context)
            let ms = Date().timeIntervalSince(start) * 1000

            // Evaluate
            let lower = answer.lowercased()
            let hitNegative = q.negativeKeywords.contains { lower.contains($0) }
            let hitExpected = q.expectedKeywords.contains { lower.contains($0) }
            let passed = hitExpected && !hitNegative
            let failReason: String? = {
                if hitNegative { return "Answer contained negative keyword" }
                if !hitExpected { return "None of \(q.expectedKeywords) found in answer" }
                return nil
            }()

            let result = EvalResult(question: q, retrieved: snippets, answer: answer,
                                    passed: passed, failReason: failReason,
                                    tokensUsed: tokens, durationMs: ms)
            results.append(result)

            let icon = passed ? "✅" : "❌"
            print("\(icon) [MemEval] Q\(q.id) [\(q.type.rawValue)] — \(answer.prefix(80))")
            if let reason = failReason { print("   ↳ \(reason)") }

            // Throttle — stay well under 30 RPM
            if q.id < Self.questions.count {
                try? await Task.sleep(nanoseconds: callDelay)
            }
        }

        printSummary(results)
        return results
    }

    // ── Groq call ─────────────────────────────────────────────────────────────

    private func askGroq(question: String, context: String) async -> (answer: String, tokens: Int) {
        let userMessage = """
        Use only the memories below to answer the question. \
        Be concise (1-2 sentences). If the memories don't contain the answer, say "Not found in memory."

        Memories:
        \(context.isEmpty ? "(none retrieved)" : context)

        Question: \(question)
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content":
                    "You are a memory assistant. Answer questions using only the provided memories. Be factual and brief."],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 120,
            "temperature": 0.0
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return ("(serialization error)", 0)
        }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as! HTTPURLResponse

            // Log quota
            if let rem = http.value(forHTTPHeaderField: "x-ratelimit-remaining-requests") {
                print("📊 [MemEval] Remaining requests this minute: \(rem)/30")
            }

            guard http.statusCode == 200,
                  let json     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices  = json["choices"]  as? [[String: Any]],
                  let message  = choices.first?["message"] as? [String: Any],
                  let content  = message["content"] as? String
            else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                return ("(error \(http.statusCode): \(raw.prefix(100)))", 0)
            }

            let tokens = (json["usage"] as? [String: Any])?["total_tokens"] as? Int ?? 0
            return (content.trimmingCharacters(in: .whitespacesAndNewlines), tokens)

        } catch {
            return ("(network error: \(error.localizedDescription))", 0)
        }
    }

    // ── Console summary ───────────────────────────────────────────────────────

    private func printSummary(_ results: [EvalResult]) {
        let passed  = results.filter { $0.passed }.count
        let total   = results.count
        let tokens  = results.map { $0.tokensUsed }.reduce(0, +)

        print("")
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║           SwiftMem LongMemEval-style Retrieval Eval          ║")
        print("╠══════════════════════════════════════════════════════════════╣")
        for r in results {
            let icon = r.passed ? "✅" : "❌"
            let type = r.question.type.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)
            print("║ \(icon) Q\(String(r.question.id).padding(toLength:2,withPad:" ",startingAt:0)) [\(type)] \(r.question.question.prefix(38))")
            if !r.passed, let reason = r.failReason {
                print("║       ↳ \(reason)")
                print("║       ↳ Answer: \(r.answer.prefix(60))")
            }
        }
        print("╠══════════════════════════════════════════════════════════════╣")
        print("║  SCORE  : \(passed)/\(total) (\(Int(Double(passed)/Double(total)*100))%)")
        print("║  TOKENS : \(tokens) total")
        print("╚══════════════════════════════════════════════════════════════╝")
        print("")
    }
}
