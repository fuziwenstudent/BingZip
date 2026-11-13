// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BingZip",
    platforms: [
        .macOS(.v11)
    ],
    targets: [
        .executableTarget(
            name: "BingZip",
            path: "Sources/BingZip"
        )
    ]
)