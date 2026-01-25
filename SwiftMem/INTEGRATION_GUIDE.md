# SwiftMem Integration Guide for Host Apps

## Overview

SwiftMem is a **Swift Package** that provides graph-based memory for AI apps. This guide shows how to integrate it into your iOS app with model downloads.

---

## Installation

### 1. Add SwiftMem Package

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/yourusername/SwiftMem.git", from: "1.0.0"),
    .package(url: "https://github.com/yourusername/OnDeviceCatalyst.git", from: "1.0.0")
]
```

### 2. Import in Your App

```swift
import SwiftMem
import OnDeviceCatalyst
```

---

## Quick Start (3 Steps)

### Step 1: Let Users Download Embedding Model

SwiftMem provides a ready-to-use download UI:

```swift
import SwiftUI
import SwiftMem

struct SettingsView: View {
    @State private var showModelDownload = false
    
    var body: some View {
        Button("Download Embedding Model") {
            showModelDownload = true
        }
        .sheet(isPresented: $showModelDownload) {
            ModelDownloadView()  // Built-in SwiftMem UI
        }
    }
}
```

**That's it!** Users can now download models directly in your app.

### Step 2: Initialize SwiftMem with Downloaded Model

```swift
import SwiftMem
import OnDeviceCatalyst

class MemoryService {
    private var swiftMem: SwiftMemClient?
    private var embeddingModel: LlamaInstance?
    
    func initialize() async throws {
        // 1. Check if user has downloaded a model
        let downloadManager = try ModelDownloadManager()
        
        guard let (model, modelPath) = await downloadManager.getBestAvailableModel() else {
            throw SwiftMemError.configurationError("No embedding model downloaded. Ask user to download one.")
        }
        
        print("Using embedding model: \(model.displayName)")
        
        // 2. Load the embedding model
        let profile = try ModelProfile.autoDetect(filePath: modelPath.path)
        let settings = InstanceSettings(
            contextLength: 512,
            batchSize: 512,
            gpuLayers: 99,
            cpuThreads: 4,
            enableMemoryMapping: true,
            enableMemoryLocking: false,
            useFlashAttention: false
        )
        
        embeddingModel = LlamaInstance(
            profile: profile,
            settings: settings,
            predictionConfig: .default
        )
        
        // Initialize the model
        for await progress in embeddingModel!.initialize() {
            print(progress.message)
        }
        
        // 3. Create embedder
        let embedder = OnDeviceCatalystEmbedder(
            llama: embeddingModel!,
            dimensions: model.dimensions,
            modelIdentifier: model.rawValue
        )
        
        // 4. Create SwiftMem
        var config = SwiftMemConfig.default
        config.embeddingDimensions = model.dimensions
        
        swiftMem = try await SwiftMemClient.makeOnDisk(
            config: config,
            embedder: embedder
        )
        
        print("✅ SwiftMem initialized with \(model.displayName)")
    }
}
```

### Step 3: Use SwiftMem in Your App

```swift
// Store user messages
try await swiftMem.storeMessage(
    text: "I love running in the morning",
    role: .user
)

// Retrieve relevant memories
let context = try await swiftMem.retrieveContext(
    for: "What exercise do I like?",
    maxResults: 5
)

// Use context with your chat model
let memories = context.formatted
let prompt = """
Context from user's memories:
\(memories)

User: What exercise do I like?
Assistant:
"""
```

---

## Architecture Options

### Option 1: Separate Models (Recommended)

**Best for:** Production apps, privacy-focused apps

```
Embedding Model (nomic-v2, 140MB)  → SwiftMem
Chat Model (Qwen 2.5, 2GB)         → Conversations
```

**Benefits:**
- ✅ No resource contention
- ✅ Fast embeddings (dedicated model)
- ✅ Can embed while chatting

**Code:**
```swift
// Embedding model for SwiftMem
let embeddingModel = LlamaInstance(...)  // nomic-v2
let embedder = OnDeviceCatalystEmbedder(llama: embeddingModel, ...)

// Chat model for conversations
let chatModel = LlamaInstance(...)  // Qwen 2.5

// They work independently
```

---

### Option 2: Single Model (Minimal)

**Best for:** Prototypes, minimal storage

```
Chat Model (Qwen 2.5, 2GB) → Both chat AND embeddings
```

**Trade-offs:**
- ⚠️ Can't chat while generating embeddings
- ⚠️ Slower embeddings
- ✅ Only one model to download

**Code:**
```swift
// Use chat model for everything
let qwen = LlamaInstance(...)

let embedder = OnDeviceCatalystEmbedder(
    llama: qwen,
    dimensions: 384,  // Qwen's embedding size
    modelIdentifier: "qwen2.5"
)

// ⚠️ Qwen is now shared between chat and embeddings
```

---

### Option 3: Cloud Embeddings (Hybrid)

**Best for:** Apps with internet, cost-conscious

```
Cloud API (OpenAI)         → Embeddings
Local Model (Qwen 2.5)     → Chat (private)
```

**Code:**
```swift
let config = EmbedderFactory.EmbedderConfig.cloudFirst(
    apiKeys: ["openai": "sk-..."]
)

let (embedder, dims) = try await EmbedderFactory.createEmbedder(config: config)

// Chat stays local, embeddings use cloud
```

---

## Custom UI (Advanced)

If you want to build your own download UI instead of using `ModelDownloadView`:

```swift
import SwiftMem

