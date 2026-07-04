// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenMeter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "TokenMeter",
            targets: ["TokenMeter"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TokenMeter",
            path: "Sources/TokenMeter"
        )
    ]
)
