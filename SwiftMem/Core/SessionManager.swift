//
//  Session.swift
//  SwiftMem
//
//  Created by Sankritya Thakur on 12/7/25.
//


//
//  SessionManager.swift
//  SwiftMem - Session Grouping & Multi-Session Retrieval
//
//  Groups memories by conversation session for temporal reasoning
//

import Foundation

// MARK: - Session

/// Represents a conversation session
public struct Session: Identifiable, Codable, Equatable {
    public let id: SessionID
    public let startDate: Date
    public var endDate: Date?
    public let type: SessionType
    public var metadata: [String: MetadataValue]
    
    public init(
        id: SessionID = SessionID(),
        startDate: Date = Date(),
        endDate: Date? = nil,
        type: SessionType = .chat,
        metadata: [String: MetadataValue] = [:]
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.type = type
        self.metadata = metadata
    }
}

public struct SessionID: Identifiable, Codable, Equatable, Hashable {
    public let value: UUID
    public var id: UUID { value }
    
    public init(value: UUID = UUID()) {
        self.value = value
    }
}

public enum SessionType: String, Codable {
    case chat = "chat"
    case voiceNote = "voice_note"
    case import = "import"
    case batch = "batch"
    case system = "system"
}

// MARK: - Session Query

/// Query parameters for session-based retrieval
public struct SessionQuery {
    /// Get memories from specific sessions
    public let sessionIds: [SessionID]?
    
    /// Get memories from date range
    public let dateRange: (start: Date, end: Date)?
    
    /// Get memories from session type
    public let sessionType: SessionType?
    
    /// Maximum sessions to retrieve
    public let limit: Int?
    
    /// Include session metadata in results
    public let includeMetadata: Bool
    
    public init(
        sessionIds: [SessionID]? = nil,
        dateRange: (Date, Date)? = nil,
        sessionType: SessionType? = nil,
        limit: Int? = nil,
        includeMetadata: Bool = true
    ) {
        self.sessionIds = sessionIds
        self.dateRange = dateRange
        self.sessionType = sessionType
        self.limit = limit
        self.includeMetadata = includeMetadata
    }
}

// MARK: - Session Manager