class ModelManager: ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    
    private let downloadManager: ModelDownloadManager
    
    init() throws {
        self.downloadManager = try ModelDownloadManager()
    }
    
    func downloadNomic() async throws {
        isDownloading = true
        
        _ = try await downloadManager.downloadModel(.nomicV2) { progress in
            Task { @MainActor in
                self.downloadProgress = progress.percentage
                
                if progress.isComplete {
                    self.isDownloading = false
                }
            }
        }
    }
    
    func checkDownloaded() async -> Bool {
        return await downloadManager.isModelDownloaded(.nomicV2)
    }
}
```

---

## Model Selection Guide

### For Most Apps: nomic-embed-text-v2
- 140MB, 768 dimensions
- SOTA 2026, 8k context
- Best quality/size ratio

### For Minimal Apps: bge-small-en-v1.5
- 45MB, 384 dimensions
- Fast, lightweight
- Good quality

### For Maximum Quality: mxbai-embed-large
- 340MB, 1024 dimensions
- Highest quality
- Slower inference

---

## Error Handling

```swift
do {
    try await memoryService.initialize()
} catch SwiftMemError.configurationError(let message) {
    if message.contains("No embedding model") {
        // Show download UI
        showModelDownload = true
    }
} catch {
    print("Unexpected error: \(error)")
}
```

---

## Storage Management

```swift
let downloadManager = try ModelDownloadManager()

// Check storage
let (totalSize, modelCount) = await downloadManager.getStorageInfo()
print("Models using: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")

// Delete old models
try await downloadManager.deleteModel(.bgeSmall)

// Delete all
try await downloadManager.deleteAllModels()
```

---

## Complete Example App

```swift
import SwiftUI
import SwiftMem
import OnDeviceCatalyst

@main
struct MyApp: App {
    @StateObject private var memoryService = MemoryService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(memoryService)
                .task {
                    await memoryService.initializeIfNeeded()
                }
        }
    }
}

class MemoryService: ObservableObject {
    @Published var isReady = false
    @Published var needsModelDownload = false
    
    private var swiftMem: SwiftMemClient?
    
    func initializeIfNeeded() async {
        do {
            let downloadManager = try ModelDownloadManager()
            
            // Check if model exists
            guard let (model, modelPath) = await downloadManager.getBestAvailableModel() else {
                needsModelDownload = true
                return
            }
            
            // Initialize SwiftMem
            let profile = try ModelProfile.autoDetect(filePath: modelPath.path)
            let settings = InstanceSettings.balanced
            
            let embeddingModel = LlamaInstance(
                profile: profile,
                settings: settings,
                predictionConfig: .default
            )
            
            for await _ in embeddingModel.initialize() { }
            
            let embedder = OnDeviceCatalystEmbedder(
                llama: embeddingModel,
                dimensions: model.dimensions,
                modelIdentifier: model.rawValue
            )
            
            var config = SwiftMemConfig.default
            config.embeddingDimensions = model.dimensions
            
            swiftMem = try await SwiftMemClient.makeOnDisk(
                config: config,
                embedder: embedder
            )
            
            isReady = true
            
        } catch {
            print("Failed to initialize: \(error)")
        }
    }
    
    func storeMemory(_ text: String) async throws {
        guard let swiftMem = swiftMem else { return }
        try await swiftMem.storeMessage(text: text, role: .user)
    }
    
    func retrieveMemories(for query: String) async throws -> String {
        guard let swiftMem = swiftMem else { return "" }
        let context = try await swiftMem.retrieveContext(for: query, maxResults: 5)
        return context.formatted
    }
}

struct ContentView: View {
    @EnvironmentObject var memoryService: MemoryService
    @State private var showModelDownload = false
    
    var body: some View {
        Group {
            if memoryService.needsModelDownload {
                VStack(spacing: 20) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 60))
                    Text("Download Embedding Model")
                        .font(.title)
                    Button("Download") {
                        showModelDownload = true
                    }
                }
            } else if memoryService.isReady {
                ChatView()
            } else {
                ProgressView("Initializing...")
            }
        }
        .sheet(isPresented: $showModelDownload) {
            ModelDownloadView()
        }
    }
}
```

---

## Best Practices

### 1. Download on WiFi
```swift
import Network

func shouldAllowDownload() -> Bool {
    let monitor = NWPathMonitor()
    let path = monitor.currentPath
    return path.usesInterfaceType(.wifi)
}
```

### 2. Show Storage Warning
```swift
if model.expectedSize > 100_000_000 {  // 100MB+
    showAlert("This will download \(model.description). Continue?")
}
```

### 3. Cache Model Instance
```swift
// Don't reload model on every app launch
// Keep LlamaInstance alive in a singleton/service
```

### 4. Handle Background Downloads
```swift
// URLSession automatically handles background downloads
// Progress will resume when app returns to foreground
```

---

## FAQ

**Q: Do users need to download models?**
A: Yes, for local embeddings. Or use cloud APIs (no download needed).

**Q: Can I bundle models in the app?**
A: Not recommended - models are 45-340MB. App Store has size limits.

**Q: What if user deletes the model?**
A: SwiftMem will throw an error. Show download UI again.

**Q: Can I update models?**
A: Yes, delete old and download new. Embeddings need regeneration.

**Q: Do embeddings work offline?**
A: Yes, once model is downloaded, everything is local.

---

## Support

- **Documentation:** docs.swiftmem.dev
- **GitHub:** github.com/yourusername/SwiftMem
- **Discord:** discord.gg/swiftmem
