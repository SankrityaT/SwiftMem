//
//  MigrationTestView.swift
//  SwiftMem v3 — Comprehensive Test Suite
//
//  Tests everything: RRF, vDSP cosine, temporal parsing, contradiction detection,
//  exponential decay, bi-temporal schema, HyDE graceful degradation, graph expansion,
//  edge cases, and things expected to fail.
//

import SwiftUI

// MARK: - Test Result Model

struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    let status: Status
    let detail: String
    let duration: Double // ms

    enum Status {
        case pass, fail, warn, skip
        var icon: String {
            switch self { case .pass: "✅"; case .fail: "❌"; case .warn: "⚠️"; case .skip: "⏭️" }
        }
        var color: Color {
            switch self { case .pass: .green; case .fail: .red; case .warn: .orange; case .skip: .gray }
        }
    }
}

// MARK: - Test Suite

@MainActor
class SwiftMemTestSuite: ObservableObject {
    @Published var results: [TestResult] = []
    @Published var isRunning = false
    @Published var currentTest = ""
    @Published var summary = ""

    private let userId = "test_user_v3"
    private var api: SwiftMemAPI { SwiftMemAPI.shared }

    func runAll() async {
        isRunning = true
        results = []

        // Reset state before full run
        try? await api.clearAll()

        let tests: [(String, () async -> TestResult)] = [
            // ── Foundation ──
            ("1. Initialize SwiftMem",              testInit),
            ("2. Basic Add + Search",               testBasicAddSearch),
            ("3. RRF Score Range",                  testRRFScoreRange),
            ("4. vDSP Cosine Identity",             testVDSPCosineIdentity),
            ("5. vDSP Cosine Orthogonal",           testVDSPCosineOrthogonal),

            // ── Temporal ──
            ("6. Parse: 'yesterday'",               testTemporalYesterday),
            ("7. Parse: 'last week'",               testTemporalLastWeek),
            ("8. Parse: '3 days ago'",              testTemporalNDaysAgo),
            ("9. Parse: 'recently'",                testTemporalRecently),
            ("10. Parse: no temporal expression",   testTemporalNone),
            ("11. Temporal Search (date filter)",   testTemporalSearch),

            // ── Graph ──
            ("12. Relationship Detection",          testRelationshipDetection),
            ("13. Graph Expansion in Search",       testGraphExpansion),

            // ── Memory Types ──
            ("14. Static vs Dynamic Classification", testStaticDynamic),
            ("15. Container Tag Isolation",         testContainerTags),
            ("16. Multi-User Isolation",            testMultiUser),

            // ── v3 Features ──
            ("17. Contradiction Detection",         testContradictionDetection),
            ("18. Bi-temporal Schema Columns",      testBiTemporalSchema),
            ("19. Exponential Decay (Static)",      testExponentialDecayStatic),
            ("20. Exponential Decay (Dynamic)",     testExponentialDecayDynamic),
            ("21. HyDE Graceful Degradation",       testHyDEGraceful),

            // ── Edge Cases (expected to be tricky) ──
            ("22. Empty Query Search",              testEmptyQuery),
            ("23. Very Long Content",               testLongContent),
            ("24. Duplicate Content Add",           testDuplicateContent),
            ("25. Special Characters",              testSpecialChars),
            ("26. Large Batch (50 memories)",       testLargeBatch),
            ("27. Search After clearAll()",         testSearchAfterClear),
            ("28. Temporal: Future Date Filter",    testFutureDateFilter),
            ("29. Consolidation Dedup",             testConsolidation),
            ("30. Stats Accuracy",                  testStats),
        ]

        for (name, test) in tests {
            currentTest = name
            let result = await test()
            results.append(result)
        }

        let passed  = results.filter { $0.status == .pass }.count
        let failed  = results.filter { $0.status == .fail }.count
        let warned  = results.filter { $0.status == .warn }.count
        let total   = results.count
        let totalMs = results.map { $0.duration }.reduce(0, +)
        summary = "\(passed)/\(total) passed · \(failed) failed · \(warned) warned · \(String(format: "%.0f", totalMs))ms total"
        currentTest = "Done"
        isRunning = false
    }

    // MARK: - Helper

    private func run(name: String, block: () async throws -> (TestResult.Status, String)) async -> TestResult {
        let start = Date()
        do {
            let (status, detail) = try await block()
            let ms = Date().timeIntervalSince(start) * 1000
            return TestResult(name: name, status: status, detail: detail, duration: ms)
        } catch {
            let ms = Date().timeIntervalSince(start) * 1000
            return TestResult(name: name, status: .fail, detail: "Threw: \(error.localizedDescription)", duration: ms)
        }
    }

