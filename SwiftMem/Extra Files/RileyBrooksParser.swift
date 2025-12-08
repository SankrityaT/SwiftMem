//
//  RileyBrooksParser.swift
//  SwiftMem
//
//  Created by Sankritya Thakur on 12/7/25.
//


//
//  RileyBrooksParser.swift
//  SwiftMem
//
//  Parse Riley Brooks journal format into SwiftMem nodes
//

import Foundation

struct RileyBrooksParser {
    
    static func parseToNodes(from jsonData: Data) throws -> [Node] {
        let decoder = JSONDecoder()
        let rileyData = try decoder.decode(RileyBrooksData.self, from: jsonData)
        
        var nodes: [Node] = []
        
        // Parse journal entries
        for dayEntry in rileyData.dayEntries {
            guard let date = parseDate(dayEntry.date) else { continue }
            
            // Process journal entries
            for journalEntry in dayEntry.daily.journalEntries {
                let metadata: [String: MetadataValue] = [
                    "date": .string(dayEntry.date),
                    "source": .string("journal"),
                    "tags": .array(journalEntry.tags.map { .string($0) })
                ]
                
                let node = Node(
                    content: journalEntry.text,
                    type: .episodic,
                    metadata: metadata,
                    createdAt: date
                )
                nodes.append(node)
            }
            
            // Process coaching sessions
            for coachSession in dayEntry.daily.coachSession ?? [] {
                if !coachSession.summary.isEmpty {
                    let metadata: [String: MetadataValue] = [
                        "date": .string(dayEntry.date),
                        "source": .string("coaching"),
                        "title": .string(coachSession.title)
                    ]
                    
                    let node = Node(
                        content: coachSession.summary,
                        type: .semantic,
                        metadata: metadata,
                        createdAt: date
                    )
                    nodes.append(node)
                }
            }
            
            // Process habit tracking
            if !dayEntry.daily.habitValues.isEmpty {
                let habitText = dayEntry.daily.habitValues.keys.joined(separator: ", ")
                let metadata: [String: MetadataValue] = [
                    "date": .string(dayEntry.date),
                    "source": .string("habits")
                ]
                
                let node = Node(
                    content: "Completed habits: \(habitText)",
                    type: .procedural,
                    metadata: metadata,
                    createdAt: date
                )
                nodes.append(node)
            }
            
            // Process mood/performance tracking
            if let mood = dayEntry.daily.trackValues["Mood"],
               let performance = dayEntry.daily.trackValues["Performance"] {
                let metadata: [String: MetadataValue] = [
                    "date": .string(dayEntry.date),
                    "source": .string("tracking"),
                    "mood": .int(mood),
                    "performance": .int(performance)
                ]
                
                let node = Node(
                    content: "Mood: \(mood)/10, Performance: \(performance)/10",
                    type: .emotional,
                    metadata: metadata,
                    createdAt: date
                )
                nodes.append(node)
            }
        }
        
        return nodes
    }
    
    private static func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter.date(from: dateString)
    }
}

// MARK: - Decodable Models

struct RileyBrooksData: Decodable {
    let dayEntries: [DayEntry]
    let habitAreas: [HabitArea]?
    let trackAreas: [TrackArea]?
    let user: UserInfo?
}

struct DayEntry: Decodable {
    let date: String
    let daily: DailyData
}

struct DailyData: Decodable {
    let journalEntries: [JournalEntry]
    let coachSession: [CoachSession]?
    let habitValues: [String: Bool]
    let trackValues: [String: Int]
}

struct JournalEntry: Decodable {
    let text: String
    let tags: [String]
}

struct CoachSession: Decodable {
    let title: String
    let summary: String
    let sessionDescription: String?
    let isComplete: Bool?
}

struct HabitArea: Decodable {
    let area: String
    let targetValue: Int
}

struct TrackArea: Decodable {
    let area: String
    let targetValue: Int
}

struct UserInfo: Decodable {
    let name: String
    let age: Int?
    let affirmation: String?
    let context: String?
}
