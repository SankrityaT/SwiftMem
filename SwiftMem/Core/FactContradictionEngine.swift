//
//  FactContradictionEngine.swift
//  SwiftMem
//
//  Rule-based contradiction detection using fact triples
//  No LLM required - deterministic and reliable
//

import Foundation

/// Engine for detecting contradictions between facts
/// Uses predicate categories and synonym matching for reliable detection
public actor FactContradictionEngine {

    // MARK: - Predicate Synonyms

    /// Groups of predicates that mean the same thing
    private let predicateSynonymGroups: [[String]] = [
        // Location predicates
        ["lives_in", "located_in", "resides_in", "stays_in", "home_is", "based_in", "living_in"],

        // Employment predicates
        ["works_at", "employed_by", "job_at", "employed_at", "working_at"],

        // Job title predicates
        ["job_title", "role", "position", "title", "works_as", "profession"],

        // Preference predicates (positive)
        ["likes", "enjoys", "loves", "prefers", "favorite"],

        // Preference predicates (negative)
        ["dislikes", "hates", "avoids", "cant_stand"],

        // Date predicates
        ["birthday", "born_on", "birth_date", "date_of_birth"],

        // Age predicates
        ["age", "years_old", "is_age"],

        // Name predicates
        ["name", "called", "named", "goes_by"],

        // Relationship predicates
        ["partner", "spouse", "married_to", "dating", "relationship_with"],

        // Parent predicates
        ["mother", "mom", "parent_mother"],
        ["father", "dad", "parent_father"],
    ]

    /// Cache of predicate to synonym group index
    private var predicateSynonymCache: [String: Int] = [:]

    // MARK: - Initialization

    public init() {
        buildSynonymCache()
    }

    private func buildSynonymCache() {
        for (index, group) in predicateSynonymGroups.enumerated() {
            for predicate in group {
                predicateSynonymCache[predicate] = index
            }
        }
    }

    // MARK: - Public API

    /// Check if a new fact contradicts any existing facts
    /// - Parameters:
    ///   - newFact: The new fact to check
    ///   - existingFacts: All existing facts to check against
    /// - Returns: ContradictionResult with details if contradiction found
    public func checkContradiction(
        newFact: Fact,
        existingFacts: [Fact]
    ) -> ContradictionResult {
        for existing in existingFacts {
            // Skip if different subjects
            guard factsShareSubject(newFact, existing) else {
                continue
            }

            // Check if predicates are related
            guard predicatesAreRelated(newFact.predicate, existing.predicate) else {
                continue
            }

            // Check if this category allows contradictions
            guard newFact.predicateCategory.isMutuallyExclusive else {
                continue
            }

            // Same/similar predicate but different object = potential contradiction
            if !objectsAreEquivalent(newFact.object, existing.object) {
                // Determine resolution based on temporal info
                let resolution = determineResolution(new: newFact, existing: existing)

                return ContradictionResult(
                    type: areSynonymPredicates(newFact.predicate, existing.predicate)
                        ? .impliedContradiction
                        : .directContradiction,
                    existingFact: existing,
                    newFact: newFact,
                    resolution: resolution,
                    confidence: calculateContradictionConfidence(new: newFact, existing: existing)
                )
            }
        }

        return .noContradiction
    }

    /// Batch check multiple new facts against existing facts
    public func checkContradictions(
        newFacts: [Fact],
        existingFacts: [Fact]
    ) -> [ContradictionResult] {
        var results: [ContradictionResult] = []

        for newFact in newFacts {
            let result = checkContradiction(newFact: newFact, existingFacts: existingFacts)
            if result.type != .noContradiction {
                results.append(result)
            }
        }

        return results
    }

    /// Find all facts that might be related to a new fact (for pre-filtering)
    public func findRelatedFacts(
        for newFact: Fact,
        in existingFacts: [Fact]
    ) -> [Fact] {
        return existingFacts.filter { existing in
            factsShareSubject(newFact, existing) &&
            (predicatesAreRelated(newFact.predicate, existing.predicate) ||
             newFact.predicateCategory == existing.predicateCategory)
        }
    }

    // MARK: - Subject Matching

    /// Check if two facts share the same subject
    private func factsShareSubject(_ a: Fact, _ b: Fact) -> Bool {
        let subjectA = normalizeSubject(a.subject)
        let subjectB = normalizeSubject(b.subject)
        return subjectA == subjectB
    }

    /// Normalize subject for comparison
    private func normalizeSubject(_ subject: String) -> String {
        var normalized = subject.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Normalize common subject variations
        let userVariations = ["user", "i", "me", "myself", "the user"]
        if userVariations.contains(normalized) {
            normalized = "user"
        }

        return normalized
    }

    // MARK: - Predicate Matching

    /// Check if two predicates are related (same or synonyms)
    private func predicatesAreRelated(_ a: String, _ b: String) -> Bool {
        let normalizedA = a.lowercased()
        let normalizedB = b.lowercased()

        // Exact match
        if normalizedA == normalizedB {
            return true
        }

        // Synonym match
        return areSynonymPredicates(normalizedA, normalizedB)
    }

    /// Check if two predicates are synonyms
    private func areSynonymPredicates(_ a: String, _ b: String) -> Bool {
        guard let groupA = predicateSynonymCache[a],
              let groupB = predicateSynonymCache[b] else {
            return false
        }
        return groupA == groupB
    }

    // MARK: - Object Matching

    /// Check if two objects are equivalent (same meaning)
    private func objectsAreEquivalent(_ a: String, _ b: String) -> Bool {
        let normalizedA = normalizeObject(a)
        let normalizedB = normalizeObject(b)

        // Exact match
        if normalizedA == normalizedB {
            return true
        }

        // Check common equivalences
        return areEquivalentObjects(normalizedA, normalizedB)
    }

    /// Normalize object for comparison
    private func normalizeObject(_ object: String) -> String {
        var normalized = object.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common articles
        let articles = ["the ", "a ", "an "]
        for article in articles {
            if normalized.hasPrefix(article) {
                normalized = String(normalized.dropFirst(article.count))
            }
        }

        return normalized
    }

    /// Check if two normalized objects are equivalent
    private func areEquivalentObjects(_ a: String, _ b: String) -> Bool {
        // City abbreviations
        let cityEquivalents: [[String]] = [
            ["new york", "nyc", "new york city", "ny"],
            ["los angeles", "la", "l.a."],
            ["san francisco", "sf", "san fran"],
            ["washington dc", "dc", "washington d.c."],
        ]

        for equivalents in cityEquivalents {
            if equivalents.contains(a) && equivalents.contains(b) {
                return true
            }
        }

        // Check if one contains the other (e.g., "Google" vs "Google Inc")
        if a.contains(b) || b.contains(a) {
            // Only if significant overlap
            let shorter = min(a.count, b.count)
            let longer = max(a.count, b.count)
            if Double(shorter) / Double(longer) > 0.7 {
                return true
            }
        }

        return false
    }

    // MARK: - Resolution

    /// Determine how to resolve a contradiction
    private func determineResolution(new: Fact, existing: Fact) -> ContradictionResolution {
        // If new fact has valid_from and it's after existing, new supersedes
        if let newValidFrom = new.validFrom,
           let existingValidFrom = existing.validFrom {
            if newValidFrom > existingValidFrom {
                return .newSupersedes
            } else if existingValidFrom > newValidFrom {
                return .keepExisting
            }
        }

        // If new fact has valid_from but existing doesn't, new is more specific
        if new.validFrom != nil && existing.validFrom == nil {
            return .newSupersedes
        }

        // If existing has higher confidence, keep it
        if existing.confidence > new.confidence + 0.2 {
            return .keepExisting
        }

        // Default: newer information supersedes
        return .newSupersedes
    }

    /// Calculate confidence in the contradiction detection
    private func calculateContradictionConfidence(new: Fact, existing: Fact) -> Float {
        var confidence: Float = 0.5

        // Boost if predicates are exact match
        if new.predicate.lowercased() == existing.predicate.lowercased() {
            confidence += 0.2
        }

        // Boost if category is strongly exclusive
        if new.predicateCategory == .location || new.predicateCategory == .attribute {
            confidence += 0.15
        }

        // Boost based on extraction confidence
        confidence += (new.confidence + existing.confidence) / 10.0

        return min(confidence, 1.0)
    }
}

