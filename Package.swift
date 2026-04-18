// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftKanaKanji",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "KanaKanjiCore",
            targets: ["KanaKanjiCore"]
        ),
        .executable(
            name: "kana-kanji",
            targets: ["KanaKanjiCLI"]
        )
    ],
    targets: [
        .target(
            name: "KanaKanjiCore"
        ),
        .executableTarget(
            name: "KanaKanjiCLI",
            dependencies: ["KanaKanjiCore"]
        ),
        .testTarget(
            name: "KanaKanjiCoreTests",
            dependencies: ["KanaKanjiCore"]
        )
    ]
)
