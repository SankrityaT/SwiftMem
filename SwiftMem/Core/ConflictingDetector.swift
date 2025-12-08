//
//  ConflictingMemory.swift
//  SwiftMem
//
//  Created by Sankritya Thakur on 12/7/25.
//


//
//  ConflictDetector.swift
//  SwiftMem - Knowledge Update Detection
//
//  Detects when new memories conflict with existing ones and suggests relationship types
//

import Foundation

// MARK: - Conflict Types

/// Represents a detected conflict between memories
public struct ConflictingMemory: Equatable {
    /// The existing (old) memory
    public let oldNode: Node
    
    /// The new memory being added
    public let newNode: Node
    
    /// Semantic similarity score (0.0 to 1.0)
    public let similarity: Float
    
    /// Type of conflict detected
    public let conflictType: ConflictType
    
    /// Confidence in the conflict detection (0.0 to 1.0)
    public let confidence: Float
    
    /// Why this was flagged as a conflict
    public let reason: String
}

/// Types of conflicts between memories
public enum ConflictType: String, Codable {
    /// New information replaces old (e.g., "color is green" vs "color is blue")
    case updates
    
    /// New information adds detail to existing (e.g., "works at Google" + "is a PM at Google")
    case extends
    
    /// New information completely invalidates old (stronger than updates)
    case supersedes
    
    /// Information is contradictory and unclear which is correct
    case contradicts
    
    /// Same information, just rephrased (duplicate)
    case duplicate
}

// MARK: - Conflict Detection Configuration

public struct ConflictDetectionConfig {
    /// Minimum similarity to consider as potential conflict (0.0 to 1.0)
    public let similarityThreshold: Float
    
    /// Only check memories within this time window (nil = all time)
    public let timeWindow: TimeInterval?
    
    /// Memory types to check for conflicts
    public let memoryTypesToCheck: Set<MemoryType>
    
    /// Minimum confidence to report a conflict (0.0 to 1.0)
    public let minConfidence: Float
    
    /// Maximum number of candidates to check (for performance)
    public let maxCandidates: Int
    
    public init(
        similarityThreshold: Float = 0.75,
        timeWindow: TimeInterval? = nil,
        memoryTypesToCheck: Set<MemoryType> = [.semantic, .procedural, .goal],
        minConfidence: Float = 0.6,
        maxCandidates: Int = 100
    ) {
        self.similarityThreshold = similarityThreshold
        self.timeWindow = timeWindow
        self.memoryTypesToCheck = memoryTypesToCheck
        self.minConfidence = minConfidence
        self.maxCandidates = maxCandidates
    }
    
    public static let `default` = ConflictDetectionConfig()
    
    /// Strict config for production (fewer false positives)
    public static let strict = ConflictDetectionConfig(
        similarityThreshold: 0.85,
        minConfidence: 0.75
    )
    
    /// Aggressive config for testing (catch everything)
    public static let aggressive = ConflictDetectionConfig(
        similarityThreshold: 0.65,
        minConfidence: 0.5
    )
}

// MARK: - Conflict Detector

