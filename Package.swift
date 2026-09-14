// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "lanes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lanes", targets: ["lanes"]),
        .executable(name: "lanes-mcp", targets: ["lanes-mcp"])
    ],
    targets: [
        .executableTarget(name: "lanes", path: "Sources/lanes"),
        .executableTarget(name: "lanes-mcp", path: "Sources/lanes-mcp"),
        .testTarget(name: "lanesTests", dependencies: ["lanes"], path: "Tests/lanesTests")
    ]
)
