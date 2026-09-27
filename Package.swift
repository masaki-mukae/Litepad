// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Litepad",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Litepad",
            path: "Sources/Litepad"
        ),
        .testTarget(
            name: "LitepadTests",
            dependencies: ["Litepad"],
            path: "Tests/LitepadTests"
        ),
    ]
)
