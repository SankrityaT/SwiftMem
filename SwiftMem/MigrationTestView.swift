//
//  MigrationTestView.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-25.
//

import SwiftUI

struct MigrationTestView: View {
    @State private var logs: [String] = []
    @State private var isRunning = false
    @State private var memoryCount = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("SwiftMem Migration Test")
                .font(.title)
                .bold()
            
            Text("Memories: \(memoryCount)")
                .font(.headline)
            
            Button("Run Migration Test") {
                Task {
                    await runMigrationTest()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
            
            Button("Clear Database") {
                Task {
                    await clearDatabase()
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRunning)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                        Text(log)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
        }
        .padding()
    }
    
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
    }
    
    private func runMigrationTest() async {
        isRunning = true
        logs.removeAll()
        
        log("🚀 Starting migration test...")
        
        do {
            // Initialize SwiftMem
            log("📦 Initializing SwiftMem...")
            let api = SwiftMemAPI.shared
            try await api.initialize()
            log("✅ SwiftMem initialized")
            
            // Test data - simulating SeeMeUI migration
            let testMemories = [
                ("User profile", "John is a 25-year-old male", 1.0),
                ("Goal 1", "Goal: Improve mental health", 1.0),
                ("Goal 2", "Goal: Build better relationships", 1.0),
                ("Goal 3", "Goal: Career growth", 1.0),
                ("Life areas", "Life Area Ratings (1-10 scale):\n- Health: 7/10\n- Career: 8/10", 0.8),
                ("Session 1", "Intro Session: Discussed goals and aspirations", 0.9),
                ("Session 2", "Weekly Check-in: Made progress on health goals", 0.9),
                ("Journal 1", "Today was a good day. I felt productive.", 0.8),
                ("Journal 2", "Struggled with anxiety today but managed to cope.", 0.8),
                ("Focus area", "Focus Area: Mental Health / Current: Stressed / Target: Calm", 0.8)
            ]
            
            log("📝 Inserting \(testMemories.count) test memories...")
            
            for (index, memory) in testMemories.enumerated() {
                let (type, content, importance) = memory
                log("  [\(index + 1)/\(testMemories.count)] Inserting: \(type)")
                
                try await api.add(
                    content: content,
                    userId: "test-user-123",
                    metadata: ["importance": String(importance)],
                    containerTags: ["type:\(type)"],
                    skipRelationships: true  // Skip during bulk insert
                )
                
                log("  ✅ Inserted: \(type)")
            }
            
            log("🔍 Verifying memories...")
            let allMemories = try await api.getAllMemories()
            memoryCount = allMemories.count
            log("✅ Found \(allMemories.count) memories in database")
            
            if allMemories.count == testMemories.count {
                log("🎉 SUCCESS: All memories inserted correctly!")
            } else {
                log("⚠️ WARNING: Expected \(testMemories.count) but found \(allMemories.count)")
            }
            
        } catch {
            log("❌ ERROR: \(error.localizedDescription)")
            log("   Details: \(error)")
        }
        
        isRunning = false
    }
    
    private func clearDatabase() async {
        isRunning = true
        log("🗑️ Clearing database...")
        
        do {
            await SwiftMemAPI.shared.reset()
            log("✅ Database cleared")
            memoryCount = 0
        } catch {
            log("❌ Error clearing database: \(error)")
        }
        
        isRunning = false
    }
}

#Preview {
    MigrationTestView()
}
