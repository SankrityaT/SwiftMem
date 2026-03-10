# SwiftMem

**On-device graph memory for Swift AI apps.** Semantic search, temporal reasoning, contradiction detection — 100% private, runs on your GPU.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017%2B%20%7C%20macOS%2014%2B-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![LongMemEval](https://img.shields.io/badge/LongMemEval-10%2F10%20(100%25)-brightgreen.svg)](#benchmarks)

---

## What it does

SwiftMem gives your app persistent, searchable memory across sessions — like Mem0 or MemGPT, but fully on-device. Every memory is embedded, stored in a graph, and retrieved via hybrid BM25 + vector search with Reciprocal Rank Fusion (RRF).

```
User says something → extract → embed → store in SQLite graph
                                              ↓
User asks a question → embed query → hybrid search → ranked results → LLM context
```

---

## Installation

### Requirements

- iOS 17+ / macOS 14+
- Xcode 15+
- [OnDeviceCatalyst](https://github.com/SankrityaT/OnDeviceCatalyst) (peer dependency — auto-downloaded via SPM)

### Swift Package Manager

In Xcode: **File → Add Package Dependencies**

```
https://github.com/SankrityaT/SwiftMem.git
```

Select branch: `main`

> **Important:** Build via Xcode IDE. `swift build` CLI won't link the `llama` XCFramework from OnDeviceCatalyst.

---

## Quick Start

```swift
import SwiftMem
import OnDeviceCatalyst

// 1. Configure — picks nomic-embed-text-v1.5, auto-downloads on first run (~550 MB)
let config = SwiftMemConfig(
    storageLocation: .applicationSupport,
    llmConfig: LLMConfig(embeddingModel: .nomicEmbedV1_5)
)

// 2. Initialize once at app launch
try await SwiftMemAPI.shared.initialize(config: config)

// 3. Add memories
try await SwiftMemAPI.shared.add(
    content: "User prefers morning workouts and hates cardio",
    userId: "user_123"
)

// 4. Search — ask in plain English
let results = try await SwiftMemAPI.shared.search(
    query: "What does the user think about exercise?",
    userId: "user_123",
    limit: 5
)

// 5. Build your LLM context
let context = results.map { $0.content }.joined(separator: "\n")
let prompt = "Relevant memories:\n\(context)\n\nUser: \(userMessage)"
```

That's it. SwiftMem handles embeddings, deduplication, relationships, decay, and retrieval automatically.

---

## Choosing an Embedding Model

| Model | Size | Dims | Best for |
|-------|------|------|----------|
| `nomicEmbedV1_5` | ~550 MB | 768 | iPhone / iPad — best accuracy per MB |
| `gteQwen2_1_5B` | ~1.6 GB | 1536 | Mac / iPad Pro — highest quality |
| *(none — NLEmbedder fallback)* | 0 MB | 512 | No download, lower retrieval accuracy |

```swift
// iPhone/iPad
LLMConfig(embeddingModel: .nomicEmbedV1_5)

// Mac or iPad Pro
LLMConfig(embeddingModel: .gteQwen2_1_5B, enableLLMClassification: true)

// Zero-download fallback (Apple NLEmbedding)
LLMConfig()  // no embeddingModel
```

The model auto-downloads from HuggingFace on first use. Progress is published to `SwiftMemDownloadState.shared` for your SwiftUI download screen.

---

## Core API

### Add

```swift
// Simple
try await api.add(content: "I love Italian food", userId: uid)

// With tags and temporal grounding
try await api.add(
    content: "Had a great 1:1 with my manager today",
    userId: uid,
    metadata: nil,
    containerTags: ["topic:work", "session:2026-03-09"],
    conversationDate: Date()   // when the conversation happened
)

// Extract memories from a raw conversation transcript
let count = try await api.addConversation(
    conversation: fullTranscriptString,
    userId: uid
)
```

### Search

```swift
// Basic
let results = try await api.search(query: "food preferences", userId: uid, limit: 5)

// Tag-scoped (only look inside "topic:work")
let workMems = try await api.search(
    query: "stress at work",
    userId: uid,
    limit: 5,
    containerTags: ["topic:work"]
)

// Temporal — "last week", "yesterday", "recently" parsed automatically
let recent = try await api.search(
    query: "What did I do last weekend?",
    userId: uid
)

// Explicit date range
let interval = DateInterval(start: startDate, end: endDate)
let ranged = try await api.search(
    query: "project updates",
    userId: uid,
    temporalFilter: interval
)

// Each result has:
result.content      // original text
result.score        // RRF relevance score
result.isStatic     // true = core fact (name, job), false = episodic
result.timestamp    // when stored
result.entities     // extracted entities
result.topics       // extracted topics
result.containerTags
```

### Update & Delete

```swift
// Update a specific memory (creates a versioned successor)
try await api.update(memoryId: uuid, newContent: "I moved from Chicago to Austin")

// Delete one
try await api.delete(memoryId: uuid)

// Wipe everything (useful for testing / logout)
try await api.clearAll()
```

### Batch

```swift
// Batch add — serial embedding (thread-safe with llama.cpp)
try await api.batchAdd(
    contents: ["Likes hiking", "Dislikes loud music", "Has a dog named Luna"],
    userId: uid,
    containerTags: [["topic:hobbies"], ["topic:preferences"], ["topic:pets"]]
)
```

---

## Container Tags — How to Organize Memory

Tags let you scope searches and keep memories organized:

```swift
// Suggested conventions
"user:\(userId)"          // automatically added by SwiftMem
"session:\(sessionId)"    // conversation session
"topic:work"              // semantic category
"type:preference"         // memory type
"eval"                    // reserved for eval seeding
```

```swift
// Search only within a session
let sessionMems = try await api.search(
    query: "what we discussed",
    userId: uid,
    containerTags: ["session:abc123"]
)
```

---

## Real App Pattern: Persistent AI Assistant

```swift
actor MemoryMiddleware {
    let api = SwiftMemAPI.shared
    let userId: String

    func beforeLLMCall(userMessage: String) async throws -> String {
        let memories = try await api.search(
            query: userMessage,
            userId: userId,
            limit: 6
        )
        guard !memories.isEmpty else { return userMessage }

        let context = memories.map { "- \($0.content)" }.joined(separator: "\n")
        return """
        Relevant memories about this user:
        \(context)

        User: \(userMessage)
        """
    }

    func afterLLMCall(userMessage: String, assistantReply: String) async throws {
        // Store the user's message as a memory (extract key facts)
        try await api.add(
            content: userMessage,
            userId: userId,
            containerTags: ["session:\(currentSessionId)"]
        )
    }
}
```

---

## Integration with OnDeviceCatalyst LLMs

SwiftMem pairs naturally with OnDeviceCatalyst completion models for a fully on-device stack:

```swift
let config = SwiftMemConfig(
    storageLocation: .applicationSupport,
    llmConfig: LLMConfig(
        embeddingModel: .nomicEmbedV1_5,   // retrieval
        completionModel: .qwen25_1_5B,     // fact extraction + reranking
        enableLLMExtraction: true,
        enableLLMReranking: true
    )
)
try await api.initialize(config: config)
```

When a completion model is loaded, SwiftMem uses it to:
- Extract structured facts from raw conversation text (`addConversation`)
- Rerank retrieved memories by semantic relevance (Phase 3)
- Detect contradictions between new and stored memories

Without a completion model, everything gracefully falls back to heuristics — still very usable.

---

## How the Search Pipeline Works

```
query: "What does the user drink in the mornings?"
    │
    ├─ [Temporal parser] → no temporal expression detected
    │
    ├─ [Embed with prefix] → "search_query: What does the user drink..." → 768-dim vector
    │
    ├─ [BM25] → keyword matches on memory content + topics
    │
    ├─ [Vector search] → cosine similarity against all stored embeddings
    │
    ├─ [RRF fusion] → reciprocal rank fusion of BM25 + vector rankings
    │
    ├─ [Static boost] → core facts boosted if already above median score
    │
    ├─ [Graph expansion] → follow relationship edges (UPDATES, EXTENDS, RELATEDTO)
    │
    └─ [MMR diversification] → remove redundant results
           ↓
    Top-K results → your LLM context
```

**Key detail — asymmetric retrieval:** nomic-embed-text-v1.5 uses task prefixes internally. SwiftMem prepends `"search_query: "` to queries and `"search_document: "` to stored memories automatically. Without this, all cosine similarities collapse to ~0.04 with no meaningful differentiation. You don't need to do anything — it's handled for you.

---

## Temporal Queries

SwiftMem parses natural language time expressions from queries and applies date-range filters automatically:

| Expression | Filter applied |
|---|---|
| `"last week"` / `"last weekend"` | Previous Mon–Sun |
| `"yesterday"` | Previous calendar day |
| `"recently"` / `"lately"` | Last 7 days |
| `"last month"` | Previous calendar month |
| `"3 days ago"` | Specific day ±0 |
| `"in the last 30 days"` | Rolling 30-day window |

```swift
// These all apply temporal filters automatically
try await api.search(query: "What did I do last weekend?", userId: uid)
try await api.search(query: "Any updates from last week?", userId: uid)
try await api.search(query: "What happened recently at work?", userId: uid)
```

To ground a memory at a specific time (e.g. user says "yesterday I went hiking"):

```swift
try await api.add(
    content: "Went hiking at Yosemite",
    userId: uid,
    conversationDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())
)
```

---

## Benchmarks

**LongMemEval-style retrieval eval** (10 questions, 10 seeded memories, Groq llama-3.3-70b judge):

| Category | Score |
|----------|-------|
| Single-hop recall | 4/4 |
| Multi-hop reasoning | 2/2 |
| Temporal grounding | 2/2 |
| Knowledge update | 1/1 |
| Absence detection | 1/1 |
| **Total** | **10/10 (100%)** |

**Performance:**
- Search: <100ms for 1,000 memories
- Batch add: 10 memories in ~2s on iPhone (A18 Pro GPU)
- Memory footprint: ~1.5 KB per stored memory

---

## Model Download — Everything You Need to Know

### When does the download happen?

The model downloads automatically the **first time you call `api.initialize()`** with an `embeddingModel` set. After that it's cached permanently in `Application Support/OnDeviceCatalyst/Models/` — subsequent launches load from disk in ~2 seconds.

| Model | HuggingFace source | Cached size |
|---|---|---|
| `nomicEmbedV1_5` | nomic-ai/nomic-embed-text-v1.5-GGUF (Q8_0) | ~550 MB |
| `gteQwen2_1_5B` | mav23/gte-Qwen2-1.5B-instruct-GGUF (Q8_0) | ~1.6 GB |

> The app needs internet access on first launch only. After that it works fully offline.

### Show a download screen (recommended)

SwiftMem ships a ready-made `ModelDownloadProgressView` overlay. Add it to your root view:

```swift
import SwiftUI
import SwiftMem

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay(ModelDownloadProgressView(state: SwiftMemDownloadState.shared))
        }
    }
}
```

The overlay appears automatically while downloading/verifying and disappears when done. It shows model name, MB downloaded, percentage, and a "this only happens once" note.

### Gate your UI on download completion

```swift
struct ContentView: View {
    // @Observable — no @ObservedObject needed (Swift 5.9+)
    var downloadState = SwiftMemDownloadState.shared

    var body: some View {
        switch downloadState.phase {
        case .idle:
            ProgressView("Initializing...")
        case .downloading(let name, let progress, let dl, let total):
            VStack {
                Text("Downloading \(name)")
                ProgressView(value: progress)
                Text("\(dl) / \(total) MB")
            }
        case .verifying(let name):
            VStack {
                ProgressView()
                Text("Verifying \(name)...")
            }
        case .ready:
            MainAppView()
        case .failed(let error):
            VStack {
                Text("Download failed: \(error)")
                Button("Retry") { Task { try? await SwiftMemAPI.shared.initialize(config: config) } }
            }
        }
    }
}
```

### Initialize at app launch — not on first search

Initialize once in your `App` or root view, not lazily at search time. This ensures the model is loaded before the user interacts:

```swift
@main
struct MyApp: App {
    @State private var isReady = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    ContentView()
                } else {
                    Color.clear  // or a splash screen
                }
            }
            .overlay(ModelDownloadProgressView(state: SwiftMemDownloadState.shared))
            .task {
                let config = SwiftMemConfig(
                    storageLocation: .applicationSupport,
                    llmConfig: LLMConfig(embeddingModel: .nomicEmbedV1_5)
                )
                try? await SwiftMemAPI.shared.initialize(config: config)
                isReady = true
            }
        }
    }
}
```

### No-download option

If you can't afford 550 MB or want instant startup, omit `embeddingModel`. SwiftMem falls back to Apple's built-in `NLEmbedding` (512-dim, no download, lower retrieval accuracy):

```swift
// Instant startup, no internet required, lower accuracy
let config = SwiftMemConfig(storageLocation: .applicationSupport)
// llmConfig defaults to LLMConfig() with no embeddingModel
try await SwiftMemAPI.shared.initialize(config: config)
```
```

---

## Architecture

```
SwiftMemAPI (actor)           ← public interface
    │
    ├─ EmbeddingEngine        ← caching wrapper, task-prefix injection
    │   └─ GGUFEmbedder       ← OnDeviceCatalyst (nomic / gte-Qwen2)
    │       └─ NLEmbedder     ← fallback (Apple NLEmbedding, no download)
    │
    ├─ MemoryGraphStore       ← SQLite persistence (WAL mode)
    │   └─ MemoryGraph        ← in-memory graph with relationship edges
    │
    ├─ HybridSearch           ← BM25 + vector + RRF fusion
    │   ├─ Reranker           ← MMR diversification
    │   └─ LLMReranker        ← optional LLM reranking (Phase 3)
    │
    ├─ MemoryExtractor        ← LLM fact extraction / heuristic fallback
    ├─ RelationshipDetector   ← cosine-threshold edge creation
    ├─ UserProfileManager     ← static vs dynamic classification
    ├─ MemoryDecay            ← per-type exponential confidence decay
    ├─ TemporalQueryParser    ← natural language → DateInterval
    └─ BatchOperations        ← serial batch embed (llama.cpp thread safety)
```

**Storage:** Single SQLite file in Application Support. WAL mode for concurrent reads. Embeddings stored as raw float blobs, loaded into memory on startup.

---

## Common Pitfalls

**Build fails with `llama` linker error**
→ Build from Xcode IDE, not `swift build`. The XCFramework requires Xcode's build system.

**Embeddings return wrong dimensions**
→ Make sure `embeddingDimensions` in `SwiftMemConfig` matches your model (768 for nomic, 1536 for gte-Qwen2).

**Search returns low-relevance results**
→ Don't use the NLEmbedder fallback for production retrieval tasks — it has significantly weaker differentiation. Set `embeddingModel: .nomicEmbedV1_5`.

**Task.sleep / actor isolation errors in batch**
→ Don't call `embedder.embed()` concurrently from TaskGroup — llama.cpp context is not thread-safe. Use `embedder.embedBatch()` which serializes internally.

**Memory not found by temporal query**
→ Pass `conversationDate:` when adding time-grounded memories. The temporal filter checks `eventDate ?? timestamp`.

---

## License

MIT — see [LICENSE](LICENSE)

---

**Built for the Swift community — on-device AI that actually remembers.**
