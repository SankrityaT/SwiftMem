//
//  VectorStore.swift
//  SwiftMem
//
//  Created on 12/7/24.
//  Production-ready vector storage with HNSW index for semantic search
//

import Foundation
import Accelerate

// MARK: - Vector Store

/// High-performance vector storage and similarity search
/// Supports both linear (exact) and HNSW (approximate) search
public actor VectorStore {
    
    // MARK: - Properties
    
    private let config: SwiftMemConfig
    private var vectors: [NodeID: [Float]] = [:]
    private var hnswIndex: HNSWIndex?
    
    // Cache for frequent queries
    private var queryCache: [String: [ScoredNode]] = [:]
    private let maxCacheSize = 100
    
    // MARK: - Initialization
    
    public init(config: SwiftMemConfig) {
        self.config = config
        
        // Initialize HNSW index if configured
        if config.vectorIndexType == .hnsw {
            self.hnswIndex = HNSWIndex(
                dimensions: config.embeddingDimensions,
                m: 16,              // Number of bi-directional links per node
                efConstruction: 200, // Size of dynamic candidate list during construction
                efSearch: config.defaultTopK * 2 // Size during search (larger = more accurate)
            )
        }
    }
    
    // MARK: - Storage Operations
    
    /// Add a vector for a node
    public func addVector(_ vector: [Float], for nodeId: NodeID) async throws {
        guard vector.count == config.embeddingDimensions else {
            throw SwiftMemError.configurationError("Vector dimension mismatch: expected \(config.embeddingDimensions), got \(vector.count)")
        }
        
        // Normalize vector for cosine similarity
        let normalizedVector = normalize(vector)
        
        // Store in dictionary
        vectors[nodeId] = normalizedVector
        
        // Add to HNSW index if enabled
        if let hnswIndex = hnswIndex {
            await hnswIndex.insert(vector: normalizedVector, id: nodeId)
        }
        
        // Clear cache on update
        queryCache.removeAll()
    }
    
    /// Add multiple vectors in batch
    public func addVectors(_ items: [(nodeId: NodeID, vector: [Float])]) async throws {
        for item in items {
            try await addVector(item.vector, for: item.nodeId)
        }
    }
    
    /// Remove a vector
    public func removeVector(for nodeId: NodeID) async {
        vectors.removeValue(forKey: nodeId)
        
        // Remove from HNSW index if enabled
        if let hnswIndex = hnswIndex {
            await hnswIndex.remove(id: nodeId)
        }
        
        // Clear cache
        queryCache.removeAll()
    }
    
    /// Remove multiple vectors
    public func removeVectors(for nodeIds: [NodeID]) async {
        for nodeId in nodeIds {
            await removeVector(for: nodeId)
        }
    }
    
    /// Get a stored vector
    public func getVector(for nodeId: NodeID) async -> [Float]? {
        return vectors[nodeId]
    }
    
    /// Check if a vector exists
    public func hasVector(for nodeId: NodeID) async -> Bool {
        return vectors[nodeId] != nil
    }
    
    /// Get total vector count
    public func getVectorCount() async -> Int {
        return vectors.count
    }
    
    /// Clear all vectors
    public func clearAll() async {
        vectors.removeAll()
        hnswIndex = nil
        queryCache.removeAll()
        
        // Reinitialize HNSW if configured
        if config.vectorIndexType == .hnsw {
            hnswIndex = HNSWIndex(
                dimensions: config.embeddingDimensions,
                m: 16,
                efConstruction: 200,
                efSearch: config.defaultTopK * 2
            )
        }
    }
    
    // MARK: - Search Operations
    
    /// Find k nearest neighbors using configured search method
    /// Returns node IDs and similarity scores
    public func search(
        query: [Float],
        k: Int? = nil,
        threshold: Float? = nil,
        excludeIds: Set<NodeID> = []
    ) async throws -> [(nodeId: NodeID, score: Float)] {
        guard query.count == config.embeddingDimensions else {
            throw SwiftMemError.configurationError("Query vector dimension mismatch")
        }
        
        let topK = k ?? config.defaultTopK
        let similarityThreshold = threshold ?? Float(config.similarityThreshold)
        
        // Check cache
        let cacheKey = "\(query.hashValue)-\(topK)-\(similarityThreshold)-\(excludeIds.hashValue)"
        if let cached = queryCache[cacheKey] {
            return cached.map { ($0.node.id, Float($0.score)) }
        }
        
        // Normalize query
        let normalizedQuery = normalize(query)
        
        // Choose search method
        let results: [(nodeId: NodeID, score: Float)]
        if config.vectorIndexType == .hnsw, let hnswIndex = hnswIndex {
            results = try await hnswSearchInternal(
                query: normalizedQuery,
                k: topK,
                threshold: similarityThreshold,
                excludeIds: excludeIds,
                index: hnswIndex
            )
        } else {
            results = try await linearSearchInternal(
                query: normalizedQuery,
                k: topK,
                threshold: similarityThreshold,
                excludeIds: excludeIds
            )
        }
        
        // Cache results (convert to ScoredNode for cache)
        if queryCache.count >= maxCacheSize {
            // Remove oldest entry (simple LRU approximation)
            queryCache.removeValue(forKey: queryCache.keys.first!)
        }
        let cacheResults = results.map { ScoredNode(node: Node(id: $0.nodeId, content: "", type: .general), score: Double($0.score)) }
        queryCache[cacheKey] = cacheResults
        
        return results
    }
    
    /// Find similar vectors to a stored node
    public func findSimilar(
        to nodeId: NodeID,
        k: Int? = nil,
        threshold: Float? = nil
    ) async throws -> [(nodeId: NodeID, score: Float)] {
        guard let vector = vectors[nodeId] else {
            throw SwiftMemError.storageError("Vector not found for node: \(nodeId)")
        }
        
        var excludeIds = Set<NodeID>()
        excludeIds.insert(nodeId) // Don't include the query node itself
        
        return try await search(
            query: vector,
            k: k,
            threshold: threshold,
            excludeIds: excludeIds
        )
    }
    
    // MARK: - Internal Search Methods
    
    private func linearSearchInternal(
        query: [Float],
        k: Int,
        threshold: Float,
        excludeIds: Set<NodeID>
    ) async throws -> [(nodeId: NodeID, score: Float)] {
        var scoredNodes: [(nodeId: NodeID, score: Float)] = []
        
        // Calculate cosine similarity for all vectors
        for (nodeId, vector) in vectors {
            if excludeIds.contains(nodeId) { continue }
            
            let similarity = cosineSimilarity(query, vector)
            
            if similarity >= threshold {
                scoredNodes.append((nodeId, similarity))
            }
        }
        
        // Sort by score descending and take top k
        scoredNodes.sort { $0.score > $1.score }
        let topResults = Array(scoredNodes.prefix(k))
        
        return topResults
    }
    
    private func hnswSearchInternal(
        query: [Float],
        k: Int,
        threshold: Float,
        excludeIds: Set<NodeID>,
        index: HNSWIndex
    ) async throws -> [(nodeId: NodeID, score: Float)] {
        // Search HNSW index
        let candidates = await index.search(query: query, k: k * 2) // Get more candidates
        
        // Filter by threshold and exclusions
        var results: [(nodeId: NodeID, score: Float)] = []
        
        for candidate in candidates {
            if excludeIds.contains(candidate.nodeId) { continue }
            if candidate.score < threshold { continue }
            
            results.append((candidate.nodeId, candidate.score))
            
            if results.count >= k {
                break
            }
        }
        
        return results
    }
    
    // MARK: - Batch Operations
    
    /// Rebuild the HNSW index from scratch (useful after bulk updates)
    public func rebuildIndex() async throws {
        guard config.vectorIndexType == .hnsw else {
            return // No index to rebuild
        }
        
        // Create new index
        let newIndex = HNSWIndex(
            dimensions: config.embeddingDimensions,
            m: 16,
            efConstruction: 200,
            efSearch: config.defaultTopK * 2
        )
        
        // Insert all vectors
        for (nodeId, vector) in vectors {
            await newIndex.insert(vector: vector, id: nodeId)
        }
        
        // Replace old index
        hnswIndex = newIndex
        
        // Clear cache
        queryCache.removeAll()
    }
    
    /// Get statistics about the vector store
    public func getStats() async -> (
        vectorCount: Int,
        dimensions: Int,
        indexType: VectorIndexType,
        cacheSize: Int,
        avgVectorNorm: Float
    ) {
        let count = vectors.count
        let dimensions = config.embeddingDimensions
        let indexType = config.vectorIndexType
        let cacheSize = queryCache.count
        
        // Calculate average vector norm
        var totalNorm: Float = 0
        for vector in vectors.values {
            totalNorm += vectorNorm(vector)
        }
        let avgNorm = count > 0 ? totalNorm / Float(count) : 0
        
        return (count, dimensions, indexType, cacheSize, avgNorm)
    }
    
    // MARK: - Vector Math Utilities
    
    /// Normalize a vector to unit length (for cosine similarity)
    private func normalize(_ vector: [Float]) -> [Float] {
        let norm = vectorNorm(vector)
        guard norm > 0 else { return vector }
        
        return vector.map { $0 / norm }
    }
    
    /// Calculate L2 norm of a vector
    private func vectorNorm(_ vector: [Float]) -> Float {
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        return sqrt(norm)
    }
    
    /// Calculate cosine similarity between two vectors
    /// Assumes vectors are already normalized
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        
        return result
    }
    
    /// Calculate Euclidean distance between two vectors
    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }
        
        var diff = [Float](repeating: 0, count: a.count)
        vDSP_vsub(b, 1, a, 1, &diff, 1, vDSP_Length(a.count))
        
        return vectorNorm(diff)
    }
}

