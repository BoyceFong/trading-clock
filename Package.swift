// swift-tools-version: 6.2
// TradingClock — floating flip-clock overlay for 5-minute candle trading (SwiftUI + Liquid Glass).
import PackageDescription

let package = Package(
    name: "TradingClock",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "TradingClock",
            path: "Sources/TradingClock",
            resources: [
                .copy("Resources/en.lproj"),
                .copy("Resources/zh-Hans.lproj")
            ]
        )
    ]
)
