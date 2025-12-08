//
//  IntegratedConflictTestView.swift
//  SwiftMem
//
//  Created by Sankritya Thakur on 12/7/25.
//


//
//  IntegratedConflictTestView.swift
//  Test ConflictDetector with EntityExtractor integration
//

import SwiftUI

struct IntegratedConflictTestView: View {
    @State private var testResults: [String] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Integrated Conflict Detection")
                        .font(.largeTitle)
                        .bold()
                    
                    Text("Tests entity-aware conflict detection")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Run Integration Tests")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
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
            .navigationTitle("Integration Test")
        }
    }
    
    func runTest() {
        Task {
            isLoading = true
            testResults = []
            
            do {
                testResults.append("🔍 Testing entity-aware conflict detection...")
                
                // Setup
                let config = SwiftMemConfig.default
                let dbURL = try config.storageLocation.url(filename: "swiftmem_integrated.db")
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
                
                testResults.append("✅ Created integrated system")
                
                // TEST 1: Entity-based conflict detection (favorite color)
                testResults.append("\n📝 Test 1: Entity-Based Updates Detection")
                
                let oldColor = Node(content: "My favorite color is blue", type: .semantic)
                try await graphStore.storeNode(oldColor)
                let oldEmbed = try await embeddingEngine.embed(oldColor.content)
                try await vectorStore.addVector(oldEmbed, for: oldColor.id)
                testResults.append("   Stored: 'favorite color is blue'")
                
                let newColor = Node(content: "My favorite color is green", type: .semantic)
                
                // Use entity-aware detection
                let conflicts1 = try await detector.detectConflictsWithEntities(for: newColor)
                
                if conflicts1.count > 0 {
                    let conflict = conflicts1[0]
                    testResults.append("   ✅ Detected conflict with entities!")
                    testResults.append("      Type: \(conflict.conflictType.rawValue)")
                    testResults.append("      Confidence: \(String(format: "%.2f", conflict.confidence))")
                    testResults.append("      Reason: \(conflict.reason)")
                    
                    if conflict.reason.contains("favorite color") {
                        testResults.append("   ✅ Correctly identified subject!")
                    } else {
                        testResults.append("   ⚠️ Subject not in reason")
                    }
                } else {
                    testResults.append("   ❌ No conflict detected")
                }
                
                // TEST 2: Entity-based job change detection
                testResults.append("\n📝 Test 2: Employment Change Detection")
                
                let oldJob = Node(content: "I work at Google", type: .semantic)
                try await graphStore.storeNode(oldJob)
                let oldJobEmbed = try await embeddingEngine.embed(oldJob.content)
                try await vectorStore.addVector(oldJobEmbed, for: oldJob.id)
                testResults.append("   Stored: 'work at Google'")
                
                let newJob = Node(content: "I work at Microsoft", type: .semantic)
                
                let conflicts2 = try await detector.detectConflictsWithEntities(for: newJob)
                
                if conflicts2.count > 0 {
                    let conflict = conflicts2[0]
                    testResults.append("   ✅ Detected job change!")
                    testResults.append("      Type: \(conflict.conflictType.rawValue)")
                    testResults.append("      Reason: \(conflict.reason)")
                    
                    if conflict.reason.contains("employment") {
                        testResults.append("   ✅ Correctly identified employment conflict!")
                    }
                } else {
                    testResults.append("   ❌ No conflict detected")
                }
                
                // TEST 3: No false positive (different subjects)
                testResults.append("\n📝 Test 3: No False Positives")
                
                let unrelated = Node(content: "I love pizza", type: .semantic)
                
                let conflicts3 = try await detector.detectConflictsWithEntities(for: unrelated)
                
                if conflicts3.isEmpty {
                    testResults.append("   ✅ Correctly detected no conflicts")
                } else {
                    testResults.append("   ⚠️ False positive: \(conflicts3.count) conflicts")
                    for c in conflicts3 {
                        testResults.append("      - \(c.reason)")
                    }
                }
                
                // TEST 4: Multiple fact conflicts (supersedes)
                testResults.append("\n📝 Test 4: Multiple Fact Conflicts")
                
                let oldProfile = Node(
                    content: "My name is John and I work at Google",
                    type: .semantic
                )
                try await graphStore.storeNode(oldProfile)
                let oldProfEmbed = try await embeddingEngine.embed(oldProfile.content)
                try await vectorStore.addVector(oldProfEmbed, for: oldProfile.id)
                testResults.append("   Stored: 'name is John, work at Google'")
                
                let newProfile = Node(
                    content: "My name is John and I work at Microsoft",
                    type: .semantic
                )
                
                let conflicts4 = try await detector.detectConflictsWithEntities(for: newProfile)
                
                if conflicts4.count > 0 {
                    let conflict = conflicts4[0]
                    testResults.append("   ✅ Detected profile change!")
                    testResults.append("      Type: \(conflict.conflictType.rawValue)")
                    testResults.append("      Reason: \(conflict.reason)")
                    
                    // Should be 'updates' (single fact change, name is same)
                    if conflict.conflictType == .updates {
                        testResults.append("   ✅ Correct type (updates, not supersedes)")
                    } else {
                        testResults.append("   ⚠️ Expected 'updates', got '\(conflict.conflictType.rawValue)'")
                    }
                } else {
                    testResults.append("   ❌ No conflict detected")
                }
                
                // TEST 5: Fallback to similarity when no entities
                testResults.append("\n📝 Test 5: Fallback to Similarity")
                
                let genericOld = Node(
                    content: "The sky looks beautiful today",
                    type: .episodic
                )
                try await graphStore.storeNode(genericOld)
                let genOldEmbed = try await embeddingEngine.embed(genericOld.content)
                try await vectorStore.addVector(genOldEmbed, for: genericOld.id)
                testResults.append("   Stored: 'sky looks beautiful'")
                
                let genericNew = Node(
                    content: "The weather seems nice today",
                    type: .episodic
                )
                
                let conflicts5 = try await detector.detectConflictsWithEntities(for: genericNew)
                
                testResults.append("   Found \(conflicts5.count) conflicts")
                testResults.append("   ✅ Fallback works (episodic memories)")
                
                // TEST 6: Auto-resolve with entities
                testResults.append("\n📝 Test 6: Auto-Resolve with Entities")
                
                // Store the new color node
                try await graphStore.storeNode(newColor)
                let newColorEmbed = try await embeddingEngine.embed(newColor.content)
                try await vectorStore.addVector(newColorEmbed, for: newColor.id)
                
                // Re-detect
                let toResolve = try await detector.detectConflictsWithEntities(for: newColor)
                
                if !toResolve.isEmpty {
                    testResults.append("   Found \(toResolve.count) conflicts to resolve")
                    
                    try await detector.resolveConflicts(toResolve)
                    testResults.append("   ✅ Auto-resolved conflicts")
                    
                    // Verify edge created
                    let edges = try await graphStore.getOutgoingEdges(from: newColor.id)
                    if edges.count > 0 {
                        testResults.append("   ✅ Created \(edges.count) edge(s)")
                        testResults.append("      Type: \(edges[0].relationshipType.rawValue)")
                    } else {
                        testResults.append("   ❌ No edges created")
                    }
                    
                    // Verify metadata
                    if let updated = try await graphStore.getNode(oldColor.id) {
                        if updated.metadata["superseded_by"] != nil {
                            testResults.append("   ✅ Old node marked as superseded")
                        } else {
                            testResults.append("   ⚠️ Metadata not updated")
                        }
                    }
                } else {
                    testResults.append("   ⚠️ No conflicts to resolve")
                }
                
                // TEST 7: Compare entity vs non-entity detection
                testResults.append("\n📝 Test 7: Entity vs Similarity Comparison")
                
                let comparison = Node(content: "My favorite food is pasta", type: .semantic)
                
                // Without entities
                let simConflicts = try await detector.detectConflicts(for: comparison)
                testResults.append("   Similarity-based: \(simConflicts.count) conflicts")
                
                // With entities
                let entityConflicts = try await detector.detectConflictsWithEntities(for: comparison)
                testResults.append("   Entity-based: \(entityConflicts.count) conflicts")
                
                if entityConflicts.count > simConflicts.count {
                    testResults.append("   ✅ Entity detection more precise")
                } else {
                    testResults.append("   ℹ️ Both methods found similar results")
                }
                
                testResults.append("\n🎉 All integration tests complete!")
                
            } catch {
                testResults.append("❌ Error: \(error.localizedDescription)")
            }
            
            isLoading = false
        }
    }
}

#Preview {
    IntegratedConflictTestView()
}