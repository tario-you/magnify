// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Magnify",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Magnify",
            targets: ["Magnify"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Magnify"
        )
    ]
)
