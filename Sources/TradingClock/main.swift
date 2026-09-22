import AppKit

// TradingClock — floating flip-clock overlay for 5-minute candle trading.

let arguments = CommandLine.arguments

if let idx = arguments.firstIndex(of: "--glow-preview") {
    let dir = idx + 1 < arguments.count ? arguments[idx + 1] : NSTemporaryDirectory()
    GlowPreview.run(directory: dir)
    exit(0)
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
