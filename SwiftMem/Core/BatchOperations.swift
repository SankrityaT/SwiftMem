import Foundation

/// Phase 8: Batch Operations
/// Efficient bulk operations for adding, updating, and deleting memories
public actor BatchOperations {
    private let embedder: Embedder
    private let relationshipDetector: RelationshipDetector
    
    public init(embedder: Embedder, relationshipDetector: RelationshipDetector) {
        self.embedder = embedder
        self.relationshipDetector = relationshipDetector
    }
    
    /// Batch add multiple memories efficiently
    public func batchAdd(
        contents: [String],
        userId: String,
        containerTags: [[String]] = [],
        existingMemories: [MemoryNode]
    ) async throws -> [MemoryNode] {
        print("📦 [BatchOps] Adding \(contents.count) memories in batch...")
        
        // Generate embeddings in parallel
        let embeddings = try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (index, content) in contents.enumerated() {
                group.addTask {
                    let embedding = try await self.embedder.embed(content)
                    return (index, embedding)
                }
            }
            
            var results: [(Int, [Float])] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        
        // Create memory nodes
        var newMemories: [MemoryNode] = []
        for (index, content) in contents.enumerated() {
            let tags = index < containerTags.count ? containerTags[index] : []
            let memory = MemoryNode(
                content: content,
                embedding: embeddings[index],
                containerTags: tags
            )
            newMemories.append(memory)
        }
        
        // Detect relationships for all new memories
        var allMemories = existingMemories
        for memory in newMemories {
            let relationships = try await relationshipDetector.detectRelationships(
                newMemory: memory,
                existingMemories: allMemories
            )
            var updatedMemory = memory
            updatedMemory.relationships = relationships.map { detected in
                MemoryRelationship(
                    type: detected.type,
                    targetId: detected.targetId,
                    confidence: detected.confidence
                )
            }
            allMemories.append(updatedMemory)
        }
        
        print("✅ [BatchOps] Batch add complete: \(newMemories.count) memories")
        return Array(allMemories.suffix(newMemories.count))
    }
    
    /// Batch delete multiple memories by IDs
    public func batchDelete(
        ids: [UUID],
        from memories: [MemoryNode]
    ) -> [MemoryNode] {
        print("📦 [BatchOps] Deleting \(ids.count) memories in batch...")
        
        let idsSet = Set(ids)
        let remaining = memories.filter { !idsSet.contains($0.id) }
        
        print("✅ [BatchOps] Batch delete complete: \(memories.count - remaining.count) removed")
        return remaining
    }
    
    /// Batch update memories with new content/metadata
    public func batchUpdate(
        updates: [(id: UUID, content: String?, metadata: MemoryMetadata?, containerTags: [String]?)],
        memories: [MemoryNode]
    ) async throws -> [MemoryNode] {
        print("📦 [BatchOps] Updating \(updates.count) memories in batch...")
        
        var memoryMap = Dictionary(uniqueKeysWithValues: memories.map { ($0.id, $0) })
        var updatedCount = 0
        
        for update in updates {
            guard var memory = memoryMap[update.id] else { continue }
            
            // Update content and regenerate embedding if needed
            if let newContent = update.content, newContent != memory.content {
                let newEmbedding = try await embedder.embed(newContent)
                memory = MemoryNode(
                    id: memory.id,
                    content: newContent,
                    embedding: newEmbedding,
                    timestamp: memory.timestamp,
                    confidence: memory.confidence,
                    relationships: memory.relationships,
                    metadata: update.metadata ?? memory.metadata,
                    isLatest: memory.isLatest,
                    isStatic: memory.isStatic,
                    containerTags: update.containerTags ?? memory.containerTags
                )
            } else {
                // Update metadata/tags only
                if let newMetadata = update.metadata {
                    memory.metadata = newMetadata
                }
                if let newTags = update.containerTags {
                    memory.containerTags = newTags
                }
            }
            
            memoryMap[update.id] = memory
            updatedCount += 1
        }
        
        print("✅ [BatchOps] Batch update complete: \(updatedCount) memories updated")
        return Array(memoryMap.values)
    }
    
    /// Batch search across multiple queries
    public func batchSearch(
        queries: [String],
        memories: [MemoryNode],
        limit: Int = 5
    ) async throws -> [[MemoryNode]] {
        print("📦 [BatchOps] Searching \(queries.count) queries in batch...")
        
        // Generate query embeddings in parallel
        let queryEmbeddings = try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    let embedding = try await self.embedder.embed(query)
                    return (index, embedding)
                }
            }
            
            var results: [(Int, [Float])] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        
        // Search for each query
        var allResults: [[MemoryNode]] = []
        for queryEmbedding in queryEmbeddings {
            let scored = memories.map { memory -> (MemoryNode, Float) in
                let similarity = cosineSimilarity(queryEmbedding, memory.embedding)
                return (memory, similarity)
            }
            
            let topResults = scored
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map { $0.0 }
            
            allResults.append(Array(topResults))
        }
        
        print("✅ [BatchOps] Batch search complete: \(queries.count) queries processed")
        return allResults
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
}
