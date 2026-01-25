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
        // Use LocalEmbedder (Apple NLEmbedding) for semantic embeddings
        let embedder = LocalEmbedder()  // 100% local semantic embeddings
        
        var config = SwiftMemConfig.default
        config.embeddingDimensions = embedder.dimensions  // Match NLEmbedding's 512 dims
        config.similarityThreshold = 0.3  // Lower threshold for semantic embeddings
        config.defaultRetrievalStrategy = .hybrid  // Use hybrid search
        
        let graphStore = try await GraphStore.create(config: config)
        let vectorStore = VectorStore(config: config)
        let embeddingEngine = EmbeddingEngine(embedder: embedder, config: config)
        
        print("Using LocalEmbedder (Apple NLEmbedding) - 100% local, semantic embeddings")
        print("Dimensions: \(embedder.dimensions)")
        print("Similarity threshold: \(config.similarityThreshold)")
        let datasetURL = URL(fileURLWithPath: "/Users/sankritya/Downloads/longmemeval_oracle.json")
        print("Dataset: \(datasetURL.path)")
        _ = try await LongMemEvalRunner.run(
            datasetURL: datasetURL,
            graphStore: graphStore,
            vectorStore: vectorStore,
            embeddingEngine: embeddingEngine,
            config: config,
            topK: 5,
            maxQuestions: nil  // Evaluate all questions
        )
        print("SwiftMemLongMemEval: completed run.")
    } catch {
        print("LongMemEval run failed: \(error)")
    }
    semaphore.signal()
}

semaphore.wait()
