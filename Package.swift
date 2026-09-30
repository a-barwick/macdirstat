// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacDirStat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacDirStat",
            path: "Sources/MacDirStat"
        )
    ]
)
