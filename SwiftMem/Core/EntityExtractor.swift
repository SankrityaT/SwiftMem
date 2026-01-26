//
//  EntityExtractor.swift
//  SwiftMem - Entity Extraction
//
//  Extracts structured entities from memory content for smart conflict detection
//

import Foundation

// MARK: - Extracted Entities

/// A structured fact extracted from memory content
public struct ExtractedFact: Codable, Equatable {
    /// The subject of the fact (e.g., "favorite color", "job", "location")
    public let subject: String
    
    /// The value or object (e.g., "blue", "Google", "San Francisco")
    public let value: String
    
    /// Confidence in extraction (0.0 to 1.0)
    public let confidence: Float
    
    /// How this was extracted
    public let extractionMethod: ExtractionMethod
    
    /// Optional temporal context
    public let temporal: TemporalContext?
    
    public init(
        subject: String,
        value: String,
        confidence: Float,
        extractionMethod: ExtractionMethod,
        temporal: TemporalContext? = nil
    ) {
        self.subject = subject
        self.value = value
        self.confidence = confidence
        self.extractionMethod = extractionMethod
        self.temporal = temporal
    }
}

/// How an entity was extracted
public enum ExtractionMethod: String, Codable {
    case patternMatch = "pattern_match"
    case llm = "llm"
    case hybrid = "hybrid"
}

/// Temporal context for a fact
public struct TemporalContext: Codable, Equatable {
    public let type: TemporalType
    public let date: Date?
    public let text: String
    
    public init(type: TemporalType, date: Date? = nil, text: String) {
        self.type = type
        self.date = date
        self.text = text
    }
}

public enum TemporalType: String, Codable {
    case past = "past"
    case present = "present"
    case future = "future"
    case specific = "specific"
}

// MARK: - Extraction Patterns

/// Pattern-based extraction rules
struct ExtractionPattern {
    let pattern: String
    let subjectExtractor: (String) -> String?
    let valueExtractor: (String) -> String?
    let confidence: Float
    
    func extract(from text: String) -> ExtractedFact? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        
        guard let subject = subjectExtractor(text),
              let value = valueExtractor(text) else {
            return nil
        }
        
        return ExtractedFact(
            subject: subject.lowercased(),
            value: value,
            confidence: confidence,
            extractionMethod: .patternMatch
        )
    }
}

// MARK: - Entity Extractor

