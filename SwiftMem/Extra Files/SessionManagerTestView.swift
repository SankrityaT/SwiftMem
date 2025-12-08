//
//  SessionManagerTestView.swift
//  Test session grouping and multi-session retrieval
//

import SwiftUI

struct SessionManagerTestView: View {
    @State private var testResults: [String] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Session Grouping Test")
                        .font(.largeTitle)
                        .bold()
                    
                    Text("Tests multi-session memory management")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Run Session Tests")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isLoading)
                    
                    if !testResults.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Results:")
                                .font(.headline)
                            
                            ForEach(testResults.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 8) {
                                    if testResults[index].hasPrefix("✅") {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    } else if testResults[index].hasPrefix("❌") {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    } else {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Text(testResults[index])
                                        .font(.system(.body, design: .monospaced))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    if isLoading {
                        ProgressView("Testing...")
                    }
                }
                .padding()
            }
            .navigationTitle("Sessions")
        }
    }
    
    func runTest() {
        Task {
            isLoading = true
            testResults = []
            
            do {
                testResults.append("Testing SessionManager...")
                
                // Setup - use unique DB file for each run
                let timestamp = Int(Date().timeIntervalSince1970)
                let config = SwiftMemConfig.default
                
                let graphStore = try await GraphStore.create(
                    config: config,
                    filename: "swiftmem_sessions_\(timestamp).db"
                )
                let sessionManager = SessionManager(graphStore: graphStore)
                
                testResults.append("✅ Created SessionManager")
                
                // TEST 1: Create sessions
                testResults.append("\n📝 Test 1: Create Sessions")
                
                let session1 = sessionManager.startSession(type: .chat)
                testResults.append("   Created session 1: \(String(session1.id.value.uuidString.prefix(8)))")
                
                let session2 = sessionManager.startSession(type: .chat)
                testResults.append("   Created session 2: \(String(session2.id.value.uuidString.prefix(8)))")
                
                // TEST 2: Store memories in session
                testResults.append("\n📝 Test 2: Store Memories in Session")
                
                let msg1 = Node(content: "Hello!", type: .episodic)
                let msg2 = Node(content: "How are you?", type: .episodic)
                let msg3 = Node(content: "I love hiking", type: .semantic)
                
                try await sessionManager.storeMemory(msg1, sessionId: session1.id, messageIndex: 0)
                try await sessionManager.storeMemory(msg2, sessionId: session1.id, messageIndex: 1)
                try await sessionManager.storeMemory(msg3, sessionId: session1.id, messageIndex: 2)
                
                testResults.append("   ✅ Stored 3 memories in session 1")
                
                // Verify metadata
                if let stored = try await graphStore.getNode(msg1.id) {
                    if stored.metadata["session_id"] != nil {
                        testResults.append("   ✅ Session metadata added")
                    }
                    if stored.metadata["message_index"] != nil {
                        testResults.append("   ✅ Message index added")
                    }
                }
                
                // TEST 3: Retrieve session memories
                testResults.append("\n📝 Test 3: Retrieve Session Memories")
                
                let retrieved = try await sessionManager.getMemories(fromSession: session1.id)
                testResults.append("   Retrieved \(retrieved.count) memories")
                
                if retrieved.count == 3 {
                    testResults.append("   ✅ Correct count")
                    
                    // Check order
                    if retrieved[0].content == "Hello!" &&
                       retrieved[1].content == "How are you?" &&
                       retrieved[2].content == "I love hiking" {
                        testResults.append("   ✅ Correct chronological order")
                    } else {
                        testResults.append("   ❌ Wrong order")
                    }
                } else {
                    testResults.append("   ❌ Wrong count (expected 3)")
                }
                
                // TEST 4: Session edges
                testResults.append("\n📝 Test 4: Same-Session Edges")
                
                let edges = try await graphStore.getOutgoingEdges(from: msg2.id)
                testResults.append("   Found \(edges.count) edges from msg2")
                
                if edges.count > 0 {
                    let sameSessionEdges = edges.filter { $0.relationshipType == .sameSession }
                    testResults.append("   ✅ Created \(sameSessionEdges.count) sameSession edge(s)")
                }
                
                // TEST 5: Multiple session storage
                testResults.append("\n📝 Test 5: Multiple Sessions")
                
                let session2Msgs = [
                    Node(content: "Good morning", type: .episodic),
                    Node(content: "Weather is nice", type: .episodic)
                ]
                
                try await sessionManager.storeMemories(session2Msgs, sessionId: session2.id)
                testResults.append("   ✅ Stored 2 memories in session 2")
                
                let session2Retrieved = try await sessionManager.getMemories(fromSession: session2.id)
                if session2Retrieved.count == 2 {
                    testResults.append("   ✅ Session 2 has correct count")
                }
                
                // TEST 6: Multi-session query
                testResults.append("\n📝 Test 6: Multi-Session Query")
                
                let query = SessionQuery(
                    sessionIds: [session1.id, session2.id]
                )
                
                let multiResults = try await sessionManager.getMemories(query: query)
                testResults.append("   Retrieved \(multiResults.count) memories total")
                
                if multiResults.count == 5 {
                    testResults.append("   ✅ Got all memories from both sessions")
                } else {
                    testResults.append("   ❌ Expected 5, got \(multiResults.count)")
                }
                
                // TEST 7: Date range query
                testResults.append("\n📝 Test 7: Date Range Query")
                
                let now = Date()
                let oneHourAgo = now.addingTimeInterval(-3600)
                
                let dateQuery = SessionQuery(
                    dateRange: (oneHourAgo, now)
                )
                
                let dateResults = try await sessionManager.getMemories(query: dateQuery)
                testResults.append("   Found \(dateResults.count) memories in last hour")
                
                if dateResults.count == 5 {
                    testResults.append("   ✅ All memories in date range")
                }
                
                // TEST 8: Get unique sessions
                testResults.append("\n📝 Test 8: Get Unique Sessions")
                
                let sessions = try await sessionManager.getSessions(
                    from: oneHourAgo,
                    to: now
                )
                
                testResults.append("   Found \(sessions.count) unique sessions")
                
                if sessions.count == 2 {
                    testResults.append("   ✅ Correct session count")
                }
                
                // TEST 9: End session
                testResults.append("\n📝 Test 9: End Session")
                
                sessionManager.endSession(session1.id)
                
                if let endedSession = sessionManager.getActiveSession(session1.id),
                   endedSession.endDate != nil {
                    testResults.append("   ✅ Session ended with timestamp")
                } else {
                    testResults.append("   ⚠️ Session end date not set")
                }
                
                testResults.append("\n🎉 All session tests complete!")
                
            } catch {
                testResults.append("❌ Error: \(error.localizedDescription)")
            }
            
            isLoading = false
        }
    }
}

#Preview {
    SessionManagerTestView()
}
