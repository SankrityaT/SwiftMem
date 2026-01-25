//
//  MemoryGraph.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//

import Foundation

/// In-memory representation of the knowledge graph
public actor MemoryGraph {
    private var nodes: [UUID: MemoryNode] = [:]
    private var adjacencyList: [UUID: Set<UUID>] = [:]  // For efficient traversal
    
    public init() {}
    
    // MARK: - Node Operations
    
    /// Add a node to the graph
    public func addNode(_ node: MemoryNode) {
        nodes[node.id] = node
        
        // Update adjacency list
        if adjacencyList[node.id] == nil {
            adjacencyList[node.id] = Set()
        }
        
        for relationship in node.relationships {
            adjacencyList[node.id]?.insert(relationship.targetId)
        }
    }
    
    /// Get a node by ID
    public func getNode(_ id: UUID) -> MemoryNode? {
        return nodes[id]
    }
    
    /// Update a node
    public func updateNode(_ node: MemoryNode) {
        nodes[node.id] = node
        
        // Rebuild adjacency list for this node
        adjacencyList[node.id] = Set(node.relationships.map { $0.targetId })
    }
    
    /// Remove a node
    public func removeNode(_ id: UUID) {
        nodes.removeValue(forKey: id)
        adjacencyList.removeValue(forKey: id)
        
        // Remove from other nodes' adjacency lists
        for (nodeId, _) in adjacencyList {
            adjacencyList[nodeId]?.remove(id)
        }
    }
    
    /// Get all nodes
    public func getAllNodes() -> [MemoryNode] {
        return Array(nodes.values)
    }
    
    // MARK: - Relationship Operations
    
    /// Add a relationship between two nodes
    public func addRelationship(from sourceId: UUID, to targetId: UUID, type: RelationType, confidence: Float = 1.0) {
        guard var sourceNode = nodes[sourceId] else { return }
        
        let relationship = MemoryRelationship(
            type: type,
            targetId: targetId,
            confidence: confidence
        )
        
        sourceNode.addRelationship(relationship)
        nodes[sourceId] = sourceNode
        
        // Update adjacency list
        adjacencyList[sourceId]?.insert(targetId)
        
        // Handle UPDATES relationship - mark old node as not latest
        if type == .updates, var targetNode = nodes[targetId] {
            targetNode.isLatest = false
            nodes[targetId] = targetNode
        }
    }
    
    /// Get all nodes related to a given node
    public func getRelatedNodes(_ nodeId: UUID, ofType type: RelationType? = nil) -> [MemoryNode] {
        guard let node = nodes[nodeId] else { return [] }
        
        let relationships = type == nil ? node.relationships : node.relationships.filter { $0.type == type }
        
        return relationships.compactMap { nodes[$0.targetId] }
    }
    
    /// Get nodes that point to this node (reverse relationships)
    public func getIncomingNodes(_ nodeId: UUID, ofType type: RelationType? = nil) -> [MemoryNode] {
        return nodes.values.filter { node in
            let hasRelationship = node.relationships.contains { $0.targetId == nodeId }
            if let type = type {
                return node.relationships.contains { $0.targetId == nodeId && $0.type == type }
            }
            return hasRelationship
        }
    }
    
    // MARK: - Graph Traversal
    
    /// Get all nodes in a subgraph starting from a node (BFS)
    public func getSubgraph(startingFrom nodeId: UUID, maxDepth: Int = 3) -> [MemoryNode] {
        var visited = Set<UUID>()
        var queue: [(UUID, Int)] = [(nodeId, 0)]
        var result: [MemoryNode] = []
        
        while !queue.isEmpty {
            let (currentId, depth) = queue.removeFirst()
            
            guard depth <= maxDepth, !visited.contains(currentId) else { continue }
            visited.insert(currentId)
            
            if let node = nodes[currentId] {
                result.append(node)
                
                // Add neighbors to queue
                for relationship in node.relationships {
                    if !visited.contains(relationship.targetId) {
                        queue.append((relationship.targetId, depth + 1))
                    }
                }
            }
        }
        
        return result
    }
    
    /// Find path between two nodes
    public func findPath(from sourceId: UUID, to targetId: UUID) -> [MemoryNode]? {
        var visited = Set<UUID>()
        var queue: [(UUID, [UUID])] = [(sourceId, [sourceId])]
        
        while !queue.isEmpty {
            let (currentId, path) = queue.removeFirst()
            
            if currentId == targetId {
                return path.compactMap { nodes[$0] }
            }
            
            guard !visited.contains(currentId) else { continue }
            visited.insert(currentId)
            
            if let neighbors = adjacencyList[currentId] {
                for neighborId in neighbors {
                    if !visited.contains(neighborId) {
                        queue.append((neighborId, path + [neighborId]))
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Query Operations
    
    /// Get latest version of a memory (following UPDATES chain)
    public func getLatestVersion(of nodeId: UUID) -> MemoryNode? {
        guard var node = nodes[nodeId] else { return nil }
        
        // Follow UPDATES relationships to find latest
        while !node.isLatest {
            let updaters = getIncomingNodes(node.id, ofType: .updates)
            guard let latestNode = updaters.first(where: { $0.isLatest }) else {
                break
            }
            node = latestNode
        }
        
        return node
    }
    
    /// Get all memories that extend a given memory
    public func getExtensions(of nodeId: UUID) -> [MemoryNode] {
        return getIncomingNodes(nodeId, ofType: .extends)
    }
    
    /// Get all memories that derive from a given memory
    public func getDerivedMemories(from nodeId: UUID) -> [MemoryNode] {
        return getIncomingNodes(nodeId, ofType: .derives)
    }
    
    /// Get enriched context for a memory (includes extensions and related)
    public func getEnrichedContext(for nodeId: UUID) -> [MemoryNode] {
        guard let node = nodes[nodeId] else { return [] }
        
        var context: [MemoryNode] = [node]
        
        // Add extensions
        context.append(contentsOf: getExtensions(of: nodeId))
        
        // Add related memories
        context.append(contentsOf: getRelatedNodes(nodeId, ofType: .relatedTo))
        
        // Add derived memories
        context.append(contentsOf: getDerivedMemories(from: nodeId))
        
        return context
    }
    
    // MARK: - Filtering
    
    /// Get only latest (non-superseded) nodes
    public func getLatestNodes() -> [MemoryNode] {
        return nodes.values.filter { $0.isLatest && !$0.isSuperseded }
    }
    
    /// Get nodes by confidence threshold
    public func getNodesByConfidence(minConfidence: Float, currentDate: Date = Date()) -> [MemoryNode] {
        return nodes.values.filter { $0.effectiveConfidence(currentDate: currentDate) >= minConfidence }
    }
    
    /// Get static memories (core facts)
    public func getStaticMemories() -> [MemoryNode] {
        return nodes.values.filter { $0.isStatic }
    }
    
    /// Get dynamic memories (episodic)
    public func getDynamicMemories() -> [MemoryNode] {
        return nodes.values.filter { !$0.isStatic }
    }
    
    // MARK: - Statistics
    
    public func nodeCount() -> Int {
        return nodes.count
    }
    
    public func relationshipCount() -> Int {
        return nodes.values.reduce(0) { $0 + $1.relationships.count }
    }
    
    public func averageDegree() -> Double {
        guard !nodes.isEmpty else { return 0 }
        return Double(relationshipCount()) / Double(nodeCount())
    }
}