/// Manages conversation sessions and multi-session retrieval
public actor SessionManager {
    private let graphStore: GraphStore
    private var activeSessions: [SessionID: Session] = [:]
    
    public init(graphStore: GraphStore) {
        self.graphStore = graphStore
    }
    
    // MARK: - Session Management
    
    /// Start a new session
    public func startSession(
        type: SessionType = .chat,
        metadata: [String: MetadataValue] = [:]
    ) -> Session {
        let session = Session(
            startDate: Date(),
            type: type,
            metadata: metadata
        )
        
        activeSessions[session.id] = session
        return session
    }
    
    /// End a session
    public func endSession(_ sessionId: SessionID) {
        guard var session = activeSessions[sessionId] else { return }
        session.endDate = Date()
        activeSessions[sessionId] = session
    }
    
    /// Get active session
    public func getActiveSession(_ sessionId: SessionID) -> Session? {
        return activeSessions[sessionId]
    }
    
    // MARK: - Memory Storage with Sessions
    
    /// Store a memory with session context
    public func storeMemory(
        _ node: Node,
        sessionId: SessionID,
        messageIndex: Int? = nil
    ) async throws {
        // Add session metadata to node
        var nodeWithSession = node
        nodeWithSession.metadata["session_id"] = .string(sessionId.value.uuidString)
        
        if let index = messageIndex {
            nodeWithSession.metadata["message_index"] = .int(index)
        }
        
        if let session = activeSessions[sessionId] {
            nodeWithSession.metadata["session_start"] = .string(
                ISO8601DateFormatter().string(from: session.startDate)
            )
            nodeWithSession.metadata["session_type"] = .string(session.type.rawValue)
        }
        
        // Store node
        try await graphStore.storeNode(nodeWithSession)
        
        // Link to previous message in session if exists
        if let prevNode = try await getLastMemoryInSession(sessionId) {
            let edge = Edge(
                fromNodeID: node.id,
                toNodeID: prevNode.id,
                relationshipType: .sameSession,
                metadata: [
                    "session_id": .string(sessionId.value.uuidString)
                ]
            )
            try await graphStore.storeEdge(edge)
        }
    }
    
    /// Store multiple memories in a session
    public func storeMemories(
        _ nodes: [Node],
        sessionId: SessionID
    ) async throws {
        for (index, node) in nodes.enumerated() {
            try await storeMemory(node, sessionId: sessionId, messageIndex: index)
        }
    }
    
    // MARK: - Session Retrieval
    
    /// Get all memories from a session
    public func getMemories(
        fromSession sessionId: SessionID,
        orderBy: SessionOrder = .chronological
    ) async throws -> [Node] {
        let nodes = try await graphStore.getNodes(
            filters: [
                .metadataValue("session_id", .string(sessionId.value.uuidString))
            ]
        )
        
        // Sort by message_index if available
        let sorted = nodes.sorted { a, b in
            guard let aIndex = a.metadata["message_index"]?.intValue,
                  let bIndex = b.metadata["message_index"]?.intValue else {
                // Fallback to creation date
                return orderBy == .chronological ? 
                    a.createdAt < b.createdAt : 
                    a.createdAt > b.createdAt
            }
            
            return orderBy == .chronological ? aIndex < bIndex : aIndex > bIndex
        }
        
        return sorted
    }
    
    /// Get memories from multiple sessions
    public func getMemories(query: SessionQuery) async throws -> [Node] {
        var allNodes: [Node] = []
        
        // Query by session IDs
        if let sessionIds = query.sessionIds {
            for sessionId in sessionIds {
                let nodes = try await getMemories(fromSession: sessionId)
                allNodes.append(contentsOf: nodes)
            }
        }
        
        // Query by date range
        else if let (start, end) = query.dateRange {
            let nodes = try await graphStore.getNodes(
                filters: [
                    .createdAfter(start),
                    .createdBefore(end)
                ]
            )
            allNodes = nodes
        }
        
        // Query by session type
        else if let sessionType = query.sessionType {
            let nodes = try await graphStore.getNodes(
                filters: [
                    .metadataValue("session_type", .string(sessionType.rawValue))
                ]
            )
            allNodes = nodes
        }
        
        // Apply limit
        if let limit = query.limit {
            allNodes = Array(allNodes.prefix(limit))
        }
        
        return allNodes
    }
    
    /// Get unique sessions in date range
    public func getSessions(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [SessionID] {
        let nodes = try await graphStore.getNodes(
            filters: [
                .createdAfter(startDate),
                .createdBefore(endDate)
            ]
        )
        
        // Extract unique session IDs
        var sessionIds = Set<SessionID>()
        for node in nodes {
            if let sessionIdString = node.metadata["session_id"]?.stringValue,
               let uuid = UUID(uuidString: sessionIdString) {
                sessionIds.insert(SessionID(value: uuid))
            }
        }
        
        return Array(sessionIds)
    }
    
    /// Get session timeline (grouped by date)
    public func getSessionTimeline(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [Date: [SessionID]] {
        let sessions = try await getSessions(from: startDate, to: endDate)
        
        var timeline: [Date: [SessionID]] = [:]
        
        for sessionId in sessions {
            let memories = try await getMemories(fromSession: sessionId)
            if let firstMemory = memories.first {
                let day = Calendar.current.startOfDay(for: firstMemory.createdAt)
                timeline[day, default: []].append(sessionId)
            }
        }
        
        return timeline
    }
    
    // MARK: - Private Helpers
    
    private func getLastMemoryInSession(_ sessionId: SessionID) async throws -> Node? {
        let memories = try await getMemories(fromSession: sessionId, orderBy: .reverseChronological)
        return memories.first
    }
}

// MARK: - Session Order

public enum SessionOrder {
    case chronological
    case reverseChronological
}

// MARK: - MetadataValue Extensions

extension MetadataValue {
    var intValue: Int? {
        if case .int(let value) = self {
            return value
        }
        return nil
    }
    
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}