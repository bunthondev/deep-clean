// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeepClean",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DeepClean",
            path: "Sources/DeepClean"
        )
    ]
)
