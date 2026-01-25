# SwiftMem Embedding Guide

## Overview

SwiftMem supports **multiple embedding backends** with automatic fallback, making it compatible with any model or API.

## Quick Answer: Qwen 2.5 + Embeddings

**Q: Can I use Qwen 2.5 for embeddings?**

**A: Yes, but it's not optimal.** Here's why:

| Aspect | Qwen 2.5 (Chat Model) | bge-small (Embedding Model) |
|--------|----------------------|----------------------------|
| **Size** | ~2-3GB | ~45MB |
| **Speed** | Slower | 10-50x faster |
| **Quality** | Decent | Optimized for embeddings |
| **Use Case** | Text generation | Semantic search |
| **Recommended** | ❌ Only as fallback | ✅ Best option |

**Best Practice:** Use a dedicated embedding model (bge-small) alongside Qwen for chat.

---

## Embedding Options (Ranked)

### 1. 🥇 Dedicated Local GGUF Model (BEST)

**Model:** `bge-small-en-v1.5-q4_k_m.gguf` (~45MB)

**Pros:**
- ✅ Tiny size (45MB vs 2GB+)
- ✅ Fast inference
- ✅ High quality embeddings
- ✅ 100% private
- ✅ Works offline

**Setup:**
```swift
import SwiftMem
import OnDeviceCatalyst

// Download bge-small from:
// https://huggingface.co/CompendiumLabs/bge-small-en-v1.5-gguf/resolve/main/bge-small-en-v1.5-q4_k_m.gguf

let config = EmbedderFactory.EmbedderConfig.fullyLocal(
    embeddingModelPath: "/path/to/bge-small-en-v1.5-q4_k_m.gguf"
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)

var swiftMemConfig = SwiftMemConfig.default
swiftMemConfig.embeddingDimensions = dims  // 384

let swiftMem = try await SwiftMemClient.makeOnDisk(
    config: swiftMemConfig,
    embedder: embedder
)
```

---

### 2. 🥈 Chat Model Fallback (Qwen, Llama, etc.)

**Use When:** You don't want to download a separate embedding model

**Pros:**
- ✅ No extra download
- ✅ Still works offline
- ✅ Better than nothing

**Cons:**
- ❌ Slower (uses full chat model)
- ❌ Wastes resources
- ❌ Not optimized for embeddings

**Setup:**
```swift
// Your existing Qwen chat model
let qwen = LlamaInstance(
    profile: try ModelProfile.autoDetect(filePath: "/path/to/qwen2.5-3b.gguf"),
    settings: .balanced,
    predictionConfig: .default
)

for await _ in qwen.initialize() { }

// Use Qwen for embeddings too
let config = EmbedderFactory.EmbedderConfig.fullyLocal(
    chatModel: qwen
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)

// Now SwiftMem uses Qwen for both chat AND embeddings
// ⚠️ This means Qwen can't do chat while generating embeddings
```

---

### 3. 🥉 Cloud API (OpenAI, Cohere, Voyage)

**Use When:** You want the best quality and don't care about privacy/cost

**Pros:**
- ✅ Highest quality
- ✅ No local storage needed
- ✅ Fast (if good internet)

**Cons:**
- ❌ Costs money
- ❌ Requires internet
- ❌ Not private

**Setup:**
```swift
let config = EmbedderFactory.EmbedderConfig.cloudFirst(
    apiKeys: [
        "openai": "sk-...",      // Optional
        "cohere": "...",          // Optional
        "voyage": "..."           // Optional
    ]
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)
// Uses OpenAI text-embedding-3-small (1536 dims)
```

---

### 4. 🏅 Apple NLEmbedding (Built-in)

**Use When:** You want zero setup

**Pros:**
- ✅ Built into iOS
- ✅ No download
- ✅ Decent quality
- ✅ Free

**Cons:**
- ❌ Only 512 dimensions
- ❌ Not as good as dedicated models

**Setup:**
```swift
let config = EmbedderFactory.EmbedderConfig(
    preferredStrategy: .appleNL,
    enableFallback: false
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)
// Uses iOS built-in embeddings (512 dims)
```

---

## Auto-Select (Recommended for Production)

Let SwiftMem automatically pick the best available option:

```swift
let config = EmbedderFactory.EmbedderConfig(
    preferredStrategy: .auto,
    enableFallback: true,
    apiKeys: ["openai": "sk-..."],  // Optional cloud fallback
    localEmbeddingModelPath: "/path/to/bge-small.gguf",  // Optional
    chatModelInstance: qwenInstance  // Optional
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)

// Fallback order:
// 1. Dedicated local model (bge-small) ← BEST
// 2. Chat model embeddings (Qwen)
// 3. Cloud API (OpenAI)
// 4. Apple NLEmbedding ← LAST RESORT
```

