//
//  LongMemEvalRunner.swift
//  SwiftMem
//
//  Created by Sankritya on 12/8/25.
//  Lightweight harness to run LongMemEval-style retrieval benchmarks against SwiftMem.
//

import Foundation

/// Schema for a single turn in a LongMemEval session
public struct LongMemEvalTurn: Codable {
    public let role: String
    public let content: String
    public let hasAnswer: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case hasAnswer = "has_answer"
    }
}

/// Answer field in LongMemEval can be string or number; decode both safely.
public enum LongMemEvalAnswer: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else {
            throw DecodingError.typeMismatch(
                LongMemEvalAnswer.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected String or number for LongMemEval answer"
                )
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):
            try container.encode(s)
        case .int(let i):
            try container.encode(i)
        case .double(let d):
            try container.encode(d)
        }
    }
}

/// Schema for a single LongMemEval instance (one question + its history)
public struct LongMemEvalInstance: Codable {
    public let questionId: String
    public let questionType: String
    public let question: String
    public let answer: LongMemEvalAnswer
    public let questionDate: String
    public let haystackSessionIds: [String]
    public let haystackDates: [String]
    public let haystackSessions: [[LongMemEvalTurn]]
    public let answerSessionIds: [String]
    
    private enum CodingKeys: String, CodingKey {
        case questionId = "question_id"
        case questionType = "question_type"
        case question
        case answer
        case questionDate = "question_date"
        case haystackSessionIds = "haystack_session_ids"
        case haystackDates = "haystack_dates"
        case haystackSessions = "haystack_sessions"
        case answerSessionIds = "answer_session_ids"
    }
}

/// Basic retrieval metrics for LongMemEval-style evaluation
public struct LongMemEvalMetrics {
    /// Number of evaluated (non-abstention) questions
    public let totalQuestions: Int
    /// Fraction of questions where the top-1 retrieved session was correct
    public let hitAt1: Double
    /// Fraction of questions where any of the top-k retrieved sessions was correct
    public let hitAtK: Double
    /// Macro-averaged precision over all questions
    public let meanPrecision: Double
    /// Macro-averaged recall over all questions
    public let meanRecall: Double
}

public enum LongMemEvalRunnerError: Error {
    case emptyDataset
}

/// Runner that evaluates SwiftMem's retrieval on a LongMemEval JSON dataset.
///
/// This is intentionally minimal and library-only. You can call it from a CLI target or tests.
public struct LongMemEvalRunner {
    /// Run session-level retrieval evaluation using an existing SwiftMem stack.
    /// - Parameters:
    ///   - datasetURL: URL of `longmemeval_*.json` file.
    ///   - graphStore: Shared GraphStore instance (will be cleared between questions).
    ///   - vectorStore: Shared VectorStore instance (will be cleared between questions).
    ///   - embeddingEngine: EmbeddingEngine used for all embeddings.
    ///   - config: SwiftMemConfig used for retrieval settings.
    ///   - topK: Number of sessions to retrieve per question (e.g. 5).
    ///   - maxQuestions: Optional cap for debugging (evaluate on first N questions).
    /// - Returns: Aggregated retrieval metrics.
    @discardableResult
    public static func run(
        datasetURL: URL,
        graphStore: GraphStore,
        vectorStore: VectorStore,
        embeddingEngine: EmbeddingEngine,
        config: SwiftMemConfig,
        topK: Int = 5,
        maxQuestions: Int? = nil
    ) async throws -> LongMemEvalMetrics {
        let data = try Data(contentsOf: datasetURL)
        let decoder = JSONDecoder()
        
        let instances = try decoder.decode([LongMemEvalInstance].self, from: data)
        if instances.isEmpty {
            throw LongMemEvalRunnerError.emptyDataset
        }
        
        var totalEvaluated = 0
        var hit1Count = 0
        var hitKCount = 0
        var precisionSum: Double = 0
        var recallSum: Double = 0
        
        let retrievalEngine = RetrievalEngine(
            graphStore: graphStore,
            vectorStore: vectorStore,
            embeddingEngine: embeddingEngine,
            config: config
        )
        
        for instance in instances {
            if let maxQ = maxQuestions, totalEvaluated >= maxQ {
                break
            }
            
            // Skip abstention questions (no ground-truth evidence location)
            if instance.questionId.hasSuffix("_abs") || instance.answerSessionIds.isEmpty {
                continue
            }
            
            // Reset stores between questions
            try await graphStore.clearAll()
            await vectorStore.clearAll()
            
            // Ingest all haystack sessions for this instance
            try await ingest(instance: instance, graphStore: graphStore, vectorStore: vectorStore, embeddingEngine: embeddingEngine)
            
            // Run retrieval for the question
            let predictedSessionIds = try await retrieveSessions(
                question: instance.question,
                topK: topK,
                retrievalEngine: retrievalEngine
            )
            
            // Compute per-question metrics
            let gold = Set(instance.answerSessionIds)
            let predicted = Array(predictedSessionIds.prefix(topK))
            let predictedSet = Set(predicted)
            let intersectionCount = gold.intersection(predictedSet).count
            
            if let first = predicted.first, gold.contains(first) {
                hit1Count += 1
            }
            if intersectionCount > 0 {
                hitKCount += 1
            }
            
            let precision: Double
            let recall: Double
            if predictedSet.isEmpty {
                precision = 0
            } else {
                precision = Double(intersectionCount) / Double(predictedSet.count)
            }
            if gold.isEmpty {
                recall = 0
            } else {
                recall = Double(intersectionCount) / Double(gold.count)
            }
            
            precisionSum += precision
            recallSum += recall
            totalEvaluated += 1
        }
        
        guard totalEvaluated > 0 else {
            throw LongMemEvalRunnerError.emptyDataset
        }
        
        let total = Double(totalEvaluated)
        let metrics = LongMemEvalMetrics(
            totalQuestions: totalEvaluated,
            hitAt1: Double(hit1Count) / total,
            hitAtK: Double(hitKCount) / total,
            meanPrecision: precisionSum / total,
            meanRecall: recallSum / total
        )
        
        // Print a simple summary for now
        print("LongMemEval (session-level) on \(datasetURL.lastPathComponent):")
        print("  Questions evaluated: \(metrics.totalQuestions)")
        print(String(format: "  Hit@1: %.3f", metrics.hitAt1))
        print(String(format: "  Hit@%d: %.3f", topK, metrics.hitAtK))
        print(String(format: "  Mean precision: %.3f", metrics.meanPrecision))
        print(String(format: "  Mean recall: %.3f", metrics.meanRecall))
        
        return metrics
    }
    
