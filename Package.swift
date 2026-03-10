// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// SwiftMem Swift Package manifest
// Created by Sankritya on 12/9/25.

import PackageDescription

let package = Package(
    name: "SwiftMem",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftMem",
            targets: ["SwiftMem"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/SankrityaT/OnDeviceCatalyst.git", branch: "main"),
        .package(url: "https://github.com/jkrukowski/swift-embeddings.git", from: "0.0.1")
    ],
    targets: [
        .target(
            name: "SwiftMem",
            dependencies: [
                .product(name: "OnDeviceCatalyst", package: "OnDeviceCatalyst"),
                .product(name: "Embeddings", package: "swift-embeddings")
            ],
            path: "SwiftMem",
            exclude: [
                "SwiftMemApp.swift",
                "Views/",
                "Extra Files/"
            ]
        )
    ]
)