// MARK: - Convenience Extensions

extension FactContradictionEngine {
    /// Check contradictions and return only those that should supersede
    public func findSupersedingContradictions(
        newFacts: [Fact],
        existingFacts: [Fact]
    ) -> [(new: Fact, old: Fact)] {
        let results = checkContradictions(newFacts: newFacts, existingFacts: existingFacts)

        return results
            .filter { $0.resolution == .newSupersedes }
            .compactMap { result in
                guard let newFact = result.newFact,
                      let existingFact = result.existingFact else {
                    return nil
                }
                return (newFact, existingFact)
            }
    }

    /// Get a human-readable description of a contradiction
    public func describeContradiction(_ result: ContradictionResult) -> String {
        guard let newFact = result.newFact,
              let existingFact = result.existingFact else {
            return "No contradiction"
        }

        let typeDesc = switch result.type {
        case .directContradiction: "directly contradicts"
        case .impliedContradiction: "implies different value for"
        case .temporalContradiction: "temporally conflicts with"
        case .noContradiction: "does not contradict"
        }

        let resolutionDesc = switch result.resolution {
        case .newSupersedes: "New fact will supersede old"
        case .keepExisting: "Existing fact will be kept"
        case .needsUserInput: "User input needed"
        case .coexist: "Both facts can coexist"
        case .none: ""
        }

        return """
        "\(newFact.subject) \(newFact.predicate) \(newFact.object)" \(typeDesc)
        "\(existingFact.subject) \(existingFact.predicate) \(existingFact.object)"
        Resolution: \(resolutionDesc)
        """
    }
}

