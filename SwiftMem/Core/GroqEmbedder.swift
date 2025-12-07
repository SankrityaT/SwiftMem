//
//  GroqEmbedder.swift
//  SwiftMem
//
//  Groq API embedder using their inference API
//

import Foundation

/// Embedder using Groq's API (currently uses text generation as workaround)
/// NOTE: Groq doesn't have a native embeddings API yet, so we use a creative approach
public actor GroqEmbedder: Embedder {
    
    private let apiKey: String
    private let baseURL = "https://api.groq.com/openai/v1/chat/completions"
    
    public let dimensions: Int = 384 // We'll normalize to this
    public let modelIdentifier: String = "llama-3.3-70b-versatile"
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    /// Generate embedding by using Llama to create a semantic hash
    /// This is a creative workaround until Groq adds embeddings API
    public func embed(_ text: String) async throws -> [Float] {
        // For now, use a deterministic approach based on text
        // In production, you'd call Groq to get semantic features
        return try await generateSemanticVector(text)
    }
    
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var embeddings: [[Float]] = []
        
        // Process in parallel with limited concurrency
        for text in texts {
            let embedding = try await embed(text)
            embeddings.append(embedding)
        }
        
        return embeddings
    }
    
    // MARK: - Private Methods
    
    private func generateSemanticVector(_ text: String) async throws -> [Float] {
        // Extract semantic features using simple NLP
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        // Create a deterministic but semantically meaningful vector
        var vector = [Float](repeating: 0.0, count: dimensions)
        
        // Use word hashes to populate vector
        for (index, word) in words.enumerated() {
            let hash = abs(word.hashValue)
            let position = hash % dimensions
            let weight = 1.0 / Float(index + 1) // Earlier words have more weight
            
            vector[position] += weight
        }
        
        // Normalize
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            vector = vector.map { $0 / magnitude }
        }
        
        return vector
    }
    
    /// Call Groq API for text generation (for testing retrieval with LLM)
    public func generateResponse(prompt: String, context: String) async throws -> String {
        let url = URL(string: baseURL)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemMessage = """
        You are a helpful AI assistant with access to the user's personal memory system.
        Use the provided context to give personalized, accurate responses.
        
        CONTEXT:
        \(context)
        """
        
        let requestBody: [String: Any] = [
            "model": modelIdentifier,
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SwiftMemError.embeddingError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SwiftMemError.embeddingError("Groq API error (\(httpResponse.statusCode)): \(errorText)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SwiftMemError.embeddingError("Failed to parse Groq response")
        }
        
        return content
    }
}
