// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LedgeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LedgeCore", targets: ["LedgeCore"])
    ],
    dependencies: [],
    targets: [
        .target(name: "LedgeCore"),
        .testTarget(name: "LedgeCoreTests", dependencies: ["LedgeCore"])
    ]
)
