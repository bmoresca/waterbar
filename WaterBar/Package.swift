// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WaterBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WaterBar", path: "Sources/WaterBar")
    ]
)