    // MARK: - Ingestion
    
    private static func ingest(
        instance: LongMemEvalInstance,
        graphStore: GraphStore,
        vectorStore: VectorStore,
        embeddingEngine: EmbeddingEngine
    ) async throws {
        // Sanity check: align sessions and ids
        let sessionCount = min(
            instance.haystackSessionIds.count,
            instance.haystackSessions.count
        )
        guard sessionCount > 0 else { return }
        
        for index in 0..<sessionCount {
            let sessionId = instance.haystackSessionIds[index]
            let turns = instance.haystackSessions[index]
            
            // Concatenate turns into a single content string
            var lines: [String] = []
            lines.reserveCapacity(turns.count)
            
            var hasAnswer = false
            for turn in turns {
                let rolePrefix: String
                switch turn.role.lowercased() {
                case "user":
                    rolePrefix = "user:"
                case "assistant":
                    rolePrefix = "assistant:"
                default:
                    rolePrefix = "other:"
                }
                lines.append("\(rolePrefix) \(turn.content)")
                if turn.hasAnswer == true {
                    hasAnswer = true
                }
            }
            let content = lines.joined(separator: "\n")
            
            // Build metadata
            var metadata: [String: MetadataValue] = [:]
            metadata["lme_question_id"] = .string(instance.questionId)
            metadata["lme_session_id"] = .string(sessionId)
            metadata["lme_question_type"] = .string(instance.questionType)
            metadata["has_answer"] = .bool(hasAnswer)
            
            let node = Node(
                content: content,
                type: .episodic,
                metadata: metadata
            )
            
            try await graphStore.storeNode(node)
            let embedding = try await embeddingEngine.embed(node.content)
            try await vectorStore.addVector(embedding, for: node.id)
        }
    }
    
    // MARK: - Retrieval
    
    private static func retrieveSessions(
        question: String,
        topK: Int,
        retrievalEngine: RetrievalEngine
    ) async throws -> [String] {
        let result = try await retrievalEngine.query(
            question,
            maxResults: topK,
            strategy: .hybrid,
            filters: nil
        )
        
        // Map retrieved nodes back to LongMemEval session IDs
        let sessionIds: [String] = result.nodes.compactMap { scored in
            scored.node.metadata["lme_session_id"]?.stringValue
        }
        
        return sessionIds
    }
}