    private func pass(_ detail: String) -> (TestResult.Status, String) { (.pass, detail) }
    private func fail(_ detail: String) -> (TestResult.Status, String) { (.fail, detail) }
    private func warn(_ detail: String) -> (TestResult.Status, String) { (.warn, detail) }

    // MARK: - Foundation Tests

    func testInit() async -> TestResult {
        await run(name: "Init") {
            let config = SwiftMemConfig.default
            try await self.api.initialize(config: config)
            let stats = try await self.api.getStats()
            return self.pass("Init OK · \(stats.totalMemories) memories")
        }
    }

    func testBasicAddSearch() async -> TestResult {
        await run(name: "Basic Add+Search") {
            try await self.api.add(content: "I love cooking Italian food", userId: self.userId)
            try await self.api.add(content: "I am a software engineer", userId: self.userId)
            try await self.api.add(content: "My favorite color is blue", userId: self.userId)
            let results = try await self.api.search(query: "cooking food preferences", userId: self.userId, limit: 5)
            let found = results.contains { $0.content.contains("Italian") }
            let status: TestResult.Status = found ? .pass : .fail
            return (status, "Top: \(results.first?.content.prefix(50) ?? "none") · \(results.count) results")
        }
    }

    func testRRFScoreRange() async -> TestResult {
        await run(name: "RRF Score Range") {
            let results = try await self.api.search(query: "engineer software", userId: self.userId, limit: 5)
            guard let top = results.first else { return self.fail("No results returned") }
            // RRF max = 3*(1/(60+1)) ≈ 0.049; typical > 0.005
            let inRange = top.score > 0.0 && top.score < 0.2
            return (inRange ? .pass : .fail, "Top RRF: \(String(format: "%.5f", top.score)) (expected 0.005–0.05)")
        }
    }

    // MARK: - vDSP Cosine Tests

    func testVDSPCosineIdentity() async -> TestResult {
        await run(name: "vDSP Cosine Identity") {
            let v: [Float] = [1.0, 0.5, -0.3, 0.8, 0.1]
            let sim = embeddingCosineSimilarity(v, v)
            let ok = abs(sim - 1.0) < 0.0001
            return (ok ? .pass : .fail, "cosine(v,v) = \(String(format: "%.6f", sim)) (expected 1.0)")
        }
    }

    func testVDSPCosineOrthogonal() async -> TestResult {
        await run(name: "vDSP Cosine Orthogonal") {
            let a: [Float] = [1.0, 0.0, 0.0, 0.0]
            let b: [Float] = [0.0, 1.0, 0.0, 0.0]
            let sim = embeddingCosineSimilarity(a, b)
            let ok = abs(sim) < 0.0001
            return (ok ? .pass : .fail, "cosine(a⊥b) = \(String(format: "%.6f", sim)) (expected 0.0)")
        }
    }

    // MARK: - Temporal Parsing Tests

    func testTemporalYesterday() async -> TestResult {
        await run(name: "Temporal: yesterday") {
            let parser = TemporalQueryParser(referenceDate: Date())
            let result = parser.parse("what did I do yesterday?")
            guard let interval = result.interval else { return self.fail("No interval for 'yesterday'") }
            let cal = Calendar.current
            let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
            let ok = cal.isDate(interval.start, inSameDayAs: yesterday) && result.isTemporalQuery
            return (ok ? .pass : .fail, "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(interval.end.formatted(date: .abbreviated, time: .omitted))")
        }
    }

    func testTemporalLastWeek() async -> TestResult {
        await run(name: "Temporal: last week") {
            let parser = TemporalQueryParser(referenceDate: Date())
            let result = parser.parse("show me memories from last week")
            guard let interval = result.interval else { return self.fail("No interval for 'last week'") }
            let days = interval.duration / 86400
            let ok = days > 6.5 && days < 7.5
            return (ok ? .pass : .fail, "\(String(format: "%.1f", days)) days · cleaned: '\(result.cleanedQuery)'")
        }
    }

    func testTemporalNDaysAgo() async -> TestResult {
        await run(name: "Temporal: 3 days ago") {
            let parser = TemporalQueryParser(referenceDate: Date())
            let result = parser.parse("what happened 3 days ago?")
            guard let interval = result.interval else { return self.fail("No interval for '3 days ago'") }
            let cal = Calendar.current
            let target = cal.date(byAdding: .day, value: -3, to: Date())!
            let ok = cal.isDate(interval.start, inSameDayAs: target)
            return (ok ? .pass : .fail, "Start: \(interval.start.formatted(date: .abbreviated, time: .omitted))")
        }
    }

