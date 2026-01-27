//
//  GoalMemoryManager.swift
//  SwiftMem
//
//  Goal-centric memory organization for life coaching
//  Links memories to goals, tracks progress/blockers
//

import Foundation

/// Manages goal-centric memory organization
/// Specifically designed for life coaching applications
public actor GoalMemoryManager {

    // MARK: - Storage

    /// All goal clusters indexed by goal ID
    private var goalClusters: [UUID: GoalCluster] = [:]

    /// Mapping from memory ID to goal IDs it's linked to
    private var memoryToGoals: [UUID: Set<UUID>] = [:]

    // MARK: - Keywords for Classification

    /// Keywords indicating progress
    private let progressKeywords = [
        "did", "completed", "finished", "achieved", "made progress",
        "went to", "exercised", "worked on", "succeeded", "accomplished",
        "got", "reached", "hit", "met", "passed", "won", "improved",
        "started", "began", "initiated", "launched", "created"
    ]

    /// Keywords indicating blockers/obstacles
    private let blockerKeywords = [
        "couldn't", "didn't", "failed", "struggled", "hard to",
        "difficult", "skipped", "missed", "can't", "unable",
        "stuck", "blocked", "frustrated", "overwhelmed", "tired",
        "busy", "no time", "procrastinated", "avoided", "forgot"
    ]

    /// Keywords indicating motivation/reasons
    private let motivationKeywords = [
        "want to", "because", "so that", "in order to", "goal is",
        "dream of", "hope to", "aspire", "wish", "motivated by",
        "reason", "why", "purpose", "important to me", "matters"
    ]

    /// Keywords indicating goals
    private let goalKeywords = [
        "goal", "want to", "plan to", "trying to", "working on",
        "aim to", "hope to", "need to", "going to", "will",
        "resolution", "objective", "target", "dream", "aspire"
    ]

    // MARK: - Public API

    /// Register a new goal
    public func registerGoal(
        memoryId: UUID,
        content: String,
        userId: String
    ) -> GoalCluster {
        let cluster = GoalCluster(
            goalMemoryId: memoryId,
            goalContent: content,
            userId: userId
        )

        goalClusters[cluster.id] = cluster
        memoryToGoals[memoryId, default: []].insert(cluster.id)

        return cluster
    }

    /// Link a memory to relevant goals
    public func linkMemoryToGoals(
        memoryId: UUID,
        content: String,
        emotionalValence: EmotionalValence,
        userId: String
    ) async -> [GoalLinkResult] {
        var results: [GoalLinkResult] = []

        // Get all goals for this user
        let userGoals = goalClusters.values.filter { $0.userId == userId }

        for goal in userGoals {
            // Calculate relevance
            let relevance = calculateGoalRelevance(content: content, goal: goal)

            if relevance > 0.3 {
                // Classify the relationship type
                let relationshipType = classifyGoalRelationship(content)

                // Update the cluster
                var updatedCluster = goal
                switch relationshipType {
                case .progressToward:
                    updatedCluster.progressMemoryIds.append(memoryId)
                case .blockerFor:
                    updatedCluster.blockerMemoryIds.append(memoryId)
                case .motivationFor:
                    updatedCluster.motivationMemoryIds.append(memoryId)
                case .insightAbout:
                    updatedCluster.insightMemoryIds.append(memoryId)
                default:
                    break
                }

                // Track emotional trajectory
                updatedCluster.emotionalTrajectory.append((Date(), emotionalValence))

                goalClusters[goal.id] = updatedCluster
                memoryToGoals[memoryId, default: []].insert(goal.id)

                results.append(GoalLinkResult(
                    goalId: goal.id,
                    memoryId: memoryId,
                    relationshipType: relationshipType,
                    relevance: relevance
                ))
            }
        }

        return results
    }

    /// Check if content represents a goal
    public func isGoalContent(_ content: String) -> Bool {
        let lower = content.lowercased()

        for keyword in goalKeywords {
            if lower.contains(keyword) {
                return true
            }
        }

        return false
    }

    /// Get goal cluster by ID
    public func getGoalCluster(_ goalId: UUID) -> GoalCluster? {
        return goalClusters[goalId]
    }

    /// Get all goals for a user
    public func getGoalsForUser(_ userId: String) -> [GoalCluster] {
        return goalClusters.values.filter { $0.userId == userId }
    }

    /// Get goals linked to a memory
    public func getGoalsForMemory(_ memoryId: UUID) -> [GoalCluster] {
        guard let goalIds = memoryToGoals[memoryId] else { return [] }
        return goalIds.compactMap { goalClusters[$0] }
    }

    /// Generate coaching context for a goal
    public func generateCoachingContext(for goalId: UUID) -> CoachingContext? {
        guard let cluster = goalClusters[goalId] else { return nil }

        return CoachingContext(
            goal: cluster.goalContent,
            goalCreatedAt: cluster.createdAt,
            progressCount: cluster.progressMemoryIds.count,
            blockerCount: cluster.blockerMemoryIds.count,
            motivationCount: cluster.motivationMemoryIds.count,
            emotionalTrend: analyzeEmotionalTrend(cluster.emotionalTrajectory),
            recentEmotions: cluster.emotionalTrajectory.suffix(5).map { $0.1 }
        )
    }

    /// Format coaching context as string for LLM
    public func formatCoachingContextString(for goalId: UUID) -> String? {
        guard let context = generateCoachingContext(for: goalId),
              let cluster = goalClusters[goalId] else { return nil }

        var output = """
        GOAL: \(context.goal)
        Created: \(formatDate(context.goalCreatedAt))

        """

        if context.progressCount > 0 {
            output += """
            PROGRESS: \(context.progressCount) positive updates recorded

            """
        }

        if context.blockerCount > 0 {
            output += """
            CHALLENGES: \(context.blockerCount) obstacles mentioned

            """
        }

        if let trend = context.emotionalTrend {
            output += """
            EMOTIONAL TREND: \(trend.description)

            """
        }

        return output
    }

    // MARK: - Goal Relevance

    private func calculateGoalRelevance(content: String, goal: GoalCluster) -> Float {
        let contentWords = Set(content.lowercased().components(separatedBy: .whitespacesAndNewlines))
        let goalWords = Set(goal.goalContent.lowercased().components(separatedBy: .whitespacesAndNewlines))

        // Remove common words
        let stopWords = Set(["the", "a", "an", "is", "are", "was", "were", "to", "i", "my", "me", "and", "or", "but", "in", "on", "at", "for", "of"])
        let contentFiltered = contentWords.subtracting(stopWords)
        let goalFiltered = goalWords.subtracting(stopWords)

        // Calculate Jaccard similarity
        let intersection = contentFiltered.intersection(goalFiltered)
        let union = contentFiltered.union(goalFiltered)

        guard !union.isEmpty else { return 0 }

        let baseSimilarity = Float(intersection.count) / Float(union.count)

        // Boost if contains goal-related keywords
        var boost: Float = 0
        let lower = content.lowercased()

        if progressKeywords.contains(where: { lower.contains($0) }) {
            boost += 0.15
        }
        if blockerKeywords.contains(where: { lower.contains($0) }) {
            boost += 0.15
        }
        if motivationKeywords.contains(where: { lower.contains($0) }) {
            boost += 0.1
        }

        return min(baseSimilarity + boost, 1.0)
    }

    // MARK: - Relationship Classification

    private func classifyGoalRelationship(_ content: String) -> EnhancedRelationType {
        let lower = content.lowercased()

        // Check progress first (positive updates)
        for keyword in progressKeywords {
            if lower.contains(keyword) {
                return .progressToward
            }
        }

        // Check blockers
        for keyword in blockerKeywords {
            if lower.contains(keyword) {
                return .blockerFor
            }
        }

        // Check motivation
        for keyword in motivationKeywords {
            if lower.contains(keyword) {
                return .motivationFor
            }
        }

        // Default to related
        return .relatedTo
    }

    // MARK: - Emotional Analysis

    private func analyzeEmotionalTrend(_ trajectory: [(Date, EmotionalValence)]) -> EmotionalTrend? {
        guard trajectory.count >= 2 else { return nil }

        // Sort by date
        let sorted = trajectory.sorted { $0.0 < $1.0 }

        // Calculate average sentiment for first and second half
        let midpoint = sorted.count / 2
        let firstHalf = sorted.prefix(midpoint)
        let secondHalf = sorted.suffix(sorted.count - midpoint)

        let firstAvg = firstHalf.map { $0.1.sentiment }.reduce(0, +) / Float(firstHalf.count)
        let secondAvg = secondHalf.map { $0.1.sentiment }.reduce(0, +) / Float(secondHalf.count)

        let change = secondAvg - firstAvg

        // Determine trend
        if change > 0.2 {
            return .improving
        } else if change < -0.2 {
            return .declining
        } else {
            return .stable
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - Persistence

    /// Export all goal clusters for persistence
    public func exportClusters() -> [GoalCluster] {
        Array(goalClusters.values)
    }

    /// Import goal clusters from persistence
    public func importClusters(_ clusters: [GoalCluster]) {
        for cluster in clusters {
            goalClusters[cluster.id] = cluster
            memoryToGoals[cluster.goalMemoryId, default: []].insert(cluster.id)

            // Rebuild memory to goals mapping
            for memoryId in cluster.progressMemoryIds {
                memoryToGoals[memoryId, default: []].insert(cluster.id)
            }
            for memoryId in cluster.blockerMemoryIds {
                memoryToGoals[memoryId, default: []].insert(cluster.id)
            }
            for memoryId in cluster.motivationMemoryIds {
                memoryToGoals[memoryId, default: []].insert(cluster.id)
            }
            for memoryId in cluster.insightMemoryIds {
                memoryToGoals[memoryId, default: []].insert(cluster.id)
            }
        }
    }

    /// Clear all data
    public func clear() {
        goalClusters.removeAll()
        memoryToGoals.removeAll()
    }
}

// MARK: - Supporting Types

/// Result of linking a memory to a goal
public struct GoalLinkResult: Equatable {
    public let goalId: UUID
    public let memoryId: UUID
    public let relationshipType: EnhancedRelationType
    public let relevance: Float
}

/// Emotional trend over time
public enum EmotionalTrend: String, Codable {
    case improving
    case stable
    case declining

    public var description: String {
        switch self {
        case .improving: return "Positive trend - emotions improving over time"
        case .stable: return "Stable - consistent emotional state"
        case .declining: return "Challenging period - emotions trending negative"
        }
    }
}

/// Coaching context for a goal
public struct CoachingContext {
    public let goal: String
    public let goalCreatedAt: Date
    public let progressCount: Int
    public let blockerCount: Int
    public let motivationCount: Int
    public let emotionalTrend: EmotionalTrend?
    public let recentEmotions: [EmotionalValence]

    /// Generate a summary string
    public var summary: String {
        var parts: [String] = []

        parts.append("Goal: \(goal)")

        if progressCount > 0 {
            parts.append("\(progressCount) progress updates")
        }

        if blockerCount > 0 {
            parts.append("\(blockerCount) challenges faced")
        }

        if let trend = emotionalTrend {
            parts.append("Emotional trend: \(trend.rawValue)")
        }

        return parts.joined(separator: " | ")
    }
}

// MARK: - Goal-Based Retrieval

extension GoalMemoryManager {
    /// Get memories related to a goal, organized by type
    public func getOrganizedMemories(for goalId: UUID) -> OrganizedGoalMemories? {
        guard let cluster = goalClusters[goalId] else { return nil }

        return OrganizedGoalMemories(
            goalId: goalId,
            goalContent: cluster.goalContent,
            progressIds: cluster.progressMemoryIds,
            blockerIds: cluster.blockerMemoryIds,
            motivationIds: cluster.motivationMemoryIds,
            insightIds: cluster.insightMemoryIds
        )
    }

    /// Find goals that might be relevant to a query
    public func findRelevantGoals(query: String, userId: String, topK: Int = 3) -> [GoalCluster] {
        let userGoals = goalClusters.values.filter { $0.userId == userId }

        let scored = userGoals.map { goal -> (GoalCluster, Float) in
            let relevance = calculateGoalRelevance(content: query, goal: goal)
            return (goal, relevance)
        }

        return scored
            .filter { $0.1 > 0.2 }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
    }
}

/// Organized memories for a goal
public struct OrganizedGoalMemories {
    public let goalId: UUID
    public let goalContent: String
    public let progressIds: [UUID]
    public let blockerIds: [UUID]
    public let motivationIds: [UUID]
    public let insightIds: [UUID]

    public var totalRelatedMemories: Int {
        progressIds.count + blockerIds.count + motivationIds.count + insightIds.count
    }
}
