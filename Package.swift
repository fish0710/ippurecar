// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IPPureBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "IPPureBar",
            path: "Sources/IPPureBar"
        )
    ]
)
