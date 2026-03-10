//
//  TemporalQueryParser.swift
//  SwiftMem
//
//  v3: Parses temporal expressions from search queries into DateInterval filters.
//  Enables queries like "what did I do last week?" to filter memories by timestamp.
//

import Foundation

/// Result of parsing a search query for temporal expressions
public struct TemporalFilter {
    /// The date interval to filter memories by (nil = no temporal constraint)
    public let interval: DateInterval?
    /// Human-readable description for logging/debugging
    public let description: String
    /// Whether the query was detected as temporally grounded
    public let isTemporalQuery: Bool
    /// The query stripped of temporal language (better for embedding)
    public let cleanedQuery: String
}

/// Parses natural language temporal expressions from search queries
/// into DateInterval filters. Used by SwiftMemAPI.search() for temporal grounding.
public struct TemporalQueryParser {

    private let referenceDate: Date
    private let calendar: Calendar

    public init(referenceDate: Date = Date(), calendar: Calendar = .current) {
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    // MARK: - Public API

    public func parse(_ query: String) -> TemporalFilter {
        let lower = query.lowercased()
        for rule in rules {
            if let result = rule(lower, query) { return result }
        }
        return TemporalFilter(interval: nil, description: "no filter", isTemporalQuery: false, cleanedQuery: query)
    }

    // MARK: - Rules (most specific first)

    private var rules: [(String, String) -> TemporalFilter?] {[
        parseToday, parseYesterday,
        parseLastNDays, parseNDaysAgo,
        parseNWeeksAgo, parseNMonthsAgo,
        parseLastWeek, parseThisWeek,
        parseLastMonth, parseThisMonth,
        parseLastYear, parseRecently
    ]}

    private func parseToday(_ lower: String, _ original: String) -> TemporalFilter? {
        guard lower.contains("today") else { return nil }
        let start = calendar.startOfDay(for: referenceDate)
        return TemporalFilter(
            interval: DateInterval(start: start, end: referenceDate),
            description: "today",
            isTemporalQuery: true,
            cleanedQuery: strip("today", from: original)
        )
    }

    private func parseYesterday(_ lower: String, _ original: String) -> TemporalFilter? {
        guard lower.contains("yesterday") else { return nil }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate)!
        let start = calendar.startOfDay(for: yesterday)
        let end   = calendar.date(byAdding: .day, value: 1, to: start)!
        return TemporalFilter(
            interval: DateInterval(start: start, end: end),
            description: "yesterday",
            isTemporalQuery: true,
            cleanedQuery: strip("yesterday", from: original)
        )
    }

    private func parseLastNDays(_ lower: String, _ original: String) -> TemporalFilter? {
        guard let n = regexInt(lower, pattern: "(?:in the )?last (\\d+) days?") else { return nil }
        let start = calendar.date(byAdding: .day, value: -n, to: referenceDate)!
        return TemporalFilter(
            interval: DateInterval(start: start, end: referenceDate),
            description: "last \(n) days",
            isTemporalQuery: true,
            cleanedQuery: regexStrip(lower, pattern: "(?:in the )?last \\d+ days?", from: original)
        )
    }

    private func parseNDaysAgo(_ lower: String, _ original: String) -> TemporalFilter? {
        guard let n = regexInt(lower, pattern: "(\\d+) days? ago") else { return nil }
        let day = calendar.date(byAdding: .day, value: -n, to: referenceDate)!
        let start = calendar.startOfDay(for: day)
        let end   = calendar.date(byAdding: .day, value: 1, to: start)!
        return TemporalFilter(
            interval: DateInterval(start: start, end: end),
            description: "\(n) days ago",
            isTemporalQuery: true,
            cleanedQuery: regexStrip(lower, pattern: "\\d+ days? ago", from: original)
        )
    }

    private func parseNWeeksAgo(_ lower: String, _ original: String) -> TemporalFilter? {
        guard let n = regexInt(lower, pattern: "(\\d+) weeks? ago") else { return nil }
        let weekStart = calendar.date(byAdding: .weekOfYear, value: -n, to: referenceDate)!
        let start = calendar.dateInterval(of: .weekOfYear, for: weekStart)?.start ?? weekStart
        let end   = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
        return TemporalFilter(
            interval: DateInterval(start: start, end: end),
            description: "\(n) weeks ago",
            isTemporalQuery: true,
            cleanedQuery: regexStrip(lower, pattern: "\\d+ weeks? ago", from: original)
        )
    }

