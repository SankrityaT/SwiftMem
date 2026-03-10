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

## Elevating Your App's AI Memory Experience

Without memory, every LLM session starts cold — the AI has no idea who the user is. With SwiftMem, the AI accumulates a personal knowledge graph of each user across every session, making responses feel genuinely intelligent and personal.

### The Core Pattern: Retrieve → Inject → Store

```swift
actor AISession {
    let api = SwiftMemAPI.shared
    let llm: YourLLMClient       // OnDeviceCatalyst, OpenAI, Claude, etc.
    let userId: String
    let sessionId = UUID().uuidString

    /// Call this instead of sending the message directly to your LLM
    func send(_ userMessage: String) async throws -> String {
        // 1. Retrieve what we know about this user relevant to their message
        let memories = try await api.search(
            query: userMessage,
            userId: userId,
            limit: 6
        )

        // 2. Separate core facts from recent episodes
        let facts    = memories.filter { $0.isStatic }.map { "• \($0.content)" }
        let episodes = memories.filter { !$0.isStatic }.map { "• \($0.content)" }

        // 3. Build a context-rich system prompt
        var systemParts: [String] = ["You are a helpful AI assistant."]
        if !facts.isEmpty {
            systemParts.append("Facts about this user:\n\(facts.joined(separator: "\n"))")
        }
        if !episodes.isEmpty {
            systemParts.append("Recent context:\n\(episodes.joined(separator: "\n"))")
        }

        // 4. Call your LLM with enriched context
        let reply = try await llm.complete(
            system: systemParts.joined(separator: "\n\n"),
            user: userMessage
        )

        // 5. Store the exchange so the AI learns from it
        try await api.add(
            content: userMessage,
            userId: userId,
            metadata: nil,
            containerTags: ["session:\(sessionId)", "type:user-message"]
        )

        return reply
    }
}
```

**Before SwiftMem:**
```
System: You are a helpful assistant.
User: What should I have for breakfast?
→ Generic answer about healthy breakfast options
```

**After SwiftMem:**
```
System: You are a helpful assistant.
        Facts about this user:
        • Prefers green tea over coffee every morning
        • Has a lactose intolerance
        • Trains for marathons, high-carb diet
User: What should I have for breakfast?
→ "Based on your marathon training and carb needs, oats with banana
   and your green tea would be a great start..."
```

---

### What to Store vs What to Skip

Not everything a user says deserves a memory. Store signal, skip noise.

```swift
// STORE — facts, preferences, goals, events with personal meaning
try await api.add(content: "I'm training for the London Marathon in April", userId: uid)
try await api.add(content: "Allergic to peanuts", userId: uid)
try await api.add(content: "My daughter Emma started kindergarten this week", userId: uid)
try await api.add(content: "Moved to Austin from Chicago last year", userId: uid)

// STORE — after meaningful conversations, use addConversation to extract facts automatically
let extracted = try await api.addConversation(
    conversation: fullTranscript,   // raw back-and-forth text
    userId: uid
)
// SwiftMem extracts structured facts and stores only the signal

// SKIP — single-turn throwaway messages, greetings, clarification questions
// "Ok", "Thanks", "What do you mean?", "lol" → don't store these
```

---

### Static vs Dynamic: Making the AI Sound Like It Knows the User

SwiftMem automatically classifies memories as **static** (core facts) or **dynamic** (episodic events).

```swift
let memories = try await api.search(query: userMessage, userId: uid, limit: 8)

// Static = identity facts, preferences, permanent traits
let whoTheyAre = memories.filter { $0.isStatic }
// "name is Jordan", "iOS engineer at NovaMind", "has a border collie named Luna"

// Dynamic = what happened recently, evolving context
let whatHappened = memories.filter { !$0.isStatic }
// "went hiking in Yosemite last weekend", "mentioned feeling anxious about demo"

// Use them differently in your system prompt:
let systemPrompt = """
You know this user well:
\(whoTheyAre.map { $0.content }.joined(separator: ". "))

Recent context:
\(whatHappened.map { $0.content }.joined(separator: ". "))

Respond as someone who genuinely knows them — don't reference memories robotically.
"""
```

---

### Session Continuity: Pick Up Exactly Where You Left Off

```swift
// At session start: surface what was discussed last time
let lastSession = try await api.search(
    query: "recent conversations and what we were working on",
    userId: uid,
    limit: 4,
    containerTags: ["session:\(previousSessionId)"]
)

// At session end: store a summary
try await api.add(
    content: "Session summary: \(sessionSummary)",
    userId: uid,
    metadata: nil,
    containerTags: ["session:\(sessionId)", "type:summary"]
)

// Temporal search — "what did we talk about last week?"
let lastWeek = try await api.search(
    query: "what topics did we cover last week?",
    userId: uid,
    limit: 6
    // temporal filter parsed automatically from query
)
```

---

### App-Type Playbook

#### Personal AI Assistant / Chatbot

```swift
// Store every meaningful user message + AI reply summary
// Retrieve: top-6 by relevance to current message
// Prompt injection: "Here's what you know about this user: ..."

// Key tags: "session:{id}", "type:preference", "type:goal", "type:fact"
```

#### Coaching & Therapy App

```swift
// Store: progress check-ins, emotional state, goals, breakthroughs
// Retrieve: recent sessions + relevant historical context
// Use isStatic to separate "I have anxiety" (core) from "hard week at work" (episodic)

// Tag by mood/topic for filtered retrieval:
try await api.add(
    content: "Felt overwhelmed by work deadlines this week",
    userId: uid,
    containerTags: ["topic:stress", "topic:work", "session:\(sid)"]
)

let stressHistory = try await api.search(
    query: "work stress patterns",
    userId: uid,
    containerTags: ["topic:stress"]
)
```

#### Notes & Knowledge Base

```swift
// Use addDocument for long-form content (chunked automatically)
let chunks = try await api.addDocument(
    content: articleText,
    title: "WWDC 2026 Highlights",
    userId: uid,
    containerTags: ["topic:ios", "source:article"]
)

// Later: semantic search across all stored knowledge
let relevant = try await api.search(
    query: "SwiftUI performance improvements",
    userId: uid
)
```

#### Customer Support / CRM

```swift
// Tag by ticket, product, sentiment
try await api.add(
    content: "Reported crash on checkout flow, iOS 17.4, iPhone 14",
    userId: customerId,
    containerTags: ["ticket:\(ticketId)", "topic:crash", "product:checkout"]
)

// Before each support interaction, surface the customer's full history
let history = try await api.search(
    query: "past issues and reported bugs",
    userId: customerId,
    limit: 10
)
```

---

### Integration with OnDeviceCatalyst LLMs

For a fully private, zero-cloud stack:

```swift
let config = SwiftMemConfig(
    storageLocation: .applicationSupport,
    llmConfig: LLMConfig(
        embeddingModel: .nomicEmbedV1_5,   // semantic retrieval (~550 MB)
        completionModel: .qwen25_1_5B,     // fact extraction + reranking (~1.6 GB)
        enableLLMExtraction: true,
        enableLLMReranking: true
    )
)
try await api.initialize(config: config)
```

With a completion model loaded, SwiftMem upgrades automatically:
- `addConversation` extracts structured facts via LLM (vs heuristic regex fallback)
- Search results get reranked by the LLM for semantic relevance
- Contradiction detection can reason about superseded facts (e.g. "moved from Chicago to Austin")

Without a completion model, everything falls back to heuristics — still solid for most apps.

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
