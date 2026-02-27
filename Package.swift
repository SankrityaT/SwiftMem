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
        .package(url: "https://github.com/SankrityaT/OnDeviceCatalyst.git", branch: "main")
    ],
    targets: [
        .target(
            name: "SwiftMem",
            dependencies: [
                .product(name: "OnDeviceCatalyst", package: "OnDeviceCatalyst")
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
