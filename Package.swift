// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UsageToolbar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "UsageToolbar",
            targets: ["UsageToolbar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "UsageToolbar",
            path: "Sources/UsageToolbar"
        )
    ]
)
