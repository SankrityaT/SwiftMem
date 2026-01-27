//
//  TemporalExtractor.swift
//  SwiftMem
//
//  Regex-based temporal information extraction
//  Calculates actual dates from relative references
//

import Foundation

/// Extracts temporal information from memory content
public actor TemporalExtractor {

    // MARK: - Calendar

    private let calendar = Calendar.current

    // MARK: - Public API

    /// Extract temporal information from content
    public func extract(from content: String, referenceDate: Date = Date()) -> TemporalInfo {
        let lower = content.lowercased()

        // Find all temporal markers
        let markers = extractTemporalMarkers(from: lower)

        // Determine temporal type
        let temporalType = determineTemporalType(from: lower, markers: markers)

        // Try to extract specific date
        let (eventTime, granularity) = extractEventTime(from: content, markers: markers, referenceDate: referenceDate)

        // Determine if ongoing
        let isOngoing = determineIfOngoing(from: lower)

        return TemporalInfo(
            storageTime: referenceDate,
            eventTime: eventTime,
            eventTimeGranularity: granularity,
            isOngoing: isOngoing,
            temporalMarkers: markers,
            temporalType: temporalType
        )
    }

    // MARK: - Marker Extraction

    private func extractTemporalMarkers(from text: String) -> [String] {
        var markers: [String] = []

        // Relative time markers
        let relativePatterns = [
            "today", "yesterday", "tomorrow",
            "this morning", "this afternoon", "this evening", "tonight",
            "last night", "last week", "last month", "last year",
            "next week", "next month", "next year",
            "a few days ago", "a few weeks ago", "a few months ago",
            "recently", "just now", "earlier", "later",
            "in the morning", "in the afternoon", "in the evening",
            "this week", "this month", "this year"
        ]

        for pattern in relativePatterns {
            if text.contains(pattern) {
                markers.append(pattern)
            }
        }

        // Day of week
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for day in days {
            if text.contains(day) {
                markers.append(day)
            }
        }

        // Check for "last [day]" or "next [day]"
        for day in days {
            if text.contains("last \(day)") {
                markers.append("last \(day)")
            }
            if text.contains("next \(day)") {
                markers.append("next \(day)")
            }
        }

        return markers
    }

    // MARK: - Temporal Type

    private func determineTemporalType(from text: String, markers: [String]) -> TemporalType {
        // Future indicators
        let futureIndicators = ["will", "going to", "plan to", "tomorrow", "next", "want to", "hope to", "intend to"]
        for indicator in futureIndicators {
            if text.contains(indicator) {
                return .future
            }
        }

        // Past indicators
        let pastIndicators = ["yesterday", "last", "ago", "was", "were", "had", "did", "went", "used to"]
        for indicator in pastIndicators {
            if text.contains(indicator) {
                return .past
            }
        }

        // Habitual indicators
        let habitualIndicators = ["always", "usually", "often", "sometimes", "rarely", "never", "every day", "every week"]
        for indicator in habitualIndicators {
            if text.contains(indicator) {
                return .habitual
            }
        }

        // Default to present
        return .present
    }

    // MARK: - Event Time Extraction

    private func extractEventTime(
        from content: String,
        markers: [String],
        referenceDate: Date
    ) -> (Date?, TimeGranularity) {
        // Try to extract explicit date first
        if let (date, granularity) = extractExplicitDate(from: content) {
            return (date, granularity)
        }

        // Try relative time markers
        if let (date, granularity) = extractRelativeDate(from: markers, referenceDate: referenceDate) {
            return (date, granularity)
        }

        return (nil, .unknown)
    }

    private func extractExplicitDate(from content: String) -> (Date?, TimeGranularity)? {
        // Month Day, Year pattern (e.g., "June 15, 2025" or "June 15th, 2025")
        let fullDatePattern = try? NSRegularExpression(
            pattern: "(January|February|March|April|May|June|July|August|September|October|November|December)\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?",
            options: .caseInsensitive
        )

        if let regex = fullDatePattern {
            let range = NSRange(content.startIndex..., in: content)
            if let match = regex.firstMatch(in: content, range: range) {
                guard let monthRange = Range(match.range(at: 1), in: content),
                      let dayRange = Range(match.range(at: 2), in: content) else {
                    return nil
                }

                let monthStr = String(content[monthRange])
                let dayStr = String(content[dayRange])

                var yearStr: String? = nil
                if match.range(at: 3).location != NSNotFound,
                   let yearRange = Range(match.range(at: 3), in: content) {
                    yearStr = String(content[yearRange])
                }

                if let date = parseDate(month: monthStr, day: dayStr, year: yearStr) {
                    let granularity: TimeGranularity = yearStr != nil ? .day : .day
                    return (date, granularity)
                }
            }
        }

        // Numeric date pattern (e.g., "12/25/2025" or "12/25")
        let numericPattern = try? NSRegularExpression(
            pattern: "(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?",
            options: []
        )

        if let regex = numericPattern {
            let range = NSRange(content.startIndex..., in: content)
            if let match = regex.firstMatch(in: content, range: range) {
                guard let monthRange = Range(match.range(at: 1), in: content),
                      let dayRange = Range(match.range(at: 2), in: content) else {
                    return nil
                }

                let monthStr = String(content[monthRange])
                let dayStr = String(content[dayRange])

                var yearStr: String? = nil
                if match.range(at: 3).location != NSNotFound,
                   let yearRange = Range(match.range(at: 3), in: content) {
                    yearStr = String(content[yearRange])
                }

                if let month = Int(monthStr), let day = Int(dayStr) {
                    var components = DateComponents()
                    components.month = month
                    components.day = day

                    if let yearStr = yearStr, let year = Int(yearStr) {
                        components.year = year < 100 ? 2000 + year : year
                    } else {
                        components.year = calendar.component(.year, from: Date())
                    }

                    if let date = calendar.date(from: components) {
                        return (date, .day)
                    }
                }
            }
        }

        return nil
    }

    private func extractRelativeDate(
        from markers: [String],
        referenceDate: Date
    ) -> (Date?, TimeGranularity)? {
        for marker in markers {
            if let (date, granularity) = resolveRelativeMarker(marker, referenceDate: referenceDate) {
                return (date, granularity)
            }
        }
        return nil
    }

    private func resolveRelativeMarker(_ marker: String, referenceDate: Date) -> (Date?, TimeGranularity)? {
        switch marker {
        case "today":
            return (calendar.startOfDay(for: referenceDate), .day)

        case "yesterday":
            if let date = calendar.date(byAdding: .day, value: -1, to: referenceDate) {
                return (calendar.startOfDay(for: date), .day)
            }

        case "tomorrow":
            if let date = calendar.date(byAdding: .day, value: 1, to: referenceDate) {
                return (calendar.startOfDay(for: date), .day)
            }

        case "last night":
            if let date = calendar.date(byAdding: .day, value: -1, to: referenceDate) {
                return (calendar.startOfDay(for: date), .day)
            }

        case "last week":
            if let date = calendar.date(byAdding: .weekOfYear, value: -1, to: referenceDate) {
                return (date, .week)
            }

        case "last month":
            if let date = calendar.date(byAdding: .month, value: -1, to: referenceDate) {
                return (date, .month)
            }

        case "last year":
            if let date = calendar.date(byAdding: .year, value: -1, to: referenceDate) {
                return (date, .year)
            }

        case "next week":
            if let date = calendar.date(byAdding: .weekOfYear, value: 1, to: referenceDate) {
                return (date, .week)
            }

        case "next month":
            if let date = calendar.date(byAdding: .month, value: 1, to: referenceDate) {
                return (date, .month)
            }

        case "next year":
            if let date = calendar.date(byAdding: .year, value: 1, to: referenceDate) {
                return (date, .year)
            }

        case "this week":
            return (referenceDate, .week)

        case "this month":
            return (referenceDate, .month)

        case "this year":
            return (referenceDate, .year)

        case "a few days ago":
            if let date = calendar.date(byAdding: .day, value: -3, to: referenceDate) {
                return (date, .approximate)
            }

        case "a few weeks ago":
            if let date = calendar.date(byAdding: .weekOfYear, value: -2, to: referenceDate) {
                return (date, .approximate)
            }

        case "a few months ago":
            if let date = calendar.date(byAdding: .month, value: -2, to: referenceDate) {
                return (date, .approximate)
            }

        case "recently":
            if let date = calendar.date(byAdding: .day, value: -2, to: referenceDate) {
                return (date, .approximate)
            }

        default:
            // Check for day of week
            if let dayOfWeek = parseDayOfWeek(marker) {
                // "last [day]"
                if marker.hasPrefix("last ") {
                    if let date = previousOccurrence(of: dayOfWeek, from: referenceDate) {
                        return (date, .day)
                    }
                }
                // "next [day]"
                else if marker.hasPrefix("next ") {
                    if let date = nextOccurrence(of: dayOfWeek, from: referenceDate) {
                        return (date, .day)
                    }
                }
                // Just day name - assume last occurrence
                else {
                    if let date = previousOccurrence(of: dayOfWeek, from: referenceDate) {
                        return (date, .day)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Ongoing Detection

    private func determineIfOngoing(from text: String) -> Bool {
        // Ongoing state indicators
        let ongoingIndicators = [
            "i am", "i'm", "i have been", "i've been",
            "currently", "at the moment", "these days",
            "for a while", "for some time"
        ]

        for indicator in ongoingIndicators {
            if text.contains(indicator) {
                return true
            }
        }

        // Not ongoing indicators (point in time)
        let pointIndicators = [
            "yesterday", "last night", "this morning",
            "went", "did", "was", "happened"
        ]

        for indicator in pointIndicators {
            if text.contains(indicator) {
                return false
            }
        }

        // Default to ongoing for present tense
        return text.contains("i am") || text.contains("i'm")
    }

    // MARK: - Helper Methods

    private func parseDate(month: String, day: String, year: String?) -> Date? {
        let monthMap: [String: Int] = [
            "january": 1, "february": 2, "march": 3, "april": 4,
            "may": 5, "june": 6, "july": 7, "august": 8,
            "september": 9, "october": 10, "november": 11, "december": 12
        ]

        guard let monthNum = monthMap[month.lowercased()],
              let dayNum = Int(day) else {
            return nil
        }

        var components = DateComponents()
        components.month = monthNum
        components.day = dayNum

        if let yearStr = year, let yearNum = Int(yearStr) {
            components.year = yearNum
        } else {
            // Assume current year
            components.year = calendar.component(.year, from: Date())
        }

        return calendar.date(from: components)
    }

    private func parseDayOfWeek(_ text: String) -> Int? {
        let dayMap: [String: Int] = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7
        ]

        let lower = text.lowercased()
        for (day, value) in dayMap {
            if lower.contains(day) {
                return value
            }
        }
        return nil
    }

    private func previousOccurrence(of weekday: Int, from date: Date) -> Date? {
        var components = DateComponents()
        components.weekday = weekday

        // Go back up to 7 days to find the previous occurrence
        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .previousTimePreservingSmallerComponents,
            direction: .backward
        )
    }

    private func nextOccurrence(of weekday: Int, from date: Date) -> Date? {
        var components = DateComponents()
        components.weekday = weekday

        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime
        )
    }
}

// MARK: - Date Utilities

extension TemporalExtractor {
    /// Calculate recency score for a date (0-1, higher = more recent)
    public func recencyScore(for date: Date, referenceDate: Date = Date()) -> Float {
        let daysSince = referenceDate.timeIntervalSince(date) / 86400

        if daysSince < 0 {
            // Future date
            return 0.5
        } else if daysSince < 1 {
            // Today
            return 1.0
        } else if daysSince < 7 {
            // This week
            return 0.9 - Float(daysSince) * 0.05
        } else if daysSince < 30 {
            // This month
            return 0.6 - Float(daysSince - 7) * 0.01
        } else if daysSince < 365 {
            // This year
            return 0.35 - Float(daysSince - 30) * 0.001
        } else {
            // Older
            return max(0.1, 0.25 - Float(daysSince - 365) * 0.0001)
        }
    }

    /// Check if two dates are in the same time period
    public func areInSamePeriod(_ a: Date, _ b: Date, granularity: TimeGranularity) -> Bool {
        switch granularity {
        case .exact:
            return abs(a.timeIntervalSince(b)) < 60 // Within 1 minute
        case .day:
            return calendar.isDate(a, inSameDayAs: b)
        case .week:
            return calendar.isDate(a, equalTo: b, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(a, equalTo: b, toGranularity: .month)
        case .year:
            return calendar.isDate(a, equalTo: b, toGranularity: .year)
        case .approximate, .unknown:
            // Within 2 weeks
            return abs(a.timeIntervalSince(b)) < 14 * 86400
        }
    }

    /// Format a date relative to reference date
    public func formatRelative(_ date: Date, to reference: Date = Date()) -> String {
        let daysDiff = calendar.dateComponents([.day], from: date, to: reference).day ?? 0

        if daysDiff == 0 {
            return "today"
        } else if daysDiff == 1 {
            return "yesterday"
        } else if daysDiff == -1 {
            return "tomorrow"
        } else if daysDiff > 0 && daysDiff < 7 {
            return "\(daysDiff) days ago"
        } else if daysDiff < 0 && daysDiff > -7 {
            return "in \(-daysDiff) days"
        } else if daysDiff >= 7 && daysDiff < 30 {
            let weeks = daysDiff / 7
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        } else if daysDiff >= 30 && daysDiff < 365 {
            let months = daysDiff / 30
            return "\(months) month\(months == 1 ? "" : "s") ago"
        } else if daysDiff >= 365 {
            let years = daysDiff / 365
            return "\(years) year\(years == 1 ? "" : "s") ago"
        } else {
            // Future
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}
