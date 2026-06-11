// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Traducify",
    platforms: [.macOS(.v14)],
    targets: [
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.6/whisper-v1.8.6-xcframework.zip",
            checksum: "654f6534b1d109cf1f53c3ac94de14d1aedbc08600bf9743e2b331c1619a863f"
        ),
        .executableTarget(
            name: "Traducify",
            dependencies: ["whisper"],
            path: "Sources/Traducify"
        ),
    ]
)