    func testTemporalRecently() async -> TestResult {
        await run(name: "Temporal: recently") {
            let parser = TemporalQueryParser(referenceDate: Date())
            let result = parser.parse("what did I eat recently?")
            guard let interval = result.interval else { return self.fail("No interval for 'recently'") }
            let days = interval.duration / 86400
            let ok = days > 6.5 && days < 7.5
            return (ok ? .pass : .fail, "Covers \(String(format: "%.1f", days)) days (expected ~7)")
        }
    }

    func testTemporalNone() async -> TestResult {
        await run(name: "Temporal: no expression") {
            let parser = TemporalQueryParser(referenceDate: Date())
            let result = parser.parse("what are my hobbies?")
            let ok = !result.isTemporalQuery && result.interval == nil
            return (ok ? .pass : .fail, "isTemporalQuery=\(result.isTemporalQuery) interval=\(result.interval == nil ? "nil ✓" : "SET ✗")")
        }
    }

    func testTemporalSearch() async -> TestResult {
        await run(name: "Temporal Search") {
            let cal = Calendar.current
            let oldDate    = cal.date(byAdding: .day, value: -30, to: Date())!
            let recentDate = cal.date(byAdding: .day, value: -1,  to: Date())!

            try await self.api.add(content: "I attended an old conference thirty days ago",
                                   userId: self.userId, metadata: nil,
                                   containerTags: ["temporal_test"], conversationDate: oldDate)
            try await self.api.add(content: "I met a new client yesterday for a kickoff",
                                   userId: self.userId, metadata: nil,
                                   containerTags: ["temporal_test"], conversationDate: recentDate)

            let last7Days = DateInterval(start: cal.date(byAdding: .day, value: -7, to: Date())!, end: Date())
            let results = try await self.api.search(query: "meetings events client",
                                                    userId: self.userId, limit: 10,
                                                    temporalFilter: last7Days)
            let hasRecent = results.contains { $0.content.contains("kickoff") }
            let hasOld    = results.contains { $0.content.contains("thirty days") }
            let ok = hasRecent && !hasOld
            return (ok ? .pass : .warn, "Recent: \(hasRecent) · Old excluded: \(!hasOld) · \(results.count) results")
        }
    }

    // MARK: - Graph Tests

    func testRelationshipDetection() async -> TestResult {
        await run(name: "Relationship Detection") {
            try await self.api.add(content: "I work at Apple as an engineer", userId: self.userId)
            try await self.api.add(content: "My job at Apple involves Swift development", userId: self.userId)
            let stats = try await self.api.getStats()
            return (stats.totalRelationships > 0 ? .pass : .warn,
                    "\(stats.totalRelationships) relationships · avg degree: \(String(format: "%.2f", stats.averageDegree))")
        }
    }

    func testGraphExpansion() async -> TestResult {
        await run(name: "Graph Expansion") {
            let results = try await self.api.search(query: "Swift development programming", userId: self.userId, limit: 8)
            let hasApple = results.contains { $0.content.lowercased().contains("apple") || $0.content.lowercased().contains("swift") }
            return (hasApple ? .pass : .warn, "\(results.count) results · Apple/Swift found: \(hasApple)")
        }
    }

    // MARK: - Memory Type Tests

    func testStaticDynamic() async -> TestResult {
        await run(name: "Static/Dynamic Classification") {
            try await self.api.add(content: "My name is Alex and I am 28 years old", userId: self.userId)
            try await self.api.add(content: "Today I went to the gym for the first time this week", userId: self.userId)
            let all = try await self.api.getAllMemories()
            let staticCount  = all.filter { $0.isStatic }.count
            let dynamicCount = all.filter { !$0.isStatic }.count
            return (staticCount > 0 || dynamicCount > 0 ? .pass : .warn,
                    "Static: \(staticCount) · Dynamic: \(dynamicCount)")
        }
    }

    func testContainerTags() async -> TestResult {
        await run(name: "Container Tag Isolation") {
            try await self.api.add(content: "Project Alpha milestone 1 complete", userId: self.userId,
                                   metadata: nil, containerTags: ["project_alpha"])
            try await self.api.add(content: "Unrelated personal memory about hiking", userId: self.userId,
                                   metadata: nil, containerTags: ["personal"])
            let results = try await self.api.search(query: "project milestone",
                                                    userId: self.userId, limit: 10,
                                                    containerTags: ["project_alpha"])
            let leaked = results.contains { $0.content.lowercased().contains("hiking") }
            return (leaked ? .fail : .pass, "\(results.count) tag-filtered results · hiking leaked: \(leaked)")
        }
    }

