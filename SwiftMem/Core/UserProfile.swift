//
//  UserProfile.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation

/// User profile separating static (core facts) from dynamic (episodic) memories
public struct UserProfile: Codable, Equatable {
    public let userId: String
    public var staticMemories: [UUID]  // IDs of static memory nodes
    public var dynamicMemories: [UUID] // IDs of dynamic memory nodes
    public var preferences: [String: String]
    public var metadata: ProfileMetadata
    
    public init(
        userId: String,
        staticMemories: [UUID] = [],
        dynamicMemories: [UUID] = [],
        preferences: [String: String] = [:],
        metadata: ProfileMetadata = ProfileMetadata()
    ) {
        self.userId = userId
        self.staticMemories = staticMemories
        self.dynamicMemories = dynamicMemories
        self.preferences = preferences
        self.metadata = metadata
    }
}

/// Metadata for user profile
public struct ProfileMetadata: Codable, Equatable {
    public var createdAt: Date
    public var updatedAt: Date
    public var totalMemories: Int
    public var staticMemoryCount: Int
    public var dynamicMemoryCount: Int
    
    public init(
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        totalMemories: Int = 0,
        staticMemoryCount: Int = 0,
        dynamicMemoryCount: Int = 0
    ) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalMemories = totalMemories
        self.staticMemoryCount = staticMemoryCount
        self.dynamicMemoryCount = dynamicMemoryCount
    }
}

/// Manages user profiles and memory classification
public actor UserProfileManager {
    
    private var profiles: [String: UserProfile] = [:]
    private let memoryGraphStore: MemoryGraphStore
    
    public init(memoryGraphStore: MemoryGraphStore) {
        self.memoryGraphStore = memoryGraphStore
    }
    
    // MARK: - Profile Management
    
    /// Get or create user profile
    public func getProfile(userId: String) async -> UserProfile {
        if let profile = profiles[userId] {
            return profile
        }
        
        let newProfile = UserProfile(userId: userId)
        profiles[userId] = newProfile
        return newProfile
    }
    
    /// Update user profile
    public func updateProfile(_ profile: UserProfile) async {
        profiles[profile.userId] = profile
    }
    
    // MARK: - Memory Classification
    
    /// Classify memory as static or dynamic
    public func classifyMemory(_ memory: MemoryNode, userId: String) async -> Bool {
        // Static if:
        // 1. High importance (> 0.7)
        // 2. User confirmed
        // 3. Contains core facts (name, preferences, key info)
        
        let isStatic = memory.isStatic || containsCoreFactKeywords(memory.content)
        
        var profile = await getProfile(userId: userId)
        
        if isStatic {
            if !profile.staticMemories.contains(memory.id) {
                profile.staticMemories.append(memory.id)
                profile.metadata.staticMemoryCount += 1
            }
        } else {
            if !profile.dynamicMemories.contains(memory.id) {
                profile.dynamicMemories.append(memory.id)
                profile.metadata.dynamicMemoryCount += 1
            }
        }
        
        profile.metadata.totalMemories = profile.staticMemories.count + profile.dynamicMemories.count
        profile.metadata.updatedAt = Date()
        
        await updateProfile(profile)
        
        return isStatic
    }
    
    /// Check if content contains core fact keywords
    private func containsCoreFactKeywords(_ content: String) -> Bool {
        let coreKeywords = [
            "my name is", "i am", "i'm called",
            "i prefer", "i like", "i love", "i hate",
            "i work at", "i study at",
            "my birthday", "i was born",
            "i live in", "i'm from"
        ]
        
        let lowercased = content.lowercased()
        return coreKeywords.contains { lowercased.contains($0) }
    }
    
    // MARK: - Context Assembly
    
    /// Get context for a user (static + recent dynamic)
    public func getUserContext(userId: String, maxDynamic: Int = 10) async -> [MemoryNode] {
        let profile = await getProfile(userId: userId)
        
        var context: [MemoryNode] = []
        
        // Add all static memories
        for memoryId in profile.staticMemories {
            if let memory = await memoryGraphStore.getMemory(memoryId) {
                context.append(memory)
            }
        }
        
        // Add recent dynamic memories
        var dynamicMemories: [MemoryNode] = []
        for memoryId in profile.dynamicMemories {
            if let memory = await memoryGraphStore.getMemory(memoryId) {
                dynamicMemories.append(memory)
            }
        }
        
        // Sort by timestamp (most recent first) and take top N
        dynamicMemories.sort { $0.timestamp > $1.timestamp }
        context.append(contentsOf: dynamicMemories.prefix(maxDynamic))
        
        return context
    }
    
    /// Get static memories only
    public func getStaticMemories(userId: String) async -> [MemoryNode] {
        let profile = await getProfile(userId: userId)
        return await profile.staticMemories.asyncCompactMap { await memoryGraphStore.getMemory($0) }
    }
    
    /// Get dynamic memories only
    public func getDynamicMemories(userId: String, limit: Int? = nil) async -> [MemoryNode] {
        let profile = await getProfile(userId: userId)
        var memories = await profile.dynamicMemories.asyncCompactMap { await memoryGraphStore.getMemory($0) }
        
        // Sort by recency
        memories.sort { $0.timestamp > $1.timestamp }
        
        if let limit = limit {
            return Array(memories.prefix(limit))
        }
        
        return memories
    }
}

// MARK: - Async Helpers

extension Array {
    fileprivate func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var results: [T] = []
        for element in self {
            if let result = await transform(element) {
                results.append(result)
            }
        }
        return results
    }
}