// MARK: - Fact Index for Fast Lookup

/// Index structure for fast fact lookups by subject and predicate
public actor FactIndex {
    /// Facts indexed by subject
    private var bySubject: [String: [Fact]] = [:]

    /// Facts indexed by subject:predicate key
    private var byLookupKey: [String: [Fact]] = [:]

    /// All facts
    private var allFacts: [UUID: Fact] = [:]

    // MARK: - Public API

    /// Add a fact to the index
    public func addFact(_ fact: Fact) {
        allFacts[fact.id] = fact

        let normalizedSubject = fact.subject.lowercased()
        bySubject[normalizedSubject, default: []].append(fact)

        byLookupKey[fact.lookupKey, default: []].append(fact)
    }

    /// Remove a fact from the index
    public func removeFact(_ factId: UUID) {
        guard let fact = allFacts[factId] else { return }

        allFacts.removeValue(forKey: factId)

        let normalizedSubject = fact.subject.lowercased()
        bySubject[normalizedSubject]?.removeAll { $0.id == factId }

        byLookupKey[fact.lookupKey]?.removeAll { $0.id == factId }
    }

    /// Get all facts for a subject
    public func getFacts(forSubject subject: String) -> [Fact] {
        let normalized = subject.lowercased()
        return bySubject[normalized] ?? []
    }

    /// Get facts matching a lookup key (subject:predicate)
    public func getFacts(forLookupKey key: String) -> [Fact] {
        return byLookupKey[key] ?? []
    }

    /// Get all facts
    public func getAllFacts() -> [Fact] {
        Array(allFacts.values)
    }

    /// Get fact by ID
    public func getFact(_ id: UUID) -> Fact? {
        allFacts[id]
    }

    /// Clear all facts
    public func clear() {
        allFacts.removeAll()
        bySubject.removeAll()
        byLookupKey.removeAll()
    }

    /// Get count of facts
    public func count() -> Int {
        allFacts.count
    }

    /// Bulk add facts
    public func addFacts(_ facts: [Fact]) {
        for fact in facts {
            addFact(fact)
        }
    }
}
