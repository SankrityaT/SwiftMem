//
//  AdvancedEntityExtractor.swift
//  SwiftMem
//
//  Enhanced rule-based entity and fact extraction
//  With extension points for future LLM enhancement
//

import Foundation

/// Result of extraction from memory content
public struct ExtractionResult: Equatable {
    public var facts: [Fact]
    public var entities: [TrackedEntity]
    public var temporalInfo: TemporalInfo
    public var emotionalValence: EmotionalValence

    public init(
        facts: [Fact] = [],
        entities: [TrackedEntity] = [],
        temporalInfo: TemporalInfo = TemporalInfo(),
        emotionalValence: EmotionalValence = EmotionalValence()
    ) {
        self.facts = facts
        self.entities = entities
        self.temporalInfo = temporalInfo
        self.emotionalValence = emotionalValence
    }
}

/// Enhanced entity and fact extractor
/// Rule-based with LLM extension point for future
public actor AdvancedEntityExtractor {

    // MARK: - Extraction Patterns

    /// Pattern definition for fact extraction
    private struct FactPattern {
        let regex: NSRegularExpression
        let predicateCategory: PredicateCategory
        let subjectExtractor: (String, NSTextCheckingResult) -> String?
        let predicateExtractor: (String, NSTextCheckingResult) -> String?
        let objectExtractor: (String, NSTextCheckingResult) -> String?
        let confidence: Float
    }

    private var factPatterns: [FactPattern] = []

    // MARK: - Initialization

    public init() {
        buildFactPatterns()
    }

    // MARK: - Public API

    /// Extract all structured data from content
    public func extract(
        from content: String,
        sourceMemoryId: UUID,
        userId: String
    ) async -> ExtractionResult {
        var result = ExtractionResult()

        // Extract facts using patterns
        result.facts = extractFacts(from: content, sourceMemoryId: sourceMemoryId)

        // Extract entities
        result.entities = extractEntities(from: content, userId: userId)

        // Extract temporal info (delegated to TemporalExtractor)
        // Will be set externally

        // Extract emotional valence
        result.emotionalValence = extractEmotionalValence(from: content)

        return result
    }

    /// Extract only facts
    public func extractFacts(from content: String, sourceMemoryId: UUID) -> [Fact] {
        var facts: [Fact] = []

        // Try pattern-based extraction
        for pattern in factPatterns {
            if let fact = extractWithPattern(pattern, from: content, sourceMemoryId: sourceMemoryId) {
                facts.append(fact)
            }
        }

        // Fallback heuristics if no patterns matched
        if facts.isEmpty {
            facts.append(contentsOf: extractFactsHeuristic(from: content, sourceMemoryId: sourceMemoryId))
        }

        return facts
    }

    /// Extract only entities
    public func extractEntities(from content: String, userId: String) -> [TrackedEntity] {
        var entities: [TrackedEntity] = []

        // Extract people
        entities.append(contentsOf: extractPeople(from: content, userId: userId))

        // Extract places
        entities.append(contentsOf: extractPlaces(from: content, userId: userId))

        // Extract dates
        entities.append(contentsOf: extractDates(from: content, userId: userId))

        // Extract organizations
        entities.append(contentsOf: extractOrganizations(from: content, userId: userId))

        // Extract goals
        entities.append(contentsOf: extractGoals(from: content, userId: userId))

        return entities
    }

    // MARK: - Pattern Building

    private func buildFactPatterns() {
        factPatterns = []

        // "I live in X"
        if let regex = try? NSRegularExpression(pattern: "\\b[Ii] (?:live|reside|stay|am based|am located) in ([\\w\\s,]+?)(?:\\.|,|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .location,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { _, _ in "lives_in" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.9
            ))
        }

        // "I moved to X"
        if let regex = try? NSRegularExpression(pattern: "\\b[Ii] (?:moved|relocated|am moving) to ([\\w\\s,]+?)(?:\\.|,|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .location,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { _, _ in "lives_in" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.85
            ))
        }

        // "I work at X"
        if let regex = try? NSRegularExpression(pattern: "\\b[Ii] (?:work|am employed|am working) at ([\\w\\s]+?)(?:\\s+as|\\.|,|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .attribute,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { _, _ in "works_at" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.9
            ))
        }

        // "I am a X" (profession)
        if let regex = try? NSRegularExpression(pattern: "\\b[Ii] am (?:a |an )?([\\w\\s]+?)(?:\\s+at|\\s+who|\\.|,|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .attribute,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { text, _ in
                    let lower = text.lowercased()
                    if lower.contains("developer") || lower.contains("engineer") ||
                       lower.contains("designer") || lower.contains("manager") ||
                       lower.contains("doctor") || lower.contains("teacher") ||
                       lower.contains("writer") || lower.contains("artist") {
                        return "profession"
                    }
                    return "attribute"
                },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.8
            ))
        }

        // "My favorite X is Y"
        if let regex = try? NSRegularExpression(pattern: "\\b[Mm]y favorite (\\w+) is ([\\w\\s]+?)(?:\\.|,|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .preference,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return "favorite" }
                    return "favorite_\(String(text[range]).lowercased())"
                },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 2), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.9
            ))
        }

        // "I like/love X"
        if let regex = try? NSRegularExpression(pattern: "\\b[Ii] (?:like|love|enjoy|prefer) ([\\w\\s]+?)(?:\\.|,|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .preference,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { _, _ in "likes" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.85
            ))
        }

        // "I hate/dislike X"
        if let regex = try? NSRegularExpression(pattern: "\\b[Ii] (?:hate|dislike|can't stand|avoid) ([\\w\\s]+?)(?:\\.|,|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .preference,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { _, _ in "dislikes" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.85
            ))
        }

        // "My mom/dad/X is Y" or "My X's name is Y"
        if let regex = try? NSRegularExpression(pattern: "\\b[Mm]y (mom|mother|dad|father|brother|sister|partner|wife|husband|boss|friend)'?s? (?:name is |is called |is )?([\\w]+)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .relationship,
                subjectExtractor: { text, match in
                    guard let range = Range(match.range(at: 2), in: text) else { return nil }
                    return String(text[range])
                },
                predicateExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return "relationship" }
                    return "is_\(String(text[range]).lowercased())_of"
                },
                objectExtractor: { _, _ in "user" },
                confidence: 0.9
            ))
        }

        // "X's birthday is Y"
        if let regex = try? NSRegularExpression(pattern: "([\\w]+)'?s? birthday is ([\\w\\s,]+?)(?:\\.|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .attribute,
                subjectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range])
                },
                predicateExtractor: { _, _ in "birthday" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 2), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.9
            ))
        }

        // "I want to X" (goal)
        if let regex = try? NSRegularExpression(pattern: "\\b[Ii] (?:want to|need to|plan to|hope to|am trying to) ([\\w\\s]+?)(?:\\.|,|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .goal,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { _, _ in "wants_to" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.8
            ))
        }

        // "My goal is to X"
        if let regex = try? NSRegularExpression(pattern: "\\b[Mm]y goal is (?:to )?([\\w\\s]+?)(?:\\.|,|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .goal,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { _, _ in "goal" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.9
            ))
        }

        // "I usually X" (habit)
        if let regex = try? NSRegularExpression(pattern: "\\b[Ii] (?:usually|always|often|typically|generally) ([\\w\\s]+?)(?:\\.|,|$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .habit,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { _, _ in "usually" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.75
            ))
        }

        // "I am X years old"
        if let regex = try? NSRegularExpression(pattern: "\\b[Ii] am (\\d+) years old", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .attribute,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { _, _ in "age" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range])
                },
                confidence: 0.95
            ))
        }

        // "My name is X"
        if let regex = try? NSRegularExpression(pattern: "\\b[Mm]y name is ([\\w\\s]+?)(?:\\.|,|and |$)", options: []) {
            factPatterns.append(FactPattern(
                regex: regex,
                predicateCategory: .attribute,
                subjectExtractor: { _, _ in "user" },
                predicateExtractor: { _, _ in "name" },
                objectExtractor: { text, match in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                confidence: 0.95
            ))
        }
    }

    // MARK: - Pattern Extraction

    private func extractWithPattern(
        _ pattern: FactPattern,
        from text: String,
        sourceMemoryId: UUID
    ) -> Fact? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.regex.firstMatch(in: text, range: range) else {
            return nil
        }

        guard let subject = pattern.subjectExtractor(text, match),
              let predicate = pattern.predicateExtractor(text, match),
              let object = pattern.objectExtractor(text, match) else {
            return nil
        }

        // Skip if object is too short or too long
        guard object.count >= 2 && object.count <= 100 else {
            return nil
        }

        return Fact(
            subject: subject,
            predicate: predicate,
            object: object,
            predicateCategory: pattern.predicateCategory,
            confidence: pattern.confidence,
            sourceMemoryId: sourceMemoryId,
            detectionMethod: .patternMatch
        )
    }

    // MARK: - Heuristic Extraction

    private func extractFactsHeuristic(from content: String, sourceMemoryId: UUID) -> [Fact] {
        var facts: [Fact] = []
        let lower = content.lowercased()

        // Topic detection
        let topicKeywords: [String: String] = [
            "work": "career",
            "job": "career",
            "career": "career",
            "family": "relationships",
            "relationship": "relationships",
            "health": "health",
            "fitness": "health",
            "exercise": "health",
            "money": "finance",
            "budget": "finance",
            "stress": "mental_health",
            "anxiety": "mental_health",
            "happy": "mental_health",
            "goal": "goals",
            "dream": "goals"
        ]

        for (keyword, topic) in topicKeywords {
            if lower.contains(keyword) {
                facts.append(Fact(
                    subject: "memory",
                    predicate: "about_topic",
                    object: topic,
                    predicateCategory: .belief,
                    confidence: 0.7,
                    sourceMemoryId: sourceMemoryId,
                    detectionMethod: .patternMatch
                ))
                break // One topic per memory for heuristic
            }
        }

        return facts
    }

    // MARK: - Entity Extraction

    private func extractPeople(from content: String, userId: String) -> [TrackedEntity] {
        var entities: [TrackedEntity] = []

        // Pattern for relationship mentions: "my mom Sarah", "my friend John"
        let relationshipPattern = try? NSRegularExpression(
            pattern: "\\b[Mm]y (mom|mother|dad|father|brother|sister|partner|wife|husband|boss|friend|colleague) ([A-Z][a-z]+)",
            options: []
        )

        if let regex = relationshipPattern {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)

            for match in matches {
                guard let nameRange = Range(match.range(at: 2), in: content) else { continue }
                let name = String(content[nameRange])

                if let relRange = Range(match.range(at: 1), in: content) {
                    let relationship = String(content[relRange])
                    entities.append(TrackedEntity(
                        name: name,
                        type: .person,
                        aliases: [relationship],
                        userId: userId
                    ))
                }
            }
        }

        // Capitalized words that might be names (simple heuristic)
        let words = content.components(separatedBy: .whitespacesAndNewlines)
        let excludedWords = Set(["I", "The", "A", "An", "My", "Your", "His", "Her", "Their", "Our",
                                  "This", "That", "These", "Those", "Today", "Yesterday", "Tomorrow",
                                  "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
                                  "January", "February", "March", "April", "May", "June", "July",
                                  "August", "September", "October", "November", "December"])

        for word in words {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            guard clean.count >= 2,
                  clean.first?.isUppercase == true,
                  clean.dropFirst().allSatisfy({ $0.isLowercase }),
                  !excludedWords.contains(clean) else {
                continue
            }

            // Check if not already added
            if !entities.contains(where: { $0.name == clean }) {
                entities.append(TrackedEntity(
                    name: clean,
                    type: .person,
                    userId: userId
                ))
            }
        }

        return entities
    }

    private func extractPlaces(from content: String, userId: String) -> [TrackedEntity] {
        var entities: [TrackedEntity] = []

        // Common cities
        let cities = ["New York", "NYC", "Los Angeles", "LA", "San Francisco", "SF",
                      "Chicago", "Boston", "Seattle", "Austin", "Denver", "Miami",
                      "London", "Paris", "Tokyo", "Berlin", "Sydney"]

        for city in cities {
            if content.range(of: city, options: .caseInsensitive) != nil {
                entities.append(TrackedEntity(
                    name: city,
                    type: .place,
                    userId: userId
                ))
            }
        }

        // Pattern: "in [Place]"
        let placePattern = try? NSRegularExpression(
            pattern: "\\bin ([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)?)",
            options: []
        )

        if let regex = placePattern {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)

            for match in matches {
                guard let placeRange = Range(match.range(at: 1), in: content) else { continue }
                let place = String(content[placeRange])

                if !entities.contains(where: { $0.normalizedName == place.lowercased() }) {
                    entities.append(TrackedEntity(
                        name: place,
                        type: .place,
                        userId: userId
                    ))
                }
            }
        }

        return entities
    }

    private func extractDates(from content: String, userId: String) -> [TrackedEntity] {
        var entities: [TrackedEntity] = []

        // Month day pattern: "June 15" or "June 15th"
        let monthDayPattern = try? NSRegularExpression(
            pattern: "(January|February|March|April|May|June|July|August|September|October|November|December)\\s+(\\d{1,2})(?:st|nd|rd|th)?",
            options: .caseInsensitive
        )

        if let regex = monthDayPattern {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)

            for match in matches {
                guard let fullRange = Range(match.range, in: content) else { continue }
                let dateStr = String(content[fullRange])

                entities.append(TrackedEntity(
                    name: dateStr,
                    type: .date,
                    userId: userId
                ))
            }
        }

        return entities
    }

    private func extractOrganizations(from content: String, userId: String) -> [TrackedEntity] {
        var entities: [TrackedEntity] = []

        // Common companies
        let companies = ["Google", "Apple", "Microsoft", "Amazon", "Meta", "Facebook",
                         "Netflix", "Tesla", "Stripe", "Airbnb", "Uber", "OpenAI", "Anthropic"]

        for company in companies {
            if content.range(of: company, options: .caseInsensitive) != nil {
                entities.append(TrackedEntity(
                    name: company,
                    type: .organization,
                    userId: userId
                ))
            }
        }

        // Pattern: "at [Company]" or "work at [Company]"
        let orgPattern = try? NSRegularExpression(
            pattern: "(?:at|for|with) ([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)?(?:\\s+Inc\\.?|\\s+Corp\\.?|\\s+LLC)?)",
            options: []
        )

        if let regex = orgPattern {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, range: range)

            for match in matches {
                guard let orgRange = Range(match.range(at: 1), in: content) else { continue }
                let org = String(content[orgRange])

                if !entities.contains(where: { $0.normalizedName == org.lowercased() }) {
                    entities.append(TrackedEntity(
                        name: org,
                        type: .organization,
                        userId: userId
                    ))
                }
            }
        }

        return entities
    }

    private func extractGoals(from content: String, userId: String) -> [TrackedEntity] {
        var entities: [TrackedEntity] = []

        // Goal keywords
        let goalPatterns = [
            "want to ([\\w\\s]+?)(?:\\.|,|$)",
            "goal is to ([\\w\\s]+?)(?:\\.|,|$)",
            "trying to ([\\w\\s]+?)(?:\\.|,|$)",
            "working on ([\\w\\s]+?)(?:\\.|,|$)"
        ]

        for pattern in goalPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(content.startIndex..., in: content)
            if let match = regex.firstMatch(in: content, range: range),
               let goalRange = Range(match.range(at: 1), in: content) {
                let goal = String(content[goalRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                if goal.count >= 3 && goal.count <= 100 {
                    entities.append(TrackedEntity(
                        name: goal,
                        type: .goal,
                        userId: userId
                    ))
                }
            }
        }

        return entities
    }

    // MARK: - Emotional Valence Extraction

    private func extractEmotionalValence(from content: String) -> EmotionalValence {
        let lower = content.lowercased()

        // Emotion keywords with intensity
        let emotionKeywords: [(keywords: [String], emotion: Emotion, intensity: Float)] = [
            // High intensity positive
            (["ecstatic", "thrilled", "overjoyed", "elated"], .excitement, 0.9),
            (["love", "adore", "amazing", "wonderful"], .love, 0.85),

            // Medium intensity positive
            (["happy", "glad", "pleased", "delighted"], .joy, 0.7),
            (["hopeful", "optimistic", "looking forward"], .hope, 0.7),
            (["proud", "accomplished", "achieved"], .pride, 0.7),
            (["grateful", "thankful", "appreciate"], .gratitude, 0.7),
            (["calm", "peaceful", "relaxed", "serene"], .calm, 0.6),
            (["confident", "sure", "certain"], .confident, 0.7),
            (["motivated", "driven", "energized", "pumped"], .motivated, 0.75),

            // High intensity negative
            (["devastated", "crushed", "heartbroken"], .sadness, 0.9),
            (["furious", "enraged", "livid"], .anger, 0.9),
            (["terrified", "petrified", "horrified"], .fear, 0.9),
            (["overwhelmed", "drowning", "suffocating"], .overwhelmed, 0.85),

            // Medium intensity negative
            (["sad", "unhappy", "down", "blue"], .sadness, 0.6),
            (["angry", "mad", "upset", "annoyed"], .anger, 0.6),
            (["anxious", "worried", "nervous", "stressed"], .anxiety, 0.7),
            (["frustrated", "stuck", "blocked"], .frustration, 0.65),
            (["guilty", "regret", "sorry"], .guilt, 0.6),
            (["ashamed", "embarrassed"], .shame, 0.65),
            (["disappointed", "let down"], .disappointment, 0.6),
        ]

        var detectedEmotions: [(Emotion, Float)] = []

        for (keywords, emotion, intensity) in emotionKeywords {
            for keyword in keywords {
                if lower.contains(keyword) {
                    detectedEmotions.append((emotion, intensity))
                    break
                }
            }
        }

        // Return neutral if no emotions detected
        guard !detectedEmotions.isEmpty else {
            return EmotionalValence()
        }

        // Sort by intensity and get primary
        detectedEmotions.sort { $0.1 > $1.1 }
        let primary = detectedEmotions[0]
        let secondary = detectedEmotions.dropFirst().map { $0.0 }

        // Calculate sentiment
        let positiveCount = detectedEmotions.filter { $0.0.isPositive }.count
        let negativeCount = detectedEmotions.count - positiveCount
        let sentiment = Float(positiveCount - negativeCount) / Float(max(detectedEmotions.count, 1))

        return EmotionalValence(
            primary: primary.0,
            intensity: primary.1,
            secondaryEmotions: Array(secondary.prefix(3)),
            sentiment: sentiment
        )
    }
}

// MARK: - LLM Extension Point

extension AdvancedEntityExtractor {
    /// Extension point for future LLM-enhanced extraction
    /// Currently returns nil, but can be implemented with local LLM
    public func extractWithLLM(
        from content: String,
        sourceMemoryId: UUID,
        userId: String,
        capabilities: LLMCapabilities
    ) async -> ExtractionResult? {
        // Future: When local LLMs become powerful enough
        // This will use the LLM for enhanced extraction

        guard capabilities.canExtractJSON else {
            return nil
        }

        // Placeholder for future LLM integration
        // let prompt = buildExtractionPrompt(content)
        // let response = await llmService.generate(prompt)
        // return parseExtractionResponse(response)

        return nil
    }
}
