// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HomePower",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "HomePower",
            path: "Sources/HomePower"
        )
    ]
)
