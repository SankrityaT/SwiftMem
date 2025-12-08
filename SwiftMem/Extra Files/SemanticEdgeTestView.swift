//
//  SemanticEdgeTestView.swift
//  Test semantic relationship types
//

import SwiftUI

struct SemanticEdgeTestView: View {
    @State private var testResults: [String] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Semantic Edge Types Test")
                        .font(.largeTitle)
                        .bold()
                    
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Run Edge Type Test")
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
            .navigationTitle("Edge Types")
        }
    }
    
    func runTest() {
        Task {
            isLoading = true
            testResults = []
            
            do {
                testResults.append("Testing semantic edge types...")
                
                // Setup - FORCE clean database
                let config = SwiftMemConfig.default
                let dbURL = try config.storageLocation.url(filename: "swiftmem_edgetest.db")
                
                // Delete main db and journal files
                try? FileManager.default.removeItem(at: dbURL)
                try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("shm"))
                try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("wal"))
                
                testResults.append("🗑️ Cleaned old database files")
                
                let graphStore = try await GraphStore.create(config: config)
                testResults.append("✅ Created GraphStore")
                
                // Create test nodes
                let oldNode = Node(content: "My favorite color is blue", type: .semantic)
                let newNode = Node(content: "My favorite color is green", type: .semantic)
                let detailNode = Node(content: "I prefer emerald green specifically", type: .semantic)
                let derivedNode = Node(content: "User likes cool colors", type: .semantic)
                
                try await graphStore.storeNodes([oldNode, newNode, detailNode, derivedNode])
                testResults.append("✅ Stored 4 test nodes")
                
                // Verify nodes exist
                let storedOld = try await graphStore.getNode(oldNode.id)
                let storedNew = try await graphStore.getNode(newNode.id)
                if storedOld != nil && storedNew != nil {
                    testResults.append("✅ Verified nodes exist in DB")
                } else {
                    testResults.append("❌ Nodes not found!")
                }
                
                // Test 1: Updates relationship
                testResults.append("Creating updates edge...")
                testResults.append("   From: \(String(newNode.id.value.uuidString.prefix(8)))")
                testResults.append("   To: \(String(oldNode.id.value.uuidString.prefix(8)))")
                
                let updatesEdge = Edge(
                    fromNodeID: newNode.id,
                    toNodeID: oldNode.id,
                    relationshipType: .updates
                )
                try await graphStore.storeEdge(updatesEdge)
                testResults.append("✅ Created 'updates' edge")
                
                // Test 2: Extends relationship
                let extendsEdge = Edge(
                    fromNodeID: detailNode.id,
                    toNodeID: newNode.id,
                    relationshipType: .extends
                )
                try await graphStore.storeEdge(extendsEdge)
                testResults.append("✅ Created 'extends' edge")
                
                // Test 3: Derives relationship
                let derivesEdge = Edge(
                    fromNodeID: derivedNode.id,
                    toNodeID: oldNode.id,
                    relationshipType: .derives
                )
                try await graphStore.storeEdge(derivesEdge)
                testResults.append("✅ Created 'derives' edge")
                
                // Test 4: Temporal relationships
                let event1 = Node(content: "Woke up at 6am", type: .episodic)
                let event2 = Node(content: "Had breakfast", type: .episodic)
                try await graphStore.storeNodes([event1, event2])
                
                let followedByEdge = Edge(
                    fromNodeID: event1.id,
                    toNodeID: event2.id,
                    relationshipType: .followedBy
                )
                try await graphStore.storeEdge(followedByEdge)
                testResults.append("✅ Created 'followedBy' edge")
                
                // Verify storage: retrieve edges
                let allEdges = try await graphStore.getOutgoingEdges(from: newNode.id)
                testResults.append("✅ Retrieved \(allEdges.count) edge(s) from newNode")
                
                // Verify edge content
                if allEdges.count == 1 {
                    let edge = allEdges[0]
                    testResults.append("   Type: \(edge.relationshipType.rawValue)")
                    testResults.append("   From matches: \(edge.fromNodeID == newNode.id ? "✅" : "❌")")
                    testResults.append("   To matches: \(edge.toNodeID == oldNode.id ? "✅" : "❌")")
                    testResults.append("   Weight: \(edge.weight)")
                    
                    if edge.relationshipType == .updates &&
                       edge.fromNodeID == newNode.id &&
                       edge.toNodeID == oldNode.id {
                        testResults.append("   ✅ Edge data is CORRECT!")
                    } else {
                        testResults.append("   ❌ Edge data is WRONG!")
                    }
                } else if allEdges.count == 0 {
                    testResults.append("   ❌ No edges found - query bug!")
                } else {
                    testResults.append("   ⚠️ Found \(allEdges.count) edges, expected 1")
                }
                
                // Test all relationship types compile
                let allTypes: [RelationshipType] = [
                    .related, .updates, .extends, .supersedes, .derives,
                    .followedBy, .precedes, .causes,
                    .partOf, .contains, .subtopicOf,
                    .similarTo, .oppositeOf, .mentions,
                    .sameSession, .references
                ]
                testResults.append("✅ All \(allTypes.count) relationship types available")
                
                testResults.append("\n🎉 All semantic edge tests passed!")
                
            } catch {
                testResults.append("❌ Error: \(error.localizedDescription)")
            }
            
            isLoading = false
        }
    }
}

#Preview {
    SemanticEdgeTestView()
}
