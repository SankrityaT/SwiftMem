//
//  SwiftMemApp.swift
//  SwiftMem
//
//  Created by Sankritya Thakur on 12/7/25.
//

import SwiftUI

@main
struct SwiftMemApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationView {
                TestSuiteHomeView()
            }
        }
    }
}

struct TestSuiteHomeView: View {
    var body: some View {
        List {
            Section(header: Text("SwiftMem Test Suite")) {
                NavigationLink(destination: ComprehensiveTestView()) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Comprehensive Test Suite")
                            .font(.headline)
                        Text("Test all 8 phases: Embeddings, Relationships, Search, Decay, Profiles, Tags, Consolidation, Batch Ops")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                NavigationLink(destination: RileyBrooksTestView()) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Riley Brooks Test")
                            .font(.headline)
                        Text("Real-world test with 433 memories + Groq AI")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                NavigationLink(destination: BenchmarkResultsView()) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Benchmark Results")
                            .font(.headline)
                        Text("Performance benchmarks and metrics")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("SwiftMem Tests")
    }
}
