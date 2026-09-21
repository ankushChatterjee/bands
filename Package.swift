// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bands",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "bands", targets: ["bands"]),
        .executable(name: "bands-mcp", targets: ["bands-mcp"])
    ],
    targets: [
        .executableTarget(name: "bands", path: "Sources/bands"),
        .executableTarget(name: "bands-mcp", path: "Sources/bands-mcp"),
        .testTarget(name: "bandsTests", dependencies: ["bands"], path: "Tests/bandsTests")
    ]
)
