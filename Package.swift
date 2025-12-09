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
        // OnDeviceCatalyst is optional; SwiftMem compiles without it.
        // If your app also depends on OnDeviceCatalyst, `OnDeviceCatalystEmbedder`
        // will automatically be available via `#if canImport(OnDeviceCatalyst)`.
    ],
    targets: [
        .target(
            name: "SwiftMem",
            // Sources are located in the top-level 'SwiftMem' folder next to this Package.swift
            path: "SwiftMem",
            exclude: [
                // Exclude the app entrypoint; the package is a pure library.
                "SwiftMemApp.swift"
            ]
        )
    ]
)