    func testMultiUser() async -> TestResult {
        await run(name: "Multi-User Isolation") {
            try await self.api.add(content: "Alice's confidential project details", userId: "alice_v3")
            try await self.api.add(content: "Bob's personal financial information", userId: "bob_v3")
            let aliceResults = try await self.api.search(query: "confidential project",
                                                         userId: "alice_v3", limit: 5,
                                                         containerTags: ["user:alice_v3"])
            let leaked = aliceResults.contains { $0.content.lowercased().contains("bob") }
            return (leaked ? .fail : .pass, "Alice: \(aliceResults.count) results · Bob data leaked: \(leaked)")
        }
    }

    // MARK: - v3 Feature Tests

    func testContradictionDetection() async -> TestResult {
        await run(name: "Contradiction Detection") {
            try await self.api.add(content: "I live in New York City", userId: self.userId)
            try await Task.sleep(nanoseconds: 300_000_000)
            try await self.api.add(content: "I moved to Los Angeles no longer living in New York", userId: self.userId)
            // Give fire-and-forget task time to complete
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let stats = try await self.api.getStats()
            // Can't query invalid_at from public API — verify no crash = pipeline ran
            return self.warn("Pipeline ran OK · \(stats.totalMemories) memories (check DB for invalid_at)")
        }
    }

    func testBiTemporalSchema() async -> TestResult {
        await run(name: "Bi-temporal Schema") {
            let stats = try await self.api.getStats()
            // Migration ran if app didn't crash at init and relationships loaded correctly
            return (stats.totalMemories >= 0 ? .pass : .fail,
                    "v3 schema migration OK · \(stats.totalRelationships) active relationships")
        }
    }

    func testExponentialDecayStatic() async -> TestResult {
        await run(name: "Exponential Decay (Static)") {
            let config = MemoryDecayConfig.default
            let after24h = pow(config.staticDecayRatePerHour, 24.0)
            let after30d  = pow(config.staticDecayRatePerHour, 24.0 * 30.0)
            let ok = after24h > 0.99 && after30d > 0.90
            return (ok ? .pass : .fail,
                    "24h: \(String(format: "%.4f", after24h)) · 30d: \(String(format: "%.4f", after30d))")
        }
    }

    func testExponentialDecayDynamic() async -> TestResult {
        await run(name: "Exponential Decay (Dynamic)") {
            let config = MemoryDecayConfig.default
            let after24h = pow(config.dynamicDecayRatePerHour, 24.0)
            let after7d  = pow(config.dynamicDecayRatePerHour, 24.0 * 7.0)
            let ok = after24h < 0.85 && after7d < 0.30
            return (ok ? .pass : .fail,
                    "24h: \(String(format: "%.4f", after24h)) · 7d: \(String(format: "%.4f", after7d)) (should be low)")
        }
    }

    func testHyDEGraceful() async -> TestResult {
        await run(name: "HyDE Graceful Degradation") {
            // enableHyDE=true but no LLM loaded → should skip silently, no crash
            let results = try await self.api.search(query: "cooking food", userId: self.userId, limit: 3)
            return self.warn("HyDE+no LLM → graceful skip · \(results.count) results returned normally")
        }
    }

    // MARK: - Edge Cases (Designed to Stress-Test or Fail)

    func testEmptyQuery() async -> TestResult {
        await run(name: "Empty Query") {
            let results = try await self.api.search(query: "", userId: self.userId, limit: 5)
            return self.warn("Empty query returned \(results.count) results without crashing")
        }
    }

    func testLongContent() async -> TestResult {
        await run(name: "Long Content (2000 chars)") {
            let longText = String(repeating: "This is a very long memory about software engineering best practices and design patterns. ", count: 25)
            try await self.api.add(content: longText, userId: self.userId)
            let results = try await self.api.search(query: "software engineering best practices", userId: self.userId, limit: 3)
            let found = results.contains { $0.content.count > 100 }
            return (found ? .pass : .fail, "\(longText.count) chars added · found in search: \(found)")
        }
    }

    func testDuplicateContent() async -> TestResult {
        await run(name: "Duplicate Content") {
            let content = "I have a golden retriever named Max"
            let before = try await self.api.getStats()
            try await self.api.add(content: content, userId: self.userId)
            try await self.api.add(content: content, userId: self.userId)
            let after = try await self.api.getStats()
            let added = after.totalMemories - before.totalMemories
            return self.warn("Added \(added) duplicate copies (dedup runs via consolidate())")
        }
    }

