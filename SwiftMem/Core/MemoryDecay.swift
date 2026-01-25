//
//  MemoryDecay.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation

/// Manages memory decay and automatic forgetting
public actor MemoryDecay {
    
    private let memoryGraphStore: MemoryGraphStore
    private let config: SwiftMemConfig
    
    public init(memoryGraphStore: MemoryGraphStore, config: SwiftMemConfig) {
        self.memoryGraphStore = memoryGraphStore
        self.config = config
    }
    
    // MARK: - Decay Processing
    
    /// Update confidence scores for all memories based on decay
    public func processDecay() async throws {
        let allMemories = await memoryGraphStore.getAllMemories()
        
        for memory in allMemories {
            let decayedConfidence = calculateDecayedConfidence(memory: memory)
            
            if decayedConfidence != memory.confidence {
                var updatedMemory = memory
                updatedMemory.confidence = decayedConfidence
                try await memoryGraphStore.updateMemory(updatedMemory)
            }
        }
    }
    
    /// Calculate decayed confidence for a memory
    private func calculateDecayedConfidence(memory: MemoryNode) -> Float {
        let currentDate = Date()
        let daysSinceCreation = currentDate.timeIntervalSince(memory.timestamp) / 86400
        
        // Static memories decay slower
        let decayRate: Float = memory.isStatic ? 0.01 : 0.05
        
        // Access boosts confidence
        let accessBoost = min(Float(memory.metadata.accessCount) * 0.05, 0.3)
        
        // Calculate decay
        let ageFactor = exp(-decayRate * Float(daysSinceCreation))
        let decayedConfidence = memory.confidence * ageFactor + accessBoost
        
        return max(min(decayedConfidence, 1.0), 0.0)
    }
    
    // MARK: - Forgetting
    
    /// Remove low-confidence memories (automatic forgetting)
    public func pruneMemories(threshold: Float = 0.1) async throws -> Int {
        let allMemories = await memoryGraphStore.getAllMemories()
        var prunedCount = 0
        
        for memory in allMemories {
            let effectiveConfidence = memory.effectiveConfidence()
            
            // Don't prune static memories or user-confirmed memories
            if !memory.isStatic && !memory.metadata.userConfirmed && effectiveConfidence < threshold {
                // Archive instead of delete (for potential recovery)
                try await archiveMemory(memory)
                prunedCount += 1
            }
        }
        
        return prunedCount
    }
    
    /// Archive a memory (soft delete)
    private func archiveMemory(_ memory: MemoryNode) async throws {
        // Mark as forgotten but keep in database
        // This would be implemented in MemoryGraphStore
    }
    
    // MARK: - Scheduled Decay
    
    /// Run decay process on a schedule
    public func startScheduledDecay(interval: TimeInterval = 86400) async {
        // Run decay every 24 hours
        while true {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            try? await processDecay()
            
            // Prune every 7 days
            if Int(interval) % (86400 * 7) == 0 {
                let pruned = try? await pruneMemories()
                print("Pruned \(pruned ?? 0) low-confidence memories")
            }
        }
    }
}
