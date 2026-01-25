# SwiftMem

**Production-ready, on-device graph memory system for Swift.** SOTA memory management for AI applications - 100% private, zero dependencies.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2016%2B%20%7C%20macOS%2013%2B-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![SPM](https://img.shields.io/badge/SPM-Compatible-brightgreen.svg)](https://swift.org/package-manager)

---

## Quick Start

```swift
import SwiftMem

// 1. Initialize (once at app launch)
try await SwiftMemAPI.shared.initialize()

// 2. Add memories
try await SwiftMemAPI.shared.add(
    content: "User prefers morning workouts",
    userId: "user_123"
)

// 3. Search memories
let memories = try await SwiftMemAPI.shared.search(
    query: "fitness preferences",
    userId: "user_123",
    limit: 5
)

// 4. Use in your AI prompt
let context = memories.map { $0.content }.joined(separator: "\n")
let prompt = "Context: \(context)\n\nUser: \(userMessage)"
```

**That's it.** SwiftMem handles embeddings, relationships, decay, and search automatically.

---

## Why SwiftMem?

### The Problem
- **AI apps forget context** between sessions
- **Sending full conversation history** is slow and expensive
- **No native Swift solution** for graph-based memory (Python has LangChain/Mem0)
- **Privacy concerns** with cloud-based memory systems

### The Solution
SwiftMem provides **intelligent, contextual memory** for AI applications:
- ✅ **Semantic search** - Find relevant memories, not just keyword matches
- ✅ **Relationship detection** - Understand how memories connect
- ✅ **Automatic decay** - Forget irrelevant information over time
- ✅ **100% private** - All processing on-device with Apple's NLEmbedding
- ✅ **Zero dependencies** - No external APIs or cloud services required

---

## Features

### Core Capabilities

| Feature | Description | Status |
|---------|-------------|--------|
| **Embeddings** | 512-dim semantic vectors via NLEmbedding | ✅ |
| **Relationships** | UPDATES, EXTENDS, RELATEDTO (0.725 threshold) | ✅ |
| **Hybrid Search** | Keyword + semantic + graph expansion | ✅ |
| **Memory Decay** | Time-based confidence reduction | ✅ |
| **User Profiles** | Static vs dynamic memory classification | ✅ |
| **Container Tags** | Session/topic/user organization | ✅ |
| **Consolidation** | Duplicate detection and merging | ✅ |
| **Batch Operations** | Parallel processing for bulk imports | ✅ |

### Performance
- **81.7% accuracy** on LongMemEval benchmark
- **<100ms search** for 1000 memories
- **5-10x faster** batch operations vs individual adds
- **1.5KB per memory** (embedding + metadata)

---

## API Reference

### Initialization

```swift
// Basic initialization (uses NLEmbedding)
try await SwiftMemAPI.shared.initialize()

// Custom configuration
var config = SwiftMemConfig.default
config.similarityThreshold = 0.3
try await SwiftMemAPI.shared.initialize(config: config)
```

### Adding Memories

```swift
// Simple add
try await SwiftMemAPI.shared.add(
    content: "User loves Italian food",
    userId: "user_123"
)

// Add with container tags
try await SwiftMemAPI.shared.add(
    content: "Discussed work-life balance",
    userId: "user_123",
    metadata: nil,
    containerTags: ["session:2025-01-24", "topic:work"]
)

// Batch add (5-10x faster)
try await SwiftMemAPI.shared.batchAdd(
    contents: [
        "User prefers morning workouts",
        "User struggles with procrastination",
        "User loves reading sci-fi"
    ],
    userId: "user_123",
    containerTags: [
        ["topic:fitness"],
        ["topic:productivity"],
        ["topic:hobbies"]
    ]
)
```

### Searching Memories

```swift
// Basic search
let results = try await SwiftMemAPI.shared.search(
    query: "What does the user like to eat?",
    userId: "user_123",
    limit: 5
)

// Search with tag filtering
let workMemories = try await SwiftMemAPI.shared.search(
    query: "stress management",
    userId: "user_123",
    limit: 5,
    containerTags: ["topic:work"]
)

// Access results
for memory in results {
    print(memory.content)      // Original text
    print(memory.score)        // Similarity score (0-1)
    print(memory.timestamp)    // When it was created
    print(memory.isStatic)     // Core fact vs episodic
}
```

### Memory Management

```swift
// Get statistics
let stats = try await SwiftMemAPI.shared.getStats()
print("Total memories: \(stats.totalMemories)")
print("Relationships: \(stats.totalRelationships)")

// Consolidate duplicates
let removed = try await SwiftMemAPI.shared.consolidateMemories(userId: "user_123")
print("Removed \(removed) duplicate memories")

// Batch delete
try await SwiftMemAPI.shared.batchDelete(ids: [uuid1, uuid2, uuid3])
```

---

## Container Tags

Organize memories by session, topic, user, or any custom dimension:

```swift
// Tag conventions
"session:2025-01-24"      // Session date
"topic:work_stress"       // Topic category
"user:user_123"           // User ID
"month:January"           // Time period
"type:preference"         // Memory type
"migrated:true"           // Migration flag
```

**Benefits:**
- Filter searches to specific contexts
- Enable temporal queries ("What happened in January?")
- Organize by topic or category
- Flexible and powerful organization system

---

## Integration Examples

### With Local AI (Qwen, Llama, etc.)

```swift
// After each conversation
let summary = await qwenModel.generateSummary(conversation)
try await SwiftMemAPI.shared.add(
    content: summary,
    userId: userId,
    metadata: nil,
    containerTags: ["session:\(Date().ISO8601Format())", "type:summary"]
)

// Before next conversation
let context = try await SwiftMemAPI.shared.search(
    query: userMessage,
    userId: userId,
    limit: 5
)

let enhancedPrompt = """
Previous context:
\(context.map { $0.content }.joined(separator: "\n\n"))

User: \(userMessage)
"""

let response = await qwenModel.generate(enhancedPrompt)
```

### With Cloud APIs (OpenAI, Claude, etc.)

```swift
// Store conversation insights
try await SwiftMemAPI.shared.add(
    content: "User mentioned feeling anxious about presentation",
    userId: userId,
    containerTags: ["topic:anxiety", "session:\(sessionId)"]
)

// Retrieve relevant context
let memories = try await SwiftMemAPI.shared.search(
    query: "anxiety and presentations",
    userId: userId,
    limit: 3
)

// Send to API with context
let messages = [
    ["role": "system", "content": "Context: \(memories.map { $0.content }.joined())"],
    ["role": "user", "content": userMessage]
]
```

---

## Architecture

### Technical Details

**Core Architecture:**
- Relationship threshold: 0.725 (72.5% similarity)
- k-NN optimization: max 10 comparisons per memory
- Three relationship types: UPDATES, EXTENDS, RELATEDTO
- Hybrid search: keyword + semantic + graph expansion

**Advanced Features:**
- ✅ Graph expansion in search
- ✅ Static memory boosting for core facts
- ✅ Automatic memory decay system
- ✅ User profile management
- ✅ Container tags for organization
- ✅ Batch operations for efficiency
- ✅ Memory consolidation

### How It Works

```
User Input
    ↓
[NLEmbedding] → 512-dim vector
    ↓
[Relationship Detection] → Find similar memories (0.725 threshold)
    ↓
[Memory Graph] → Store with relationships
    ↓
Search Query
    ↓
[Hybrid Search]
    ├─ Keyword matching
    ├─ Semantic similarity
    ├─ Graph expansion
    └─ Static boosting
    ↓
Ranked Results
```

---

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/SankrityaT/SwiftMem.git", branch: "main")
]
```

**In Xcode:**
1. File → Add Package Dependencies
2. Enter: `https://github.com/SankrityaT/SwiftMem.git`
3. Select: `main` branch

