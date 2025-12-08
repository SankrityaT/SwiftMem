//
//  ConflictDetectorTestView.swift
//  Test knowledge update detection
//

import SwiftUI

struct ConflictDetectorTestView: View {
    @State private var testResults: [String] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Conflict Detection Test")
                        .font(.largeTitle)
                        .bold()
                    
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Run Conflict Tests")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.purple)
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
                                    } else if testResults[index].hasPrefix("⚠️") {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                    } else if testResults[index].hasPrefix("🔍") {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(testResults[index])
                                        .font(.system(.body, design: .monospaced))
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
            .navigationTitle("Conflict Detection")
        }
    }
    
    func runTest() {
        Task {
            isLoading = true
            testResults = []
            
            do {
                testResults.append("🔍 Testing ConflictDetector...")
                
                // Setup - clean database
                let config = SwiftMemConfig.default
                let dbURL = try config.storageLocation.url(filename: "swiftmem_conflict.db")
                try? FileManager.default.removeItem(at: dbURL)
                try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("shm"))
                try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("wal"))
                
                let graphStore = try await GraphStore.create(config: config)
                let vectorStore = VectorStore(config: config)
                let embedder = GroqEmbedder(apiKey: "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")
                let embeddingEngine = EmbeddingEngine(embedder: embedder, config: config)
                
                let detector = ConflictDetector(
                    graphStore: graphStore,
                    vectorStore: vectorStore,
                    embeddingEngine: embeddingEngine,
                    config: .default
                )
                
                testResults.append("✅ Created ConflictDetector")
                
                // TEST 1: Updates detection (same subject, different value)
                testResults.append("\n📝 Test 1: Updates Detection")
                
                let oldColorNode = Node(
                    content: "My favorite color is blue",
                    type: .semantic
                )
                try await graphStore.storeNode(oldColorNode)
                let oldEmbedding = try await embeddingEngine.embed(oldColorNode.content)
                try await vectorStore.addVector(oldEmbedding, for: oldColorNode.id)
                testResults.append("   Stored: 'favorite color is blue'")
                
                let newColorNode = Node(
                    content: "My favorite color is green",
                    type: .semantic
                )
                
                let conflicts1 = try await detector.detectConflicts(for: newColorNode)
                if conflicts1.count > 0 {
                    let conflict = conflicts1[0]
                    testResults.append("   ✅ Detected conflict!")
                    testResults.append("      Type: \(conflict.conflictType.rawValue)")
                    testResults.append("      Similarity: \(String(format: "%.2f", conflict.similarity))")
                    testResults.append("      Confidence: \(String(format: "%.2f", conflict.confidence))")
                    testResults.append("      Reason: \(conflict.reason)")
                    
                    if conflict.conflictType == .updates || conflict.conflictType == .supersedes {
                        testResults.append("   ✅ Correct conflict type!")
                    } else {
                        testResults.append("   ⚠️ Expected 'updates', got '\(conflict.conflictType.rawValue)'")
                    }
                } else {
                    testResults.append("   ❌ No conflict detected (should find one)")
                }
                
                // TEST 2: Duplicate detection
                testResults.append("\n📝 Test 2: Duplicate Detection")
                
                let original = Node(
                    content: "I love pizza",
                    type: .semantic
                )
                try await graphStore.storeNode(original)
                let origEmbedding = try await embeddingEngine.embed(original.content)
                try await vectorStore.addVector(origEmbedding, for: original.id)
                testResults.append("   Stored: 'I love pizza'")
                
                let duplicate = Node(
                    content: "I love pizza",
                    type: .semantic
                )
                
                let conflicts2 = try await detector.detectConflicts(for: duplicate)
                if conflicts2.count > 0 {
                    let conflict = conflicts2[0]
                    testResults.append("   ✅ Detected duplicate!")
                    testResults.append("      Type: \(conflict.conflictType.rawValue)")
                    testResults.append("      Similarity: \(String(format: "%.2f", conflict.similarity))")
                    
                    if conflict.conflictType == .duplicate {
                        testResults.append("   ✅ Correct conflict type!")
                    } else {
                        testResults.append("   ⚠️ Expected 'duplicate', got '\(conflict.conflictType.rawValue)'")
                    }
                } else {
                    testResults.append("   ❌ No duplicate detected")
                }
                
                // TEST 3: Extension detection
                testResults.append("\n📝 Test 3: Extension Detection")
                
                let baseNode = Node(
                    content: "I work at Google",
                    type: .semantic
                )
                try await graphStore.storeNode(baseNode)
                let baseEmbedding = try await embeddingEngine.embed(baseNode.content)
                try await vectorStore.addVector(baseEmbedding, for: baseNode.id)
                testResults.append("   Stored: 'I work at Google'")
                
                let extendedNode = Node(
                    content: "I work at Google as a Product Manager in the Cloud division, focusing on AI infrastructure",
                    type: .semantic
                )
                
                let conflicts3 = try await detector.detectConflicts(for: extendedNode)
                if conflicts3.count > 0 {
                    let conflict = conflicts3[0]
                    testResults.append("   ✅ Detected relationship!")
                    testResults.append("      Type: \(conflict.conflictType.rawValue)")
                    testResults.append("      Similarity: \(String(format: "%.2f", conflict.similarity))")
                    
                    if conflict.conflictType == .extends {
                        testResults.append("   ✅ Correct conflict type!")
                    } else {
                        testResults.append("   ⚠️ Expected 'extends', got '\(conflict.conflictType.rawValue)'")
                    }
                } else {
                    testResults.append("   ❌ No extension detected")
                }
                
                // TEST 4: No conflict (different topics)
                testResults.append("\n📝 Test 4: No Conflict Detection")
                
                let unrelatedNode = Node(
                    content: "The weather is sunny today",
                    type: .episodic
                )
                
                let conflicts4 = try await detector.detectConflicts(for: unrelatedNode)
                if conflicts4.isEmpty {
                    testResults.append("   ✅ Correctly detected no conflicts")
                } else {
                    testResults.append("   ⚠️ Found \(conflicts4.count) conflicts (expected 0)")
                }
                
                // TEST 5: Auto-resolve conflicts
                testResults.append("\n📝 Test 5: Auto-Resolve Conflicts")
                
                // Store the new color node
                try await graphStore.storeNode(newColorNode)
                let newEmbedding = try await embeddingEngine.embed(newColorNode.content)
                try await vectorStore.addVector(newEmbedding, for: newColorNode.id)
                
                // Detect conflicts again
                let conflictsToResolve = try await detector.detectConflicts(for: newColorNode)
                
                if !conflictsToResolve.isEmpty {
                    testResults.append("   Found \(conflictsToResolve.count) conflicts to resolve")
                    testResults.append("   Conflict type: \(conflictsToResolve[0].conflictType.rawValue)")
                    
                    // Auto-resolve
                    do {
                        try await detector.resolveConflicts(conflictsToResolve)
                        testResults.append("   ✅ Auto-resolved conflicts")
                    } catch {
                        testResults.append("   ❌ Resolve failed: \(error)")
                    }
                    
                    // Verify edge was created
                    let edges = try await graphStore.getOutgoingEdges(from: newColorNode.id)
                    
                    if edges.count > 0 {
                        testResults.append("   ✅ Created \(edges.count) edge(s)")
                        for edge in edges {
                            testResults.append("      - Type: \(edge.relationshipType.rawValue)")
                        }
                    } else {
                        testResults.append("   ❌ No edges created")
                        
                        // Debug: Check if edge exists in reverse
                        let reverseEdges = try await graphStore.getIncomingEdges(to: newColorNode.id)
                        if reverseEdges.count > 0 {
                            testResults.append("   ⚠️ Found \(reverseEdges.count) incoming edges instead!")
                        }
                    }
                    
                    // Verify old node metadata
                    if let updatedOld = try await graphStore.getNode(oldColorNode.id) {
                        if updatedOld.metadata["superseded_by"] != nil {
                            testResults.append("   ✅ Old node marked as superseded")
                        } else {
                            testResults.append("   ⚠️ Old node not marked as superseded")
                        }
                    }
                } else {
                    testResults.append("   ⚠️ No conflicts found to resolve")
                }
                
                testResults.append("\n🎉 All conflict detection tests complete!")
                
            } catch {
                testResults.append("❌ Error: \(error.localizedDescription)")
            }
            
            isLoading = false
        }
    }
}

#Preview {
    ConflictDetectorTestView()
}