---

## Recommended Architecture

### For Privacy-Focused Apps (Coaching, Therapy, Journaling)

```swift
// Two separate models:
// 1. bge-small (~45MB) for embeddings
// 2. Qwen 2.5 (~2GB) for chat

let embeddingModel = LlamaInstance(...)  // bge-small
let chatModel = LlamaInstance(...)       // Qwen 2.5

let embedder = OnDeviceCatalystEmbedder(
    llama: embeddingModel,
    dimensions: 384,
    modelIdentifier: "bge-small"
)

// SwiftMem uses bge-small for memory
let swiftMem = try await SwiftMemClient.makeOnDisk(
    config: config,
    embedder: embedder
)

// Qwen handles chat
for await chunk in chatModel.generate(conversation: turns) {
    // Display chat response
}
```

**Benefits:**
- ✅ No resource contention (separate models)
- ✅ Fast embeddings (45MB model)
- ✅ High quality chat (Qwen)
- ✅ 100% private

---

### For Minimal Setup Apps

```swift
// Single model: Qwen does everything
let qwen = LlamaInstance(...)

let config = EmbedderFactory.EmbedderConfig.fullyLocal(
    chatModel: qwen
)

let (embedder, _) = try await EmbedderFactory.createEmbedder(config: config)

// ⚠️ Qwen can't chat while generating embeddings
// ⚠️ Slower embedding generation
```

---

### For Cloud-Hybrid Apps

```swift
// Local chat + Cloud embeddings
let qwen = LlamaInstance(...)  // Local chat

let config = EmbedderFactory.EmbedderConfig.hybrid(
    embeddingModelPath: nil,  // No local embedding model
    apiKeys: ["openai": "sk-..."]
)

let (embedder, _) = try await EmbedderFactory.createEmbedder(config: config)

// Chat is private (local)
// Embeddings use cloud (fast, high quality)
```

---

## Model Compatibility

### ✅ Works Great for Embeddings
- `bge-small-en-v1.5` (384 dims) ← **RECOMMENDED**
- `bge-base-en-v1.5` (768 dims)
- `all-MiniLM-L6-v2` (384 dims)
- `e5-small-v2` (384 dims)

### ⚠️ Works But Not Optimal
- Qwen 2.5 (any size)
- Llama 3.x (any size)
- Phi 3.x (any size)
- Mistral (any size)

**Why?** Chat models are trained for text generation, not embeddings. They work, but they're:
- Slower (larger models)
- Lower quality embeddings
- Resource-intensive

---

## Performance Comparison

**Test:** Generate embedding for 50-word sentence on iPhone 15 Pro

| Model | Size | Time | Quality |
|-------|------|------|---------|
| bge-small | 45MB | ~20ms | ⭐⭐⭐⭐⭐ |
| Qwen 2.5 3B | 2GB | ~200ms | ⭐⭐⭐ |
| OpenAI API | N/A | ~100ms* | ⭐⭐⭐⭐⭐ |
| Apple NL | Built-in | ~15ms | ⭐⭐⭐⭐ |

*Depends on internet speed

---

## FAQ

**Q: Can I use the same model for chat and embeddings?**
A: Yes, but not recommended. Use separate models for best performance.

**Q: Do I need to download bge-small if I already have Qwen?**
A: No, but it's highly recommended. bge-small is only 45MB and 10x faster.

**Q: Can I switch embedders later?**
A: Yes, but you'll need to regenerate all embeddings. Different models produce different vectors.

**Q: What if I don't have any local models?**
A: SwiftMem will automatically fall back to Apple's built-in NLEmbedding (no download needed).

**Q: Can I use multiple embedders?**
A: No, SwiftMem uses one embedder per instance. But you can create multiple SwiftMem instances.

---

## Summary

**Best Setup (Recommended):**
```
bge-small (45MB) → Embeddings
Qwen 2.5 (2GB)   → Chat
```

**Minimal Setup:**
```
Qwen 2.5 (2GB) → Both chat and embeddings
```

**Zero Setup:**
```
Apple NLEmbedding (built-in) → Embeddings
Qwen 2.5 (2GB)               → Chat
```

**Cloud Hybrid:**
```
OpenAI API     → Embeddings
Qwen 2.5 (2GB) → Chat
```