/// Detects conflicts between new and existing memories
public actor ConflictDetector {
    private let graphStore: GraphStore
    private let vectorStore: VectorStore
    private let embeddingEngine: EmbeddingEngine
    private let config: ConflictDetectionConfig
    
    public init(
        graphStore: GraphStore,
        vectorStore: VectorStore,
        embeddingEngine: EmbeddingEngine,
        config: ConflictDetectionConfig = .default
    ) {
        self.graphStore = graphStore
        self.vectorStore = vectorStore
        self.embeddingEngine = embeddingEngine
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Detect conflicts for a new memory before storing it
    public func detectConflicts(for newNode: Node) async throws -> [ConflictingMemory] {
        // Only check certain memory types
        guard config.memoryTypesToCheck.contains(newNode.type) else {
            return []
        }
        
        // Get candidates to check
        let candidates = try await getCandidates(for: newNode)
        
        // Generate embedding for new node
        let newEmbedding = try await embeddingEngine.embed(newNode.content)
        
        // Check each candidate
        var conflicts: [ConflictingMemory] = []
        
        for candidate in candidates {
            // Skip self
            guard candidate.id != newNode.id else { continue }
            
            // Calculate similarity
            guard let candidateEmbedding = try await vectorStore.getVector(for: candidate.id) else {
                continue
            }
            
            let similarity = cosineSimilarity(newEmbedding, candidateEmbedding)
            
            // Check if similar enough to be related
            guard similarity >= config.similarityThreshold else { continue }
            
            // Detect conflict type
            if let conflict = analyzeConflict(
                newNode: newNode,
                oldNode: candidate,
                similarity: similarity
            ) {
                if conflict.confidence >= config.minConfidence {
                    conflicts.append(conflict)
                }
            }
        }
        
        // Sort by confidence (highest first)
        return conflicts.sorted { $0.confidence > $1.confidence }
    }
    
    /// Auto-resolve conflicts by creating appropriate edges
    public func resolveConflicts(
        _ conflicts: [ConflictingMemory],
        autoLink: Bool = true
    ) async throws {
        for conflict in conflicts {
            switch conflict.conflictType {
            case .updates:
                // New replaces old
                try await createUpdateEdge(from: conflict.newNode, to: conflict.oldNode)
                
            case .extends:
                // New adds detail to old
                try await createExtendsEdge(from: conflict.newNode, to: conflict.oldNode)
                
            case .supersedes:
                // New completely replaces old
                try await createSupersedesEdge(from: conflict.newNode, to: conflict.oldNode)
                
            case .duplicate:
                // Mark as duplicate (link with .similarTo)
                try await createDuplicateEdge(from: conflict.newNode, to: conflict.oldNode)
                
            case .contradicts:
                // Flag for manual review - don't auto-link
                break
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func getCandidates(for newNode: Node) async throws -> [Node] {
        var filters: [NodeFilter] = [.type(newNode.type)]
        
        // Add time window filter if specified
        if let timeWindow = config.timeWindow {
            let cutoff = Date().addingTimeInterval(-timeWindow)
            filters.append(.createdAfter(cutoff))
        }
        
        let candidates = try await graphStore.getNodes(
            filters: filters,
            limit: config.maxCandidates
        )
        
        return candidates
    }
    
    private func analyzeConflict(
        newNode: Node,
        oldNode: Node,
        similarity: Float
    ) -> ConflictingMemory? {
        // Check for duplicate (very high similarity + same content)
        if similarity > 0.95 && areContentsSimilar(newNode.content, oldNode.content) {
            return ConflictingMemory(
                oldNode: oldNode,
                newNode: newNode,
                similarity: similarity,
                conflictType: .duplicate,
                confidence: similarity,
                reason: "Nearly identical content"
            )
        }
        
        // Check for update (same subject, different value)
        if let updateType = detectUpdatePattern(newNode: newNode, oldNode: oldNode) {
            let confidence = calculateUpdateConfidence(
                similarity: similarity,
                updateType: updateType
            )
            
            return ConflictingMemory(
                oldNode: oldNode,
                newNode: newNode,
                similarity: similarity,
                conflictType: updateType,
                confidence: confidence,
                reason: "Subject match with different values"
            )
        }
        
        // Check for extension (new adds detail)
        if isExtension(newNode: newNode, oldNode: oldNode) {
            return ConflictingMemory(
                oldNode: oldNode,
                newNode: newNode,
                similarity: similarity,
                conflictType: .extends,
                confidence: similarity * 0.8, // Slightly less confident
                reason: "New content adds specificity"
            )
        }
        
        return nil
    }
    
    private func detectUpdatePattern(newNode: Node, oldNode: Node) -> ConflictType? {
        // Simple heuristic: look for common update patterns
        let newLower = newNode.content.lowercased()
        let oldLower = oldNode.content.lowercased()
        
        // Pattern: "X is Y" where X matches but Y differs
        let updateKeywords = [
            "is", "was", "are", "were",
            "favorite", "prefers", "likes", "loves",
            "now", "currently", "today"
        ]
        
        for keyword in updateKeywords {
            if newLower.contains(keyword) && oldLower.contains(keyword) {
                // Found common structure - likely an update
                
                // Check for strong replacement indicators
                if newLower.contains("now") || newLower.contains("currently") {
                    return .updates
                }
                
                // Check for superseding language
                if newLower.contains("no longer") || newLower.contains("instead") {
                    return .supersedes
                }
                
                return .updates
            }
        }
        
        return nil
    }
    
    private func isExtension(newNode: Node, oldNode: Node) -> Bool {
        let newLength = newNode.content.count
        let oldLength = oldNode.content.count
        
        // Extension typically has more detail (longer)
        if newLength > oldLength * 1.5 {
            // New contains most of old content
            if newNode.content.lowercased().contains(oldNode.content.lowercased()) {
                return true
            }
        }
        
        return false
    }
    
    private func areContentsSimilar(_ a: String, _ b: String) -> Bool {
        let aNorm = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let bNorm = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if essentially the same
        return aNorm == bNorm || 
               levenshteinDistance(aNorm, bNorm) < 5
    }
    
    private func calculateUpdateConfidence(
        similarity: Float,
        updateType: ConflictType
    ) -> Float {
        // Base confidence from similarity
        var confidence = similarity
        
        // Boost for strong indicators
        switch updateType {
        case .supersedes:
            confidence = min(confidence + 0.1, 1.0)
        case .updates:
            confidence = min(confidence + 0.05, 1.0)
        default:
            break
        }
        
        return confidence
    }
    
    // MARK: - Edge Creation
    
    private func createUpdateEdge(from new: Node, to old: Node) async throws {
        let edge = Edge(
            fromNodeID: new.id,
            toNodeID: old.id,
            relationshipType: .updates,
            weight: 1.0,
            metadata: [
                "auto_detected": .bool(true),
                "detected_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
        )
        
        try await graphStore.storeEdge(edge)
        
        // Mark old node as superseded in metadata
        var updatedOld = old
        updatedOld.metadata["superseded_by"] = .string(new.id.value.uuidString)
        updatedOld.metadata["superseded_at"] = .string(ISO8601DateFormatter().string(from: Date()))
        try await graphStore.storeNode(updatedOld)
    }
    
    private func createExtendsEdge(from new: Node, to old: Node) async throws {
        let edge = Edge(
            fromNodeID: new.id,
            toNodeID: old.id,
            relationshipType: .extends,
            weight: 0.8,
            metadata: [
                "auto_detected": .bool(true),
                "detected_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
        )
        
        try await graphStore.storeEdge(edge)
    }
    
    private func createSupersedesEdge(from new: Node, to old: Node) async throws {
        let edge = Edge(
            fromNodeID: new.id,
            toNodeID: old.id,
            relationshipType: .supersedes,
            weight: 1.0,
            metadata: [
                "auto_detected": .bool(true),
                "detected_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
        )
        
        try await graphStore.storeEdge(edge)
        
        // Mark old as completely superseded
        var updatedOld = old
        updatedOld.metadata["superseded_by"] = .string(new.id.value.uuidString)
        updatedOld.metadata["superseded_at"] = .string(ISO8601DateFormatter().string(from: Date()))
        updatedOld.metadata["active"] = .bool(false)
        try await graphStore.storeNode(updatedOld)
    }
    
    private func createDuplicateEdge(from new: Node, to old: Node) async throws {
        let edge = Edge(
            fromNodeID: new.id,
            toNodeID: old.id,
            relationshipType: .similarTo,
            weight: 0.95,
            metadata: [
                "duplicate": .bool(true),
                "auto_detected": .bool(true),
                "detected_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
        )
        
        try await graphStore.storeEdge(edge)
    }
    
    // MARK: - Utility Functions
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        
        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0.0 }
        
        return dotProduct / denominator
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let len1 = s1.count
        let len2 = s2.count
        
        if len1 == 0 { return len2 }
        if len2 == 0 { return len1 }
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: len2 + 1), count: len1 + 1)
        
        for i in 0...len1 { matrix[i][0] = i }
        for j in 0...len2 { matrix[0][j] = j }
        
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        
        for i in 1...len1 {
            for j in 1...len2 {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[len1][len2]
    }
}