// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YTMusic",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "YTMusic",
            path: "Sources/YTMusic"
        )
    ]
)
