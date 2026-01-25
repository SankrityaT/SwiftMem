//
//  ExactMatchBooster.swift
//  SwiftMem
//
//  Created by Sankritya on 2026-01-23.
//  Boost retrieval scores for exact keyword matches
//

import Foundation

/// Boosts retrieval scores when query keywords appear in content
/// This helps with single-session-user queries that need literal recall
public struct ExactMatchBooster {
    
    /// Boost score based on exact keyword matches
    public static func boost(
        content: String,
        query: String,
        baseScore: Double
    ) -> Double {
        let contentLower = content.lowercased()
        let queryLower = query.lowercased()
        
        // Extract keywords (remove stop words)
        let queryKeywords = extractKeywords(from: queryLower)
        let contentKeywords = Set(extractKeywords(from: contentLower))
        
        // Count exact matches
        var matchCount = 0
        var totalKeywords = queryKeywords.count
        
        for keyword in queryKeywords {
            if contentKeywords.contains(keyword) {
                matchCount += 1
            }
        }
        
        guard totalKeywords > 0 else { return baseScore }
        
        // Calculate match ratio
        let matchRatio = Double(matchCount) / Double(totalKeywords)
        
        // Apply boost (up to 2x for perfect match)
        let boost = 1.0 + matchRatio
        
        return baseScore * boost
    }
    
    /// Extract meaningful keywords (remove stop words)
    private static func extractKeywords(from text: String) -> [String] {
        let stopWords = Set([
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "as", "is", "was", "are", "were", "be",
            "been", "being", "have", "has", "had", "do", "does", "did", "will",
            "would", "should", "could", "may", "might", "must", "can", "i", "you",
            "he", "she", "it", "we", "they", "my", "your", "his", "her", "its",
            "our", "their", "what", "when", "where", "who", "why", "how"
        ])
        
        return text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 && !stopWords.contains($0) }
    }
}
