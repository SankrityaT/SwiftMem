//
//  EntityExtractorTestView.swift
//  SwiftMem
//
//  Created by Sankritya Thakur on 12/7/25.
//


//
//  EntityExtractorTestView.swift
//  Test entity extraction
//

import SwiftUI

struct EntityExtractorTestView: View {
    @State private var testResults: [String] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Entity Extraction Test")
                        .font(.largeTitle)
                        .bold()
                    
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Run Entity Tests")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
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
            .navigationTitle("Entity Extraction")
        }
    }
    
    func runTest() {
        Task {
            isLoading = true
            testResults = []
            
            testResults.append("Testing EntityExtractor...")
            
            let extractor = EntityExtractor()
            
            // TEST 1: Favorite pattern
            testResults.append("\n📝 Test 1: Favorite Pattern")
            let facts1 = await extractor.extractFacts(from: "My favorite color is blue")
            if facts1.count > 0 {
                testResults.append("   ✅ Extracted \(facts1.count) fact(s)")
                for fact in facts1 {
                    testResults.append("      Subject: \(fact.subject)")
                    testResults.append("      Value: \(fact.value)")
                    testResults.append("      Confidence: \(String(format: "%.2f", fact.confidence))")
                }
            } else {
                testResults.append("   ❌ No facts extracted")
            }
            
            // TEST 2: Employment pattern
            testResults.append("\n📝 Test 2: Employment Pattern")
            let facts2 = await extractor.extractFacts(from: "I work at Google")
            if facts2.count > 0 {
                testResults.append("   ✅ Extracted \(facts2.count) fact(s)")
                for fact in facts2 {
                    testResults.append("      Subject: \(fact.subject)")
                    testResults.append("      Value: \(fact.value)")
                }
            } else {
                testResults.append("   ❌ No facts extracted")
            }
            
            // TEST 3: Employment with role
            testResults.append("\n📝 Test 3: Employment + Role")
            let facts3 = await extractor.extractFacts(from: "I work at Google as a Product Manager")
            if facts3.count > 0 {
                testResults.append("   ✅ Extracted \(facts3.count) fact(s)")
                for fact in facts3 {
                    testResults.append("      Subject: \(fact.subject)")
                    testResults.append("      Value: \(fact.value)")
                }
            } else {
                testResults.append("   ❌ No facts extracted")
            }
            
            // TEST 4: Location pattern
            testResults.append("\n📝 Test 4: Location Pattern")
            let facts4 = await extractor.extractFacts(from: "I live in San Francisco, California")
            if facts4.count > 0 {
                testResults.append("   ✅ Extracted \(facts4.count) fact(s)")
                for fact in facts4 {
                    testResults.append("      Subject: \(fact.subject)")
                    testResults.append("      Value: \(fact.value)")
                }
            } else {
                testResults.append("   ❌ No facts extracted")
            }
            
            // TEST 5: Conflict detection
            testResults.append("\n📝 Test 5: Fact Conflict Detection")
            let oldFacts = await extractor.extractFacts(from: "My favorite color is blue")
            let newFacts = await extractor.extractFacts(from: "My favorite color is green")
            let conflicts = await extractor.findConflictingFacts(newFacts: newFacts, oldFacts: oldFacts)
            
            if conflicts.count > 0 {
                testResults.append("   ✅ Found \(conflicts.count) conflict(s)")
                for conflict in conflicts {
                    testResults.append("      Subject: \(conflict.new.subject)")
                    testResults.append("      Old: \(conflict.old.value)")
                    testResults.append("      New: \(conflict.new.value)")
                }
            } else {
                testResults.append("   ❌ No conflicts found")
            }
            
            // TEST 6: No conflict (different subjects)
            testResults.append("\n📝 Test 6: No Conflict (Different Subjects)")
            let oldFacts6 = await extractor.extractFacts(from: "My favorite color is blue")
            let newFacts6 = await extractor.extractFacts(from: "I work at Google")
            let conflicts6 = await extractor.findConflictingFacts(newFacts: newFacts6, oldFacts: oldFacts6)
            
            if conflicts6.isEmpty {
                testResults.append("   ✅ Correctly detected no conflicts")
            } else {
                testResults.append("   ❌ False positive: found \(conflicts6.count) conflicts")
            }
            
            // TEST 7: Multiple patterns in one sentence
            testResults.append("\n📝 Test 7: Multiple Patterns")
            let facts7 = await extractor.extractFacts(from: "My name is John and I work at Microsoft")
            testResults.append("   Extracted \(facts7.count) fact(s)")
            for fact in facts7 {
                testResults.append("      \(fact.subject): \(fact.value)")
            }
            
            testResults.append("\n🎉 All entity extraction tests complete!")
            
            isLoading = false
        }
    }
}

#Preview {
    EntityExtractorTestView()
}
