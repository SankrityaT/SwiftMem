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
    
    /// Calculate decayed confidence for a memory (Supermemory-style temporal validity)
    private func calculateDecayedConfidence(memory: MemoryNode) -> Float {
        let currentDate = Date()
        let daysSinceCreation = currentDate.timeIntervalSince(memory.timestamp) / 86400
        
        // Different decay rates based on memory type (Supermemory approach)
        let decayRate: Float
        if memory.isStatic {
            // Static memories (core facts) barely decay
            decayRate = 0.001  // 10x slower than before
        } else {
            // Episodic memories decay more aggressively
            // "10th grade exam" should fade quickly
            decayRate = 0.08  // More aggressive than before (was 0.05)
        }
        
        // Access boosts confidence (recent access = still relevant)
        let accessBoost = min(Float(memory.metadata.accessCount) * 0.05, 0.3)
        
        // Importance boost (high importance = slower decay)
        let importanceBoost = memory.metadata.importance * 0.2
        
        // Calculate decay with exponential falloff
        let ageFactor = exp(-decayRate * Float(daysSinceCreation))
        var decayedConfidence = memory.confidence * ageFactor + accessBoost + importanceBoost
        
        // Temporal validity check (Supermemory concept)
        // If memory has temporal markers, check if it's still valid
        if let eventDate = memory.eventDate {
            let daysSinceEvent = currentDate.timeIntervalSince(eventDate) / 86400
            
            // Events older than 30 days decay faster (unless high importance)
            if daysSinceEvent > 30 && memory.metadata.importance < 0.7 {
                let temporalDecay = exp(-0.1 * Float(daysSinceEvent - 30))
                decayedConfidence *= temporalDecay
            }
        }
        
        return max(min(decayedConfidence, 1.0), 0.0)
    }
    
    // MARK: - Forgetting
    
    /// Remove low-confidence memories (automatic forgetting - Supermemory-style)
    public func pruneMemories(threshold: Float = 0.1) async throws -> Int {
        let allMemories = await memoryGraphStore.getAllMemories()
        var prunedCount = 0
        
        for memory in allMemories {
            let effectiveConfidence = memory.effectiveConfidence()
            
            // Never prune:
            // 1. Static memories (core facts)
            // 2. User-confirmed memories
            // 3. High-importance memories (> 0.7)
            // 4. Recently accessed memories (accessed in last 7 days)
            let recentlyAccessed: Bool = {
                if let lastAccess = memory.metadata.lastAccessed {
                    return Date().timeIntervalSince(lastAccess) < (7 * 24 * 3600)
                }
                return false
            }()
            
            let shouldPreserve = memory.isStatic ||
                                memory.metadata.userConfirmed ||
                                memory.metadata.importance > 0.7 ||
                                recentlyAccessed
            
            if !shouldPreserve && effectiveConfidence < threshold {
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
