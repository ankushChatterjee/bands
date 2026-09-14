// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "lanes",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "lanes", targets: ["lanes"])],
    targets: [
        .executableTarget(name: "lanes", path: "Sources/lanes"),
        .testTarget(name: "lanesTests", dependencies: ["lanes"], path: "Tests/lanesTests")
    ]
)
