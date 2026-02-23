//
//  UserProfile.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation

/// User profile separating static (core facts) from dynamic (episodic) memories
/// Enhanced with dynamic context tracking (Supermemory-style)
public struct UserProfile: Codable, Equatable {
    public let userId: String
    public var staticMemories: [UUID]  // IDs of static memory nodes
    public var dynamicMemories: [UUID] // IDs of dynamic memory nodes
    public var preferences: [String: String]
    public var metadata: ProfileMetadata
    
    /// Dynamic context items - "currently working on", "recent challenges", etc.
    /// This is the RAM layer that's always included in context
    public var dynamicContext: [DynamicContextItem]
    
    public init(
        userId: String,
        staticMemories: [UUID] = [],
        dynamicMemories: [UUID] = [],
        preferences: [String: String] = [:],
        metadata: ProfileMetadata = ProfileMetadata(),
        dynamicContext: [DynamicContextItem] = []
    ) {
        self.userId = userId
        self.staticMemories = staticMemories
        self.dynamicMemories = dynamicMemories
        self.preferences = preferences
        self.metadata = metadata
        self.dynamicContext = dynamicContext
    }
    
    /// Get active dynamic context (sorted by importance and recency)
    public func getActiveDynamicContext(limit: Int = 5) -> [DynamicContextItem] {
        let activeItems = dynamicContext.filter { $0.isActive }
        return activeItems
            .sorted { item1, item2 in
                // Sort by importance first, then by recency
                if item1.importance != item2.importance {
                    return item1.importance > item2.importance
                }
                return item1.lastMentioned > item2.lastMentioned
            }
            .prefix(limit)
            .map { $0 }
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

/// Dynamic context item - tracks "currently working on" / "recent endeavors"
/// Similar to Supermemory's dynamic profile concept
public struct DynamicContextItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var content: String
    public var category: DynamicContextCategory
    public var startDate: Date
    public var lastMentioned: Date
    public var mentionCount: Int
    public var importance: Float  // 0.0 - 1.0
    public var isActive: Bool
    
    public init(
        id: UUID = UUID(),
        content: String,
        category: DynamicContextCategory,
        startDate: Date = Date(),
        lastMentioned: Date = Date(),
        mentionCount: Int = 1,
        importance: Float = 0.5,
        isActive: Bool = true
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.startDate = startDate
        self.lastMentioned = lastMentioned
        self.mentionCount = mentionCount
        self.importance = importance
        self.isActive = isActive
    }
}

/// Categories for dynamic context
public enum DynamicContextCategory: String, Codable, CaseIterable {
    case currentProject = "currently_working_on"
    case recentChallenge = "recent_challenge"
    case ongoingGoal = "ongoing_goal"
    case recentMood = "recent_mood"
    case activeInterest = "active_interest"
    case temporaryFocus = "temporary_focus"
}

/// Manages user profiles and memory classification
/// Enhanced with RAM-like caching for instant access (Supermemory-style)
public actor UserProfileManager {
    
    // RAM-like cache - profiles stay in memory for instant access
    private var profiles: [String: UserProfile] = [:]
    private var profileCache: [String: (profile: UserProfile, lastAccessed: Date)] = [:]
    private let memoryGraphStore: MemoryGraphStore
    
    // Cache settings
    private let maxCacheSize = 10
    private let cacheExpirySeconds: TimeInterval = 3600 // 1 hour
    
    public init(memoryGraphStore: MemoryGraphStore) {
        self.memoryGraphStore = memoryGraphStore
    }
    
    // MARK: - Profile Management (RAM-like)
    
    /// Get or create user profile (cached for instant access)
    public func getProfile(userId: String) async -> UserProfile {
        // Check RAM cache first
        if let cached = profileCache[userId] {
            let age = Date().timeIntervalSince(cached.lastAccessed)
            if age < cacheExpirySeconds {
                // Update access time
                profileCache[userId] = (cached.profile, Date())
                return cached.profile
            }
        }
        
        // Not in cache or expired - load from memory
        if let profile = profiles[userId] {
            cacheProfile(profile)
            return profile
        }
        
        // Create new profile
        let newProfile = UserProfile(userId: userId)
        profiles[userId] = newProfile
        cacheProfile(newProfile)
        return newProfile
    }
    
    /// Update user profile (updates both storage and cache)
    public func updateProfile(_ profile: UserProfile) async {
        profiles[profile.userId] = profile
        cacheProfile(profile)
    }
    
    /// Cache a profile in RAM for instant access
    private func cacheProfile(_ profile: UserProfile) {
        // Evict oldest if cache is full
        if profileCache.count >= maxCacheSize {
            if let oldestKey = profileCache.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })?.key {
                profileCache.removeValue(forKey: oldestKey)
            }
        }
        