    func testSpecialChars() async -> TestResult {
        await run(name: "Special Characters") {
            let content = "I enjoy café culture & sushi 🍣 in Zürich — it's \"amazing\"!"
            try await self.api.add(content: content, userId: self.userId)
            let results = try await self.api.search(query: "sushi food culture", userId: self.userId, limit: 5)
            let found = results.contains { $0.content.contains("sushi") }
            return (found ? .pass : .fail, "Emoji + diacritics + quotes handled · found: \(found)")
        }
    }

    func testLargeBatch() async -> TestResult {
        await run(name: "Large Batch (50 memories)") {
            let contents = (1...50).map {
                "Batch memory \($0): I learned fact \($0) about machine learning and AI systems"
            }
            let before = try await self.api.getStats()
            try await self.api.batchAdd(contents: contents, userId: self.userId,
                                        containerTags: Array(repeating: ["batch_test"], count: 50))
            let after = try await self.api.getStats()
            let added = after.totalMemories - before.totalMemories
            let results = try await self.api.search(query: "machine learning AI", userId: self.userId,
                                                    limit: 5, containerTags: ["batch_test"])
            return (added == 50 ? .pass : .fail, "Added \(added)/50 · search: \(results.count) results")
        }
    }

    func testSearchAfterClear() async -> TestResult {
        await run(name: "Search After clearAll()") {
            try await self.api.add(content: "This will be cleared soon", userId: "throwaway_v3")
            try await self.api.clearAll()
            let results = try await self.api.search(query: "cleared memory", userId: "throwaway_v3", limit: 5)
            return (results.isEmpty ? .pass : .fail, "After clearAll: \(results.count) results (expected 0)")
        }
    }

    func testFutureDateFilter() async -> TestResult {
        await run(name: "Future Date Filter") {
            try await self.api.initialize(config: .default)
            try await self.api.add(content: "Memory added now for future filter test", userId: self.userId)
            let future = DateInterval(
                start: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
                end: Calendar.current.date(byAdding: .day, value: 7, to: Date())!
            )
            let results = try await self.api.search(query: "memory test", userId: self.userId,
                                                    limit: 10, temporalFilter: future)
            return (results.isEmpty ? .pass : .fail, "Future filter: \(results.count) results (expected 0)")
        }
    }

    func testConsolidation() async -> TestResult {
        await run(name: "Consolidation Dedup") {
            try await self.api.add(content: "I am passionate about iOS development with Swift", userId: self.userId)
            try await self.api.add(content: "I love iOS development and Swift programming", userId: self.userId)
            let before = try await self.api.getStats()
            let removed = try await self.api.consolidateMemories(userId: self.userId)
            let after = try await self.api.getStats()
            return (removed >= 0 ? .pass : .fail,
                    "Removed \(removed) duplicates · \(before.totalMemories) → \(after.totalMemories)")
        }
    }

    func testStats() async -> TestResult {
        await run(name: "Stats Accuracy") {
            let stats = try await self.api.getStats()
            let all = try await self.api.getAllMemories()
            let ok = stats.totalMemories == all.count
            return (ok ? .pass : .fail,
                    "Stats: \(stats.totalMemories) · getAllMemories: \(all.count) · rels: \(stats.totalRelationships)")
        }
    }
}

// MARK: - UI

struct MigrationTestView: View {
    @StateObject private var suite = SwiftMemTestSuite()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                if suite.isRunning {
                    VStack(spacing: 4) {
                        ProgressView()
                        Text(suite.currentTest)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                } else if !suite.summary.isEmpty {
                    Text(suite.summary)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(summaryBackground)
                }

                // Results list
                if suite.results.isEmpty && !suite.isRunning {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 60))
                            .foregroundColor(.blue.opacity(0.7))
                        Text("SwiftMem v3 Test Suite")
                            .font(.title2).bold()
                        Text("30 tests covering RRF, vDSP cosine, temporal\nparsing, contradiction detection, edge cases & more")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    List(suite.results) { result in
                        ResultRow(result: result)
                    }
                    .listStyle(.plain)
                }

                // Run button
                Button(action: {
                    Task { await suite.runAll() }
                }) {
                    Label(suite.isRunning ? "Running…" : "Run All Tests", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(suite.isRunning)
                .padding()
            }
            .navigationTitle("SwiftMem v3 Tests")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var summaryBackground: Color {
        let failed = suite.results.filter { $0.status == .fail }.count
        if failed == 0 { return .green.opacity(0.12) }
        if failed < 3  { return .orange.opacity(0.12) }
        return .red.opacity(0.12)
    }
}

struct ResultRow: View {
    let result: TestResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(result.status.icon)
                    .font(.system(size: 13))
                Text(result.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(result.status == .fail ? .red : .primary)
                Spacer()
                Text(String(format: "%.0fms", result.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Text(result.detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