**No dependencies required** - uses Apple's built-in NLEmbedding.

---

## Data Migration

Migrating existing user data? Use batch operations:

```swift
// Extract existing data
let existingData: [(content: String, tags: [String])] = [
    ("User prefers morning workouts", ["topic:fitness"]),
    ("User struggles with work-life balance", ["topic:work"]),
    // ... more data
]

// Batch import
try await SwiftMemAPI.shared.batchAdd(
    contents: existingData.map { $0.content },
    userId: userId,
    containerTags: existingData.map { $0.tags }
)

// Consolidate duplicates
let removed = try await SwiftMemAPI.shared.consolidateMemories(userId: userId)
```

See [SEEME_DATA_MIGRATION_PLAN.md](SEEME_DATA_MIGRATION_PLAN.md) for detailed migration strategies.

---

## Benchmarks

**LongMemEval Results:**
- Overall: **81.7%** accuracy
- Multi-session: **90.1%**
- Single-session (assistant): **100%**
- Knowledge update: **81.9%**
- Temporal reasoning: **81.9%**

**Performance:**
- Search latency: <100ms for 1000 memories
- Batch operations: 5-10x faster than individual adds
- Memory usage: ~1.5KB per memory (embedding + metadata)

---

## Use Cases

### Personal AI Assistants
- Remember user preferences across sessions
- Recall past conversations and context
- Provide personalized recommendations

### Coaching & Therapy Apps
- Track user progress over time
- Identify patterns and themes
- Maintain session continuity

### Journaling & Note-Taking
- Connect related thoughts and ideas
- Surface relevant past entries
- Build knowledge graphs

### Customer Support
- Remember customer history
- Provide contextual responses
- Track issue resolution

---

## Roadmap

- [ ] CloudKit sync for multi-device support
- [ ] Custom embedding models (BGE-Small, Nomic)
- [ ] Advanced graph algorithms (PageRank, community detection)
- [ ] Memory compression for long-term storage
- [ ] Real-time collaboration features

---

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- Built with Apple's NLEmbedding framework
- Benchmarked on [LongMemEval](https://github.com/Victorwz/LongMemEval)
- Inspired by modern graph-based memory systems

---

## Support

- **Documentation:** [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)
- **Issues:** [GitHub Issues](https://github.com/SankrityaT/SwiftMem/issues)
- **Discussions:** [GitHub Discussions](https://github.com/SankrityaT/SwiftMem/discussions)

---

**Built with ❤️ for the Swift community**