        profileCache[profile.userId] = (profile, Date())
    }
    
    /// Clear cache (useful for memory pressure)
    public func clearCache() {
        profileCache.removeAll()
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
    /// Uses container tags to filter by user since profiles are in-memory only
    public func getUserContext(userId: String, maxDynamic: Int = 10) async -> [MemoryNode] {
        // Query ALL memories and filter by user tag (profiles are not persisted)
        let allMemories = await memoryGraphStore.getAllMemories()
        let userTag = "user:\(userId)"

        // Filter memories that belong to this user
        let userMemories = allMemories.filter { $0.containerTags.contains(userTag) }

        var context: [MemoryNode] = []
        var dynamicMemories: [MemoryNode] = []

        for memory in userMemories {
            if memory.isStatic {
                context.append(memory)
            } else {
                dynamicMemories.append(memory)
            }
        }

        // Sort dynamic by timestamp (most recent first) and take top N
        dynamicMemories.sort { $0.timestamp > $1.timestamp }
        context.append(contentsOf: dynamicMemories.prefix(maxDynamic))

        return context
    }
    
    /// Get static memories only
    public func getStaticMemories(userId: String) async -> [MemoryNode] {
        let allMemories = await memoryGraphStore.getAllMemories()
        let userTag = "user:\(userId)"
        return allMemories.filter { $0.containerTags.contains(userTag) && $0.isStatic }
    }

    /// Get dynamic memories only
    public func getDynamicMemories(userId: String, limit: Int? = nil) async -> [MemoryNode] {
        let allMemories = await memoryGraphStore.getAllMemories()
        let userTag = "user:\(userId)"
        var memories = allMemories.filter { $0.containerTags.contains(userTag) && !$0.isStatic }

        // Sort by recency
        memories.sort { $0.timestamp > $1.timestamp }

        if let limit = limit {
            return Array(memories.prefix(limit))
        }

        return memories
    }
    
    // MARK: - Dynamic Context Management (Supermemory-style)
    
    /// Add or update dynamic context item (e.g., "currently working on X")
    public func updateDynamicContext(
        userId: String,
        content: String,
        category: DynamicContextCategory,
        importance: Float = 0.7
    ) async {
        var profile = await getProfile(userId: userId)
        
        // Check if similar context already exists
        if let existingIndex = profile.dynamicContext.firstIndex(where: {
            $0.category == category && $0.content.lowercased().contains(content.lowercased().prefix(20))
        }) {
            // Update existing
            profile.dynamicContext[existingIndex].lastMentioned = Date()
            profile.dynamicContext[existingIndex].mentionCount += 1
            profile.dynamicContext[existingIndex].importance = max(profile.dynamicContext[existingIndex].importance, importance)
        } else {
            // Add new
            let newItem = DynamicContextItem(
                content: content,
                category: category,
                importance: importance
            )
            profile.dynamicContext.append(newItem)
        }
        
        // Prune old inactive items (older than 7 days and low importance)
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        profile.dynamicContext = profile.dynamicContext.filter { item in
            item.lastMentioned > sevenDaysAgo || item.importance > 0.6
        }
        
        await updateProfile(profile)
    }
    
    /// Mark dynamic context item as inactive
    public func deactivateDynamicContext(userId: String, itemId: UUID) async {
        var profile = await getProfile(userId: userId)
        
        if let index = profile.dynamicContext.firstIndex(where: { $0.id == itemId }) {
            profile.dynamicContext[index].isActive = false
        }
        
        await updateProfile(profile)
    }
    
    /// Get formatted dynamic context string for AI prompts
    public func getDynamicContextString(userId: String, limit: Int = 5) async -> String {
        let profile = await getProfile(userId: userId)
        let activeContext = profile.getActiveDynamicContext(limit: limit)
        
        guard !activeContext.isEmpty else {
            return ""
        }
        
        var contextLines: [String] = []
        
        for item in activeContext {
            let categoryLabel = item.category.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
            contextLines.append("- \(categoryLabel): \(item.content)")
        }
        
        return """
        ## Dynamic Context (Recent Activity):
        \(contextLines.joined(separator: "\n"))
        """
    }
    
    /// Auto-extract dynamic context from recent memories
    public func extractDynamicContext(userId: String) async {
        // Get recent memories (last 3 days)
        let recentMemories = await getDynamicMemories(userId: userId, limit: 20)
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 3600)
        let veryRecent = recentMemories.filter { $0.timestamp > threeDaysAgo }
        
        // Extract patterns
        for memory in veryRecent {
            let content = memory.content.lowercased()
            
            // Detect "working on" patterns
            if content.contains("working on") || content.contains("focusing on") || content.contains("building") {
                let extracted = extractPhrase(from: memory.content, after: ["working on", "focusing on", "building"])
                if !extracted.isEmpty {
                    await updateDynamicContext(
                        userId: userId,
                        content: extracted,
                        category: .currentProject,
                        importance: 0.8
                    )
                }
            }
            
            // Detect challenges
            if content.contains("struggling with") || content.contains("challenge") || content.contains("difficult") {
                let extracted = extractPhrase(from: memory.content, after: ["struggling with", "challenge", "difficult"])
                if !extracted.isEmpty {
                    await updateDynamicContext(
                        userId: userId,
                        content: extracted,
                        category: .recentChallenge,
                        importance: 0.7
                    )
                }
            }
            
            // Detect mood patterns
            if content.contains("feeling") || content.contains("i feel") {
                let extracted = extractPhrase(from: memory.content, after: ["feeling", "i feel"])
                if !extracted.isEmpty {
                    await updateDynamicContext(
                        userId: userId,
                        content: extracted,
                        category: .recentMood,
                        importance: 0.6
                    )
                }
            }
        }
    }
    
    /// Extract phrase after trigger words
    private func extractPhrase(from text: String, after triggers: [String]) -> String {
        let lowercased = text.lowercased()
        
        for trigger in triggers {
            if let range = lowercased.range(of: trigger) {
                let startIndex = range.upperBound
                let remaining = String(text[startIndex...]).trimmingCharacters(in: .whitespaces)
                
                // Take up to first sentence or 100 chars
                if let endIndex = remaining.firstIndex(of: ".") ?? remaining.firstIndex(of: ",") {
                    return String(remaining[..<endIndex]).trimmingCharacters(in: .whitespaces)
                } else {
                    return String(remaining.prefix(100)).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        return ""
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
