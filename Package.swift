// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TeleprompterKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "TeleprompterKit",
            targets: ["TeleprompterKit"]
        )
    ],
    targets: [
        .target(
            name: "TeleprompterKit",
            resources: [.process("Resources")]
        )
    ]
)