/// Extracts structured entities from memory content
public actor EntityExtractor {
    private let patterns: [ExtractionPattern]
    
    public init() {
        // Initialize common patterns
        self.patterns = EntityExtractor.buildPatterns()
    }
    
    // MARK: - Public API
    
    /// Extract facts from memory content
    public func extractFacts(from content: String) async -> [ExtractedFact] {
        var facts: [ExtractedFact] = []
        
        // Try pattern matching first (fast)
        for pattern in patterns {
            if let fact = pattern.extract(from: content) {
                facts.append(fact)
            }
        }
        
        // If no patterns matched, use simple heuristic extraction
        // Extract key entities from conversational text
        if facts.isEmpty {
            facts.append(contentsOf: extractEntitiesHeuristic(from: content))
        }
        
        return facts
    }
    
    /// Extract entities using enhanced heuristics (fallback when patterns don't match)
    /// Optimized for local-first privacy approach without cloud LLMs
    private func extractEntitiesHeuristic(from content: String) -> [ExtractedFact] {
        var facts: [ExtractedFact] = []
        let lower = content.lowercased()
        
        // Comprehensive topic categories for coaching/personal development context
        let topicCategories: [String: Set<String>] = [
            "mental_health": ["stress", "anxiety", "depression", "mental", "emotional", "feelings", "mood", "therapy", "therapist", "counseling"],
            "relationships": ["family", "relationship", "partner", "spouse", "marriage", "dating", "friendship", "social", "connection", "communication"],
            "career": ["work", "job", "career", "professional", "business", "project", "meeting", "deadline", "promotion", "salary"],
            "health": ["health", "fitness", "exercise", "workout", "diet", "nutrition", "sleep", "energy", "physical", "body"],
            "personal_growth": ["growth", "development", "learning", "skill", "improvement", "progress", "goal", "achievement", "success"],
            "wellbeing": ["wellbeing", "wellness", "balance", "boundaries", "self-care", "mindfulness", "meditation", "peace", "calm"],
            "productivity": ["productivity", "focus", "concentration", "efficiency", "time", "management", "organization", "planning"],
            "creativity": ["creative", "creativity", "art", "design", "writing", "music", "hobby", "passion", "inspiration"],
            "finance": ["money", "financial", "budget", "savings", "investment", "debt", "income", "expense"],
            "life_purpose": ["purpose", "meaning", "values", "mission", "vision", "legacy", "impact", "contribution"]
        ]
        
        // Extract topics by category
        for (category, keywords) in topicCategories {
            for keyword in keywords {
                if lower.contains(keyword) {
                    facts.append(ExtractedFact(
                        subject: "topic",
                        value: category,
                        confidence: 0.8,
                        extractionMethod: .patternMatch
                    ))
                    break // Only add category once
                }
            }
        }
        
        // Extract specific keywords that appear (more granular than categories)
        let words = content.components(separatedBy: .whitespacesAndNewlines)
        let allTopicWords = topicCategories.values.flatMap { $0 }
        for word in words {
            let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if allTopicWords.contains(cleanWord) && cleanWord.count > 3 {
                facts.append(ExtractedFact(
                    subject: "keyword",
                    value: cleanWord,
                    confidence: 0.7,
                    extractionMethod: .patternMatch
                ))
            }
        }
        
        // Extract capitalized words (potential names, places, organizations)
        let capitalizedWords = words.filter { word in
            guard word.count > 2 else { return false }
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            return clean.first?.isUppercase == true && clean.dropFirst().allSatisfy { $0.isLowercase || $0.isNumber }
        }
        
        let excludedWords = Set(["I", "The", "A", "An", "My", "Your", "His", "Her", "Their", "Our", "This", "That", "These", "Those", "Today", "Yesterday", "Tomorrow"])
        for name in capitalizedWords.prefix(5) {
            let clean = name.trimmingCharacters(in: .punctuationCharacters)
            if clean.count > 2 && !excludedWords.contains(clean) {
                facts.append(ExtractedFact(
                    subject: "entity",
                    value: clean,
                    confidence: 0.6,
                    extractionMethod: .patternMatch
                ))
            }
        }
        
        // Extract emotional indicators
        let emotions: [String: Float] = [
            "happy": 0.8, "sad": 0.8, "angry": 0.8, "frustrated": 0.8, "excited": 0.8,
            "anxious": 0.8, "stressed": 0.8, "calm": 0.8, "peaceful": 0.8, "grateful": 0.8,
            "overwhelmed": 0.8, "confident": 0.8, "motivated": 0.8, "tired": 0.7, "energized": 0.7
        ]
        
        for (emotion, confidence) in emotions {
            if lower.contains(emotion) {
                facts.append(ExtractedFact(
                    subject: "emotion",
                    value: emotion,
                    confidence: confidence,
                    extractionMethod: .patternMatch
                ))
            }
        }
        
        // Extract action verbs (what user is doing/planning)
        let actionVerbs = ["working", "building", "creating", "learning", "studying", "practicing", "improving", "developing", "planning", "organizing", "managing", "leading", "teaching", "helping", "supporting"]
        for verb in actionVerbs {
            if lower.contains(verb) {
                facts.append(ExtractedFact(
                    subject: "action",
                    value: verb,
                    confidence: 0.6,
                    extractionMethod: .patternMatch
                ))
            }
        }
        
        return facts
    }
    
    /// Compare two sets of facts to find conflicts
    public func findConflictingFacts(
        newFacts: [ExtractedFact],
        oldFacts: [ExtractedFact]
    ) -> [(new: ExtractedFact, old: ExtractedFact)] {
        var conflicts: [(ExtractedFact, ExtractedFact)] = []
        
        for newFact in newFacts {
            for oldFact in oldFacts {
                // Same subject but different value = conflict
                if newFact.subject == oldFact.subject &&
                   newFact.value != oldFact.value {
                    conflicts.append((newFact, oldFact))
                }
            }
        }
        
        return conflicts
    }
    
    // MARK: - Pattern Building
    
    private static func buildPatterns() -> [ExtractionPattern] {
        var patterns: [ExtractionPattern] = []
        
        // Pattern 1: "My favorite X is Y"
        patterns.append(ExtractionPattern(
            pattern: "my favorite (\\w+) is ([\\w\\s]+)",
            subjectExtractor: { text in
                guard let regex = try? NSRegularExpression(pattern: "my favorite (\\w+)", options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return "favorite " + String(text[range])
            },
            valueExtractor: { text in
                guard let regex = try? NSRegularExpression(pattern: "is ([\\w\\s]+?)(?:\\.|$)", options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            },
            confidence: 0.9
        ))
        
        // Pattern 2: "I work at X"
        patterns.append(ExtractionPattern(
            pattern: "I work at ([\\w\\s]+)",
            subjectExtractor: { _ in "employment" },
            valueExtractor: { text in
                guard let regex = try? NSRegularExpression(pattern: "I work at ([\\w\\s]+?)(?:\\s+as|\\.|$)", options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            },
            confidence: 0.95
        ))
        
        // Pattern 3: "I work at X as Y"
        patterns.append(ExtractionPattern(
            pattern: "I work at ([\\w\\s]+) as ([\\w\\s]+)",
            subjectExtractor: { _ in "job title" },
            valueExtractor: { text in
                guard let regex = try? NSRegularExpression(pattern: "as ([\\w\\s]+?)(?:\\.|$)", options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            },
            confidence: 0.95
        ))
        
        // Pattern 4: "I live in X"
        patterns.append(ExtractionPattern(
            pattern: "I live in ([\\w\\s,]+)",
            subjectExtractor: { _ in "location" },
            valueExtractor: { text in
                guard let regex = try? NSRegularExpression(pattern: "I live in ([\\w\\s,]+?)(?:\\.|$)", options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            },
            confidence: 0.9
        ))
        
        // Pattern 5: "My name is X"
        patterns.append(ExtractionPattern(
            pattern: "my name is ([\\w\\s]+)",
            subjectExtractor: { _ in "name" },
            valueExtractor: { text in
                guard let regex = try? NSRegularExpression(pattern: "my name is ([\\w\\s]+?)(?:\\sand\\s|\\.|$)", options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            },
            confidence: 0.95
        ))
        
        // Pattern 6: "I am X" (profession, state, etc.)
        patterns.append(ExtractionPattern(
            pattern: "I am (?:a |an )?([\\w\\s]+)",
            subjectExtractor: { text in
                // Try to infer subject from value
                let lower = text.lowercased()
                if lower.contains("developer") || lower.contains("engineer") ||
                   lower.contains("designer") || lower.contains("manager") {
                    return "profession"
                } else if lower.contains("vegetarian") || lower.contains("vegan") {
                    return "diet"
                } else {
                    return "attribute"
                }
            },
            valueExtractor: { text in
                guard let regex = try? NSRegularExpression(pattern: "I am (?:a |an )?([\\w\\s]+?)(?:\\.|$)", options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            },
            confidence: 0.8
        ))
        
        // Pattern 7: "I prefer X"
        patterns.append(ExtractionPattern(
            pattern: "I prefer ([\\w\\s]+)",
            subjectExtractor: { _ in "preference" },
            valueExtractor: { text in
                guard let regex = try? NSRegularExpression(pattern: "I prefer ([\\w\\s]+?)(?:\\.|$)", options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            },
            confidence: 0.85
        ))
        
        // Pattern 8: "I love X" / "I hate X"
        patterns.append(ExtractionPattern(
            pattern: "I (love|hate) ([\\w\\s]+)",
            subjectExtractor: { text in
                if text.lowercased().contains("love") {
                    return "loves"
                } else {
                    return "hates"
                }
            },
            valueExtractor: { text in
                guard let regex = try? NSRegularExpression(pattern: "I (?:love|hate) ([\\w\\s]+?)(?:\\.|$)", options: .caseInsensitive),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            },
            confidence: 0.85
        ))
        
        return patterns
    }
}

// MARK: - Enhanced Conflict Detection

extension ConflictDetector {
    /// Detect conflicts using entity extraction (smarter)
    public func detectConflictsWithEntities(for newNode: Node) async throws -> [ConflictingMemory] {
        // Extract entities from new node
        let extractor = EntityExtractor()
        let newFacts = await extractor.extractFacts(from: newNode.content)
        
        // If no facts extracted, fall back to similarity-based detection
        guard !newFacts.isEmpty else {
            return try await detectConflicts(for: newNode)
        }
        
        // Get candidates
        let candidates = try await getCandidates(for: newNode)
        
        var conflicts: [ConflictingMemory] = []
        
        for candidate in candidates {
            // Extract facts from candidate
            let oldFacts = await extractor.extractFacts(from: candidate.content)
            
            // Find conflicting facts
            let factConflicts = await extractor.findConflictingFacts(
                newFacts: newFacts,
                oldFacts: oldFacts
            )
            
            if !factConflicts.isEmpty {
                // Calculate similarity for confidence
                let newEmbedding = try await embeddingEngine.embed(newNode.content)
                guard let oldEmbedding = try await vectorStore.getVector(for: candidate.id) else {
                    continue
                }
                let similarity = cosineSimilarity(newEmbedding, oldEmbedding)
                
                // Determine conflict type based on facts
                let conflictType: ConflictType = factConflicts.count > 1 ? .supersedes : .updates
                
                conflicts.append(ConflictingMemory(
                    oldNode: candidate,
                    newNode: newNode,
                    similarity: similarity,
                    conflictType: conflictType,
                    confidence: min(similarity + 0.1, 1.0), // Boost confidence with entity match
                    reason: "Conflicting facts: \(factConflicts.map { "\($0.new.subject)" }.joined(separator: ", "))"
                ))
            }
        }
        
        return conflicts.sorted { $0.confidence > $1.confidence }
    }
}
