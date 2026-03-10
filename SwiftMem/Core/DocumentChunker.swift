//
//  DocumentChunker.swift
//  SwiftMem
//
//  Text chunking for document ingestion with overlap for context preservation
//

import Foundation

/// Chunks text documents for embedding and storage
public struct DocumentChunker {

    /// A chunk of text with its byte offset in the original document
    public struct Chunk {
        public let content: String
        public let offset: Int
    }

    /// Split text into overlapping chunks using recursive boundary splitting
    /// - Parameters:
    ///   - text: The full document text
    ///   - chunkSize: Target chunk size in characters (default 512)
    ///   - overlap: Overlap between chunks in characters (default 128)
    /// - Returns: Array of chunks with their byte offsets
    public static func chunk(
        text: String,
        chunkSize: Int = 512,
        overlap: Int = 128
    ) -> [Chunk] {
        guard !text.isEmpty else { return [] }
        guard text.count > chunkSize else {
            return [Chunk(content: text, offset: 0)]
        }

        var chunks: [Chunk] = []
        var currentOffset = 0

        while currentOffset < text.count {
            let startIndex = text.index(text.startIndex, offsetBy: currentOffset)
            let endOffset = min(currentOffset + chunkSize, text.count)
            let endIndex = text.index(text.startIndex, offsetBy: endOffset)

            var chunkEnd = endIndex

            // Try to split at a natural boundary if we're not at the end
            if endOffset < text.count {
                let segment = String(text[startIndex..<endIndex])
                chunkEnd = findBestBoundary(in: segment, from: startIndex, in: text)
            }

            let chunkText = String(text[startIndex..<chunkEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunkText.isEmpty {
                chunks.append(Chunk(content: chunkText, offset: currentOffset))
            }

            let chunkLength = text.distance(from: startIndex, to: chunkEnd)
            let advance = max(chunkLength - overlap, 1)
            currentOffset += advance
        }

        return chunks
    }

    /// Find the best split boundary within a segment, preferring paragraph > sentence > word breaks
    private static func findBestBoundary(
        in segment: String,
        from startIndex: String.Index,
        in fullText: String
    ) -> String.Index {
        // Try paragraph boundary (double newline)
        if let range = segment.range(of: "\n\n", options: .backwards) {
            let offset = segment.distance(from: segment.startIndex, to: range.upperBound)
            return fullText.index(startIndex, offsetBy: offset)
        }

        // Try sentence boundary
        let sentenceEnders: [Character] = [".", "!", "?"]
        if let lastSentenceEnd = segment.lastIndex(where: { sentenceEnders.contains($0) }) {
            let offset = segment.distance(from: segment.startIndex, to: segment.index(after: lastSentenceEnd))
            return fullText.index(startIndex, offsetBy: offset)
        }

        // Try word boundary (space/newline)
        if let lastSpace = segment.lastIndex(where: { $0.isWhitespace }) {
            let offset = segment.distance(from: segment.startIndex, to: lastSpace)
            return fullText.index(startIndex, offsetBy: offset)
        }

        // Fall back to hard cut at segment end
        let offset = segment.count
        return fullText.index(startIndex, offsetBy: offset)
    }
}
