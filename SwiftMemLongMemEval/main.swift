//
//  main.swift
//  SwiftMemLongMemEval
//
//  Created by Sankritya Thakur on 12/8/25.
//

import Foundation
import Dispatch

let semaphore = DispatchSemaphore(value: 0)

print("SwiftMemLongMemEval: starting run...")

Task {
    do {
        var config = SwiftMemConfig.default
        // For this benchmark, use a deterministic mock embedder instead of Groq.
        let graphStore = try await GraphStore.create(config: config)
        let vectorStore = VectorStore(config: config)
        let embedder = MockEmbedder(dimensions: config.embeddingDimensions)
        let embeddingEngine = EmbeddingEngine(embedder: embedder, config: config)
        let datasetURL = URL(fileURLWithPath: "/Users/sankritya/Downloads/longmemeval_oracle.json")
        print("Dataset: \(datasetURL.path)")
        _ = try await LongMemEvalRunner.run(
            datasetURL: datasetURL,
            graphStore: graphStore,
            vectorStore: vectorStore,
            embeddingEngine: embeddingEngine,
            config: config,
            topK: 5,
            maxQuestions: 50
        )
        print("SwiftMemLongMemEval: completed run.")
    } catch {
        print("LongMemEval run failed: \(error)")
    }
    semaphore.signal()
}

semaphore.wait()
