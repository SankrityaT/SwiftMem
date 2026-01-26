# SwiftMem Embedding Guide

SwiftMem uses **Apple's NLEmbedding** for all embedding operations.

## NLEmbedding (Default)

**What is it?**
- Apple's built-in text embedding framework
- Available on iOS 16+ and macOS 13+
- Fully private, runs on-device
- No configuration or downloads required

**Specifications:**
- **Dimensions:** 512
- **Language:** English (primary)
- **Performance:** Fast, optimized for Apple Silicon
- **Privacy:** 100% on-device, no data leaves your device

## Usage

```swift
import SwiftMem

// NLEmbedding is used automatically
let api = SwiftMemAPI.shared
try await api.initialize()  // That's it!

// Add memories
try await api.add(content: "I love hiking", userId: "user123")

// Search memories
let results = try await api.search(query: "outdoor activities", userId: "user123")
```

## Custom Embedders

If you need a custom embedding solution, implement the `Embedder` protocol:

```swift
struct MyCustomEmbedder: Embedder {
    let dimensions: Int = 512
    let modelIdentifier: String = "my-custom-embedder"
    
    func embed(_ text: String) async throws -> [Float] {
        // Your embedding logic
    }
    
    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        // Batch embedding logic
    }
}

// Use it
let embedder = MyCustomEmbedder()
let config = SwiftMemConfig.default
let swiftMem = try await SwiftMemClient.makeOnDisk(config: config, embedder: embedder)
```

## Why NLEmbedding?

- ✅ **Zero setup** - Works out of the box
- ✅ **Fully private** - Never leaves your device
- ✅ **No downloads** - Built into iOS/macOS
- ✅ **Optimized** - Fast on Apple Silicon
- ✅ **Reliable** - Maintained by Apple

---

*For advanced use cases requiring different embedding models, implement the `Embedder` protocol.*
