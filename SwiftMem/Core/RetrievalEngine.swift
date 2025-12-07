//
//  RetrievalEngine.swift
//  SwiftMem
//
//  Created on 12/7/24.
//  Intelligent retrieval combining vector search, graph traversal, and re-ranking
//

import Foundation

// MARK: - Retrieval Engine

/// The brain of SwiftMem - combines vector search, graph traversal, and intelligent ranking
public actor RetrievalEngine {
    
    // MARK: - Properties
    
    private let graphStore: GraphStore
    private let vectorStore: VectorStore
    private let embeddingEngine: EmbeddingEngine
    private let config: SwiftMemConfig
    
    // MARK: - Initialization
    
    public init(
        graphStore: GraphStore,
        vectorStore: VectorStore,
        embeddingEngine: EmbeddingEngine,
        config: SwiftMemConfig
    ) {
        self.graphStore = graphStore
        self.vectorStore = vectorStore
        self.embeddingEngine = embeddingEngine
        self.config = config
    }
    
    // MARK: - Query Methods
    
    /// Retrieve relevant memories using the configured strategy
    public func query(
        _ query: String,
        maxResults: Int? = nil,
        strategy: RetrievalStrategy? = nil,
        filters: [String: MetadataValue]? = nil
    ) async throws -> RetrievalResult {
        let startTime = Date()
        let selectedStrategy = strategy ?? config.defaultRetrievalStrategy
        let limit = maxResults ?? config.defaultMaxResults
        
        // Generate query embedding
        let queryEmbedding = try await embeddingEngine.embed(query)
        
        // Execute strategy
        var scoredNodes: [ScoredNode]
        var nodesSearched = 0
        
        switch selectedStrategy {
        case .vector:
            (scoredNodes, nodesSearched) = try await vectorOnlyRetrieval(
                queryEmbedding: queryEmbedding,
                limit: limit,
                filters: filters
            )
            
        case .graph:
            (scoredNodes, nodesSearched) = try await graphOnlyRetrieval(
                query: query,
                limit: limit,
                filters: filters
            )
            
        case .hybrid:
            (scoredNodes, nodesSearched) = try await hybridRetrieval(
                query: query,
                queryEmbedding: queryEmbedding,
                limit: limit,
                filters: filters
            )
            
        case .temporal:
            (scoredNodes, nodesSearched) = try await temporalRetrieval(
                queryEmbedding: queryEmbedding,
                limit: limit,
                filters: filters
            )
            
        case .custom(let customFunc):
            // User-provided custom retrieval
            let nodes = try await customFunc(query)
            scoredNodes = nodes.map { ScoredNode(node: $0, score: 1.0) }
            nodesSearched = nodes.count
        }
        
        // Apply filters if provided
        if let filters = filters {
            scoredNodes = applyFilters(scoredNodes, filters: filters)
        }
        
        // Limit results
        scoredNodes = Array(scoredNodes.prefix(limit))
        
        // Format context
        let formattedContext = formatContext(scoredNodes, format: .conversational, maxTokens: nil)
        
        // Calculate metrics
        let retrievalTime = Date().timeIntervalSince(startTime)
        let estimatedTokens = formattedContext.count / 4 // Rough estimate: 4 chars per token
        
        let metadata = RetrievalMetadata(
            strategy: String(describing: selectedStrategy),
            nodesSearched: nodesSearched,
            retrievalTime: retrievalTime,
            estimatedTokens: estimatedTokens
        )
        
        return RetrievalResult(
            nodes: scoredNodes,
            formattedContext: formattedContext,
            metadata: metadata
        )
    }
    
    /// Get formatted context string for LLM consumption
    public func getContext(
        for query: String,
        maxResults: Int? = nil,
        strategy: RetrievalStrategy? = nil,
        format: ContextFormat = .conversational,
        maxTokens: Int? = nil
    ) async throws -> String {
        let result = try await self.query(
            query,
            maxResults: maxResults,
            strategy: strategy
        )
        
        return formatContext(result.nodes, format: format, maxTokens: maxTokens)
    }
    
    // MARK: - Retrieval Strategies
    
    /// Vector-only retrieval (pure semantic search)
    private func vectorOnlyRetrieval(
        queryEmbedding: [Float],
        limit: Int,
        filters: [String: MetadataValue]?
    ) async throws -> ([ScoredNode], Int) {
        // Search vectors
        let vectorResults = try await vectorStore.search(
            query: queryEmbedding,
            k: limit * 2,
            threshold: Float(config.similarityThreshold)
        )
        
        // Convert to ScoredNodes by fetching full nodes
        var scoredNodes: [ScoredNode] = []
        for result in vectorResults {
            if let node = try await graphStore.getNode(result.nodeId) {
                scoredNodes.append(ScoredNode(node: node, score: Double(result.score)))
            }
        }
        
        return (scoredNodes, vectorResults.count)
    }
    
    /// Graph-only retrieval (keyword + traversal)
    private func graphOnlyRetrieval(
        query: String,
        limit: Int,
        filters: [String: MetadataValue]?
    ) async throws -> ([ScoredNode], Int) {
        // Extract keywords from query (alphanumeric only to ignore punctuation)
        let keywords = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        // Find nodes containing keywords
        var candidates: [Node] = []
        let allNodes = try await graphStore.getNodes(limit: limit * 3)
        
        for node in allNodes {
            let contentLower = node.content.lowercased()
            for keyword in keywords {
                if contentLower.contains(keyword) {
                    candidates.append(node)
                    break
                }
            }
        }
        
        // Score by keyword matches and recency
        var scoredNodes: [ScoredNode] = []
        for node in candidates {
            let keywordScore = calculateKeywordScore(node: node, keywords: keywords)
            let recencyScore = calculateRecencyScore(node: node)
            let finalScore = (keywordScore * 0.7) + (recencyScore * 0.3)
            
            scoredNodes.append(ScoredNode(node: node, score: finalScore))
        }
        
        // Sort by score
        scoredNodes.sort { $0.score > $1.score }
        
        return (scoredNodes, candidates.count)
    }
    
    /// Hybrid retrieval (vector + graph)
    private func hybridRetrieval(
        query: String,
        queryEmbedding: [Float],
        limit: Int,
        filters: [String: MetadataValue]?
    ) async throws -> ([ScoredNode], Int) {
        // Step 1: Vector search
        let vectorResults = try await vectorStore.search(
            query: queryEmbedding,
            k: limit * 2,
            threshold: Float(config.similarityThreshold)
        )
        
        // Step 2: Graph traversal from top results
        var graphCandidates = Set<NodeID>()
        
        for result in vectorResults.prefix(5) {
            graphCandidates.insert(result.nodeId)
            
            let neighbors = try await graphStore.getNeighbors(of: result.nodeId)
            for neighbor in neighbors {
                graphCandidates.insert(neighbor.id)
            }
        }
        
        // Step 3: Re-rank
        var scoredNodes: [ScoredNode] = []
        var vectorScoreMap: [NodeID: Float] = [:]
        
        for result in vectorResults {
            vectorScoreMap[result.nodeId] = result.score
        }
        
        for nodeId in graphCandidates {
            guard let node = try await graphStore.getNode(nodeId) else { continue }
            
            let vectorScore = Double(vectorScoreMap[nodeId] ?? 0)
            let recencyScore = calculateRecencyScore(node: node)
            let graphScore = vectorScoreMap[nodeId] != nil ? 1.0 : 0.5
            
            let finalScore = (vectorScore * 0.5) + (recencyScore * 0.3) + (graphScore * 0.2)
            
            scoredNodes.append(ScoredNode(node: node, score: finalScore))
        }
        
        scoredNodes.sort { $0.score > $1.score }
        
        return (scoredNodes, graphCandidates.count)
    }
    
    /// Temporal retrieval (time-aware)
    private func temporalRetrieval(
        queryEmbedding: [Float],
        limit: Int,
        filters: [String: MetadataValue]?
    ) async throws -> ([ScoredNode], Int) {
        let vectorResults = try await vectorStore.search(
            query: queryEmbedding,
            k: limit * 3,
            threshold: Float(config.similarityThreshold)
        )
        
        var scoredNodes: [ScoredNode] = []
        for result in vectorResults {
            if let node = try await graphStore.getNode(result.nodeId) {
                let vectorScore = Double(result.score)
                let recencyScore = calculateRecencyScore(node: node)
                
                let finalScore = (recencyScore * config.recencyWeight) +
                                (vectorScore * (1.0 - config.recencyWeight))
                
                scoredNodes.append(ScoredNode(node: node, score: finalScore))
            }
        }
        
        scoredNodes.sort { $0.score > $1.score }
        
        return (scoredNodes, vectorResults.count)
    }
    
    // MARK: - Scoring
    
    private func calculateKeywordScore(node: Node, keywords: [String]) -> Double {
        let contentLower = node.content.lowercased()
        var matches = 0
        
        for keyword in keywords {
            if contentLower.contains(keyword) {
                matches += 1
            }
        }
        
        return keywords.isEmpty ? 0 : Double(matches) / Double(keywords.count)
    }
    
    private func calculateRecencyScore(node: Node) -> Double {
        let ageInSeconds = Date().timeIntervalSince(node.createdAt)
        let ageInDays = ageInSeconds / 86400.0
        
        let decay = config.recencyDecayFactor
        return exp(-decay * ageInDays)
    }
    
    // MARK: - Filtering
    
    private func applyFilters(_ nodes: [ScoredNode], filters: [String: MetadataValue]) -> [ScoredNode] {
        return nodes.filter { scoredNode in
            for (key, value) in filters {
                guard let nodeValue = scoredNode.node.metadata[key] else {
                    return false
                }
                
                if nodeValue != value {
                    return false
                }
            }
            return true
        }
    }
    
    // MARK: - Context Formatting
    
    private func formatContext(
        _ nodes: [ScoredNode],
        format: ContextFormat,
        maxTokens: Int?
    ) -> String {
        guard !nodes.isEmpty else {
            return "No relevant context found."
        }
        
        var context = ""
        
        switch format {
        case .conversational:
            context = formatConversational(nodes)
        case .bulletPoints:
            context = formatBulletPoints(nodes)
        case .structured:
            context = formatStructured(nodes)
        case .raw:
            context = formatRaw(nodes)
        }
        
        if let maxTokens = maxTokens {
            let maxChars = maxTokens * 4
            if context.count > maxChars {
                let endIndex = context.index(context.startIndex, offsetBy: maxChars)
                context = String(context[..<endIndex]) + "..."
            }
        }
        
        return context
    }
    
    private func formatConversational(_ nodes: [ScoredNode]) -> String {
        var lines: [String] = []
        lines.append("Here's what I remember:")
        lines.append("")
        
        for (index, scoredNode) in nodes.enumerated() {
            let node = scoredNode.node
            let dateStr = formatDate(node.createdAt)
            lines.append("\(index + 1). \(node.content) (\(dateStr))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func formatBulletPoints(_ nodes: [ScoredNode]) -> String {
        nodes.map { "• \($0.node.content)" }.joined(separator: "\n")
    }
    
    private func formatStructured(_ nodes: [ScoredNode]) -> String {
        var lines: [String] = []
        lines.append("=== RELEVANT CONTEXT ===")
        lines.append("")
        
        for (index, scoredNode) in nodes.enumerated() {
            let node = scoredNode.node
            lines.append("--- Memory \(index + 1) ---")
            lines.append("Content: \(node.content)")
            lines.append("Type: \(node.type.rawValue)")
            lines.append("Created: \(formatDate(node.createdAt))")
            lines.append("Relevance: \(String(format: "%.2f", scoredNode.score))")
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func formatRaw(_ nodes: [ScoredNode]) -> String {
        nodes.map { $0.node.content }.joined(separator: "\n\n")
    }
    
    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else if interval < 604800 {
            return "\(Int(interval / 86400))d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Advanced Features
    
    public func getConversationContext(
        sessionID: String,
        includeRelevantMemories: Bool = true,
        maxTokens: Int = 2000
    ) async throws -> ConversationContext {
        let conversationNodes = try await graphStore.getNodes(limit: 100)
        
        var messages: [ConversationMessage] = []
        for node in conversationNodes {
            if node.type == .general,
               let sessionId = node.metadata["sessionId"],
               case .string(let sid) = sessionId,
               sid == sessionID {
                
                if let role = node.metadata["role"],
                   case .string(let roleStr) = role,
                   let messageRole = MessageRole(rawValue: roleStr) {
                    
                    messages.append(ConversationMessage(
                        role: messageRole,
                        content: node.content,
                        timestamp: node.createdAt
                    ))
                }
            }
        }
        
        messages.sort { $0.timestamp < $1.timestamp }
        
        var relevantMemories: [ScoredNode] = []
        if includeRelevantMemories && !messages.isEmpty {
            if let lastUserMessage = messages.last(where: { $0.role == .user }) {
                let result = try await query(
                    lastUserMessage.content,
                    maxResults: 5,
                    strategy: .hybrid
                )
                relevantMemories = result.nodes
            }
        }
        
        // Format context
        let formattedContext = formatContext(relevantMemories, format: .conversational, maxTokens: maxTokens)
        let estimatedTokens = formattedContext.count / 4
        
        return ConversationContext(
            sessionID: sessionID,
            messages: messages,
            relevantMemories: relevantMemories,
            formattedContext: formattedContext,
            estimatedTokens: estimatedTokens
        )
    }
    
    public func findEntity(_ entityName: String, type: EntityType? = nil) async throws -> Entity? {
        let allNodes = try await graphStore.getNodes(limit: 1000)
        
        for node in allNodes {
            if let entities = node.metadata["entities"],
               case .array(let entityArray) = entities {
                
                for entityValue in entityArray {
                    if case .dictionary(let entityDict) = entityValue,
                       case .string(let name) = entityDict["name"],
                       name.lowercased() == entityName.lowercased() {
                        
                        if let type = type,
                           case .string(let typeStr) = entityDict["type"],
                           typeStr != type.rawValue {
                            continue
                        }
                        
                        let entityType = entityDict["type"].flatMap {
                            if case .string(let t) = $0 { return EntityType(rawValue: t) }
                            return nil
                        } ?? .other
                        
                        return Entity(
                            name: name,
                            type: entityType,
                            sourceNodeID: node.id,
                            confidence: 1.0
                        )
                    }
                }
            }
        }
        
        return nil
    }
    
    public func getTimeline(
        from startDate: Date,
        to endDate: Date,
        filters: [String: MetadataValue]? = nil
    ) async throws -> [TimelineEvent] {
        var nodes = try await graphStore.getNodes(
            createdAfter: startDate,
            createdBefore: endDate
        )
        
        if let filters = filters {
            nodes = nodes.filter { node in
                for (key, value) in filters {
                    guard let nodeValue = node.metadata[key], nodeValue == value else {
                        return false
                    }
                }
                return true
            }
        }
        
        return nodes.map { node in
            TimelineEvent(
                id: node.id,
                node: node,
                timestamp: node.createdAt
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }
    
    public func getInsights() async throws -> MemoryInsights {
        let stats = try await graphStore.getStats()
        let allNodes = try await graphStore.getNodes(limit: 10000)
        
        var entityMap: [String: (entity: Entity, count: Int)] = [:]
        for node in allNodes {
            if let entities = node.metadata["entities"],
               case .array(let entityArray) = entities {
                for entityValue in entityArray {
                    if case .dictionary(let entityDict) = entityValue,
                       case .string(let name) = entityDict["name"],
                       case .string(let typeStr) = entityDict["type"],
                       let entityType = EntityType(rawValue: typeStr) {
                        
                        let entity = Entity(
                            name: name,
                            type: entityType,
                            sourceNodeID: node.id
                        )
                        
                        if var existing = entityMap[name] {
                            existing.count += 1
                            entityMap[name] = existing
                        } else {
                            entityMap[name] = (entity, 1)
                        }
                    }
                }
            }
        }
        
        let topEntities = entityMap.values
            .sorted { $0.count > $1.count }
            .prefix(10)
            .map { EntityFrequency(entity: $0.entity, count: $0.count) }
        
        var topicFreq: [String: Int] = [:]
        for node in allNodes {
            let words = node.content.lowercased().split(separator: " ")
            for word in words where word.count > 4 {
                topicFreq[String(word), default: 0] += 1
            }
        }
        
        let dates = allNodes.map { $0.createdAt }
        let dateRange: DateInterval? = if let min = dates.min(), let max = dates.max() {
            DateInterval(start: min, end: max)
        } else {
            nil
        }
        
        return MemoryInsights(
            totalNodes: stats.nodeCount,
            totalRelationships: stats.edgeCount,
            topEntities: topEntities,
            frequentTopics: topicFreq,
            storageSize: stats.dbSize,
            dateRange: dateRange
        )
    }
}