    private func parseNMonthsAgo(_ lower: String, _ original: String) -> TemporalFilter? {
        guard let n = regexInt(lower, pattern: "(\\d+) months? ago") else { return nil }
        let monthStart = calendar.date(byAdding: .month, value: -n, to: referenceDate)!
        let start = calendar.dateInterval(of: .month, for: monthStart)?.start ?? monthStart
        let end   = calendar.date(byAdding: .month, value: 1, to: start)!
        return TemporalFilter(
            interval: DateInterval(start: start, end: end),
            description: "\(n) months ago",
            isTemporalQuery: true,
            cleanedQuery: regexStrip(lower, pattern: "\\d+ months? ago", from: original)
        )
    }

    private func parseLastWeek(_ lower: String, _ original: String) -> TemporalFilter? {
        guard lower.contains("last week") else { return nil }
        let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: referenceDate)!
        let start = calendar.dateInterval(of: .weekOfYear, for: lastWeekDate)?.start ?? lastWeekDate
        let end   = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
        return TemporalFilter(
            interval: DateInterval(start: start, end: end),
            description: "last week",
            isTemporalQuery: true,
            cleanedQuery: strip("last week", from: original)
        )
    }

    private func parseThisWeek(_ lower: String, _ original: String) -> TemporalFilter? {
        guard lower.contains("this week") else { return nil }
        let start = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start ?? referenceDate
        return TemporalFilter(
            interval: DateInterval(start: start, end: referenceDate),
            description: "this week",
            isTemporalQuery: true,
            cleanedQuery: strip("this week", from: original)
        )
    }

    private func parseLastMonth(_ lower: String, _ original: String) -> TemporalFilter? {
        guard lower.contains("last month") else { return nil }
        let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: referenceDate)!
        let start = calendar.dateInterval(of: .month, for: lastMonthDate)?.start ?? lastMonthDate
        let end   = calendar.date(byAdding: .month, value: 1, to: start)!
        return TemporalFilter(
            interval: DateInterval(start: start, end: end),
            description: "last month",
            isTemporalQuery: true,
            cleanedQuery: strip("last month", from: original)
        )
    }

    private func parseThisMonth(_ lower: String, _ original: String) -> TemporalFilter? {
        guard lower.contains("this month") else { return nil }
        let start = calendar.dateInterval(of: .month, for: referenceDate)?.start ?? referenceDate
        return TemporalFilter(
            interval: DateInterval(start: start, end: referenceDate),
            description: "this month",
            isTemporalQuery: true,
            cleanedQuery: strip("this month", from: original)
        )
    }

    private func parseLastYear(_ lower: String, _ original: String) -> TemporalFilter? {
        guard lower.contains("last year") else { return nil }
        let lastYearDate = calendar.date(byAdding: .year, value: -1, to: referenceDate)!
        let start = calendar.dateInterval(of: .year, for: lastYearDate)?.start ?? lastYearDate
        let end   = calendar.date(byAdding: .year, value: 1, to: start)!
        return TemporalFilter(
            interval: DateInterval(start: start, end: end),
            description: "last year",
            isTemporalQuery: true,
            cleanedQuery: strip("last year", from: original)
        )
    }

    private func parseRecently(_ lower: String, _ original: String) -> TemporalFilter? {
        guard lower.contains("recently") || lower.contains("lately") else { return nil }
        let start = calendar.date(byAdding: .day, value: -7, to: referenceDate)!
        return TemporalFilter(
            interval: DateInterval(start: start, end: referenceDate),
            description: "recently (last 7 days)",
            isTemporalQuery: true,
            cleanedQuery: strip("recently", from: strip("lately", from: original))
        )
    }

    // MARK: - Helpers

    private func regexInt(_ text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let numRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[numRange])
    }

    private func regexStrip(_ lower: String, pattern: String, from original: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return original }
        let range = NSRange(original.startIndex..., in: original)
        let result = regex.stringByReplacingMatches(in: original, range: range, withTemplate: "")
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func strip(_ substring: String, from original: String) -> String {
        original.replacingOccurrences(of: substring, with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
    }
}
