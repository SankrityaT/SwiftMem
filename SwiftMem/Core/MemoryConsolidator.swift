import Foundation

/// Phase 7: Memory Consolidation
/// Detects and merges duplicate or highly similar memories to reduce redundancy
public actor MemoryConsolidator {
    private let similarityThreshold: Float = 0.85  // High threshold for duplicates
    
    public init() {}
    
    /// Find duplicate memories that should be consolidated
    public func findDuplicates(in memories: [MemoryNode]) -> [(original: MemoryNode, duplicate: MemoryNode)] {
        var duplicates: [(MemoryNode, MemoryNode)] = []
        
        for i in 0..<memories.count {
            for j in (i+1)..<memories.count {
                let similarity = cosineSimilarity(memories[i].embedding, memories[j].embedding)
                
                if similarity >= similarityThreshold {
                    // Keep the older memory as original
                    let (original, duplicate) = memories[i].timestamp < memories[j].timestamp 
                        ? (memories[i], memories[j])
                        : (memories[j], memories[i])
                    
                    duplicates.append((original, duplicate))
                    print("🔄 [Consolidator] Found duplicate: \(duplicate.id) → \(original.id) (similarity: \(similarity))")
                }
            }
        }
        
        return duplicates
    }
    
    /// Merge two memories into one consolidated memory
    public func merge(original: MemoryNode, duplicate: MemoryNode) -> MemoryNode {
        // Combine content if different
        let mergedContent = original.content == duplicate.content 
            ? original.content
            : "\(original.content)\n\nUpdate: \(duplicate.content)"
        
        // Take higher confidence
        let mergedConfidence = max(original.confidence, duplicate.confidence)
        
        // Merge relationships (deduplicate by target ID)
        var relationshipMap: [UUID: MemoryRelationship] = [:]
        for rel in original.relationships {
            relationshipMap[rel.targetId] = rel
        }
        for rel in duplicate.relationships {
            if let existing = relationshipMap[rel.targetId] {
                // Keep relationship with higher confidence
                if rel.confidence > existing.confidence {
                    relationshipMap[rel.targetId] = rel
                }
            } else {
                relationshipMap[rel.targetId] = rel
            }
        }
        
        // Merge metadata
        var mergedMetadata = original.metadata
        mergedMetadata.accessCount = original.metadata.accessCount + duplicate.metadata.accessCount
        mergedMetadata.importance = max(original.metadata.importance, duplicate.metadata.importance)
        mergedMetadata.userConfirmed = original.metadata.userConfirmed || duplicate.metadata.userConfirmed
        
        // Merge container tags
        let mergedTags = Array(Set(original.containerTags + duplicate.containerTags))
        
        return MemoryNode(
            id: original.id,  // Keep original ID
            content: mergedContent,
            embedding: original.embedding,  // Keep original embedding
            timestamp: original.timestamp,  // Keep original timestamp
            confidence: mergedConfidence,
            relationships: Array(relationshipMap.values),
            metadata: mergedMetadata,
            isLatest: true,
            isStatic: original.isStatic || duplicate.isStatic,
            containerTags: mergedTags
        )
    }
    
    /// Consolidate all duplicate memories in a batch
    public func consolidate(memories: [MemoryNode]) -> (consolidated: [MemoryNode], removed: [UUID]) {
        let duplicates = findDuplicates(in: memories)
        
        if duplicates.isEmpty {
            print("✅ [Consolidator] No duplicates found")
            return (memories, [])
        }
        
        print("🔄 [Consolidator] Consolidating \(duplicates.count) duplicate pairs...")
        
        var memoryMap: [UUID: MemoryNode] = Dictionary(uniqueKeysWithValues: memories.map { ($0.id, $0) })
        var removedIds: Set<UUID> = []
        
        for (original, duplicate) in duplicates {
            guard !removedIds.contains(duplicate.id) else { continue }
            
            let merged = merge(original: original, duplicate: duplicate)
            memoryMap[original.id] = merged
            memoryMap.removeValue(forKey: duplicate.id)
            removedIds.insert(duplicate.id)
        }
        
        print("✅ [Consolidator] Consolidated \(removedIds.count) duplicates")
        return (Array(memoryMap.values), Array(removedIds))
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