// MARK: - HNSW Index Implementation

/// Hierarchical Navigable Small World (HNSW) index for approximate nearest neighbor search
/// Based on the paper: "Efficient and robust approximate nearest neighbor search using Hierarchical Navigable Small World graphs"
private actor HNSWIndex {
    
    // MARK: - Node Structure
    
    private struct HNSWNode {
        let id: NodeID
        let vector: [Float]
        var level: Int
        var connections: [Int: Set<NodeID>] // level -> connected node IDs
        
        init(id: NodeID, vector: [Float], level: Int) {
            self.id = id
            self.vector = vector
            self.level = level
            self.connections = [:]
        }
    }
    
    // MARK: - Properties
    
    private let dimensions: Int
    private let m: Int              // Max connections per node per layer
    private let efConstruction: Int // Size of dynamic candidate list during construction
    private let efSearch: Int       // Size during search
    private let mL: Float = 1.0 / log(2.0) // Level multiplier
    
    private var nodes: [NodeID: HNSWNode] = [:]
    private var entryPoint: NodeID?
    private var maxLevel: Int = 0
    
    // MARK: - Initialization
    
    init(dimensions: Int, m: Int, efConstruction: Int, efSearch: Int) {
        self.dimensions = dimensions
        self.m = m
        self.efConstruction = efConstruction
        self.efSearch = efSearch
    }
    
    // MARK: - Operations
    
    func insert(vector: [Float], id: NodeID) {
        let level = randomLevel()
        var node = HNSWNode(id: id, vector: vector, level: level)
        
        // First node becomes entry point
        if entryPoint == nil {
            entryPoint = id
            maxLevel = level
            nodes[id] = node
            return
        }
        
        // Find nearest neighbors at each level
        var currentNearest = [entryPoint!]
        
        // Search from top level down to target level
        for lc in stride(from: maxLevel, through: level + 1, by: -1) {
            currentNearest = searchLayer(
                query: vector,
                entryPoints: currentNearest,
                level: lc,
                ef: 1
            )
        }
        
        // Insert at levels 0 to target level
        for lc in 0...level {
            let candidates = searchLayer(
                query: vector,
                entryPoints: currentNearest,
                level: lc,
                ef: efConstruction
            )
            
            // Select M neighbors
            let neighbors = selectNeighbors(candidates: candidates, m: m)
            
            // Add bidirectional connections
            node.connections[lc] = Set(neighbors)
            
            for neighborId in neighbors {
                if var neighbor = nodes[neighborId] {
                    if neighbor.connections[lc] == nil {
                        neighbor.connections[lc] = Set()
                    }
                    neighbor.connections[lc]?.insert(id)
                    
                    // Prune connections if needed
                    if neighbor.connections[lc]!.count > m {
                        let candidates = Array(neighbor.connections[lc]!)
                        let pruned = selectNeighbors(candidates: candidates, m: m)
                        neighbor.connections[lc] = Set(pruned)
                    }
                    
                    nodes[neighborId] = neighbor
                }
            }
        }
        
        // Update entry point if necessary
        if level > maxLevel {
            entryPoint = id
            maxLevel = level
        }
        
        nodes[id] = node
    }
    
    func search(query: [Float], k: Int) -> [(nodeId: NodeID, score: Float)] {
        guard let entryPoint = entryPoint else {
            return []
        }
        
        var currentNearest = [entryPoint]
        
        // Search from top to level 1
        for lc in stride(from: maxLevel, through: 1, by: -1) {
            currentNearest = searchLayer(
                query: query,
                entryPoints: currentNearest,
                level: lc,
                ef: 1
            )
        }
        
        // Search at level 0 with ef
        let candidates = searchLayer(
            query: query,
            entryPoints: currentNearest,
            level: 0,
            ef: max(efSearch, k)
        )
        
        // Calculate scores and return top k
        var scored: [(nodeId: NodeID, score: Float)] = []
        for nodeId in candidates.prefix(k) {
            if let node = nodes[nodeId] {
                let similarity = cosineSimilarity(query, node.vector)
                scored.append((nodeId, similarity))
            }
        }
        
        scored.sort { $0.score > $1.score }
        
        return scored
    }
    
    func remove(id: NodeID) {
        guard let node = nodes[id] else { return }
        
        // Remove all connections to this node
        for level in 0...node.level {
            if let connections = node.connections[level] {
                for neighborId in connections {
                    if var neighbor = nodes[neighborId] {
                        neighbor.connections[level]?.remove(id)
                        nodes[neighborId] = neighbor
                    }
                }
            }
        }
        
        // Remove the node
        nodes.removeValue(forKey: id)
        
        // Update entry point if needed
        if id == entryPoint {
            entryPoint = nodes.keys.first
            maxLevel = nodes.values.map { $0.level }.max() ?? 0
        }
    }
    
    // MARK: - Helper Methods
    
    private func searchLayer(
        query: [Float],
        entryPoints: [NodeID],
        level: Int,
        ef: Int
    ) -> [NodeID] {
        var visited = Set<NodeID>()
        var candidates: [(nodeId: NodeID, distance: Float)] = []
        var results: [(nodeId: NodeID, distance: Float)] = []
        
        // Initialize with entry points
        for ep in entryPoints {
            if let node = nodes[ep] {
                let dist = euclideanDistance(query, node.vector)
                candidates.append((ep, dist))
                results.append((ep, dist))
                visited.insert(ep)
            }
        }
        
        candidates.sort { $0.distance < $1.distance }
        results.sort { $0.distance < $1.distance }
        
        while !candidates.isEmpty {
            let current = candidates.removeFirst()
            
            if current.distance > results.last!.distance {
                break
            }
            
            guard let currentNode = nodes[current.nodeId],
                  let neighbors = currentNode.connections[level] else {
                continue
            }
            
            for neighborId in neighbors {
                if visited.contains(neighborId) { continue }
                visited.insert(neighborId)
                
                guard let neighborNode = nodes[neighborId] else { continue }
                
                let dist = euclideanDistance(query, neighborNode.vector)
                
                if dist < results.last!.distance || results.count < ef {
                    candidates.append((neighborId, dist))
                    results.append((neighborId, dist))
                    
                    candidates.sort { $0.distance < $1.distance }
                    results.sort { $0.distance < $1.distance }
                    
                    if results.count > ef {
                        results.removeLast()
                    }
                }
            }
        }
        
        return results.map { $0.nodeId }
    }
    
    private func selectNeighbors(candidates: [NodeID], m: Int) -> [NodeID] {
        // Simple heuristic: select m nearest
        return Array(candidates.prefix(m))
    }
    
    private func randomLevel() -> Int {
        let r = Float.random(in: 0..<1)
        return Int(floor(-log(r) * mL))
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }
    
    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }
        var diff = [Float](repeating: 0, count: a.count)
        vDSP_vsub(b, 1, a, 1, &diff, 1, vDSP_Length(a.count))
        var norm: Float = 0
        vDSP_svesq(diff, 1, &norm, vDSP_Length(diff.count))
        return sqrt(norm)
    }
}
