// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// SwiftMem Swift Package manifest
// Created by Sankritya on 12/9/25.

import PackageDescription

let package = Package(
    name: "SwiftMem",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftMem",
            targets: ["SwiftMem"]
        )
    ],
    dependencies: [
        // OnDeviceCatalyst is optional - only needed if using BGE-Small embeddings
        // SwiftMem uses NLEmbedding by default (no dependencies required)
    ],
    targets: [
        .target(
            name: "SwiftMem",
            dependencies: [
                // No dependencies - uses Apple's built-in NLEmbedding
            ],
            path: "SwiftMem",
            exclude: [
                // Exclude the app entrypoint; the package is a pure library.
                "SwiftMemApp.swift",
                // Exclude test/demo views
                "Views/",
                "Extra Files/"
            ]
        )
    ]
)
