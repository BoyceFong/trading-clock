import AppKit
import SwiftUI

private func mark(_ s: String) {
    let line = "[ui-preview] \(s)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
}

/// Dev CLI (`--ui-preview`): renders the *actual* RootView UI (flip clock,
/// countdown, alert ring) composited over a mock candlestick chart, so the
/// README gets an honest picture of the widget floating over a trading
/// terminal. Everything except the mock chart is production view code.
enum UIPreview {
    @MainActor
    static func run(directory: String) {
        mark("start")
        let size = CGSize(width: 720, height: 300)

        let model = AppModel(glassMode: .glass)
        // 12:59:57 — three seconds to candle close: red alert + 0:03 count.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 22
        comps.hour = 12; comps.minute = 59; comps.second = 57
        let moment = Calendar.current.date(from: comps) ?? Date()
        model.apply(date: moment)

        let actions = AppActions()
        let root = RootView(previewAlertStrength: 1)
            .environment(model)
            .environment(actions)
            .environment(\.staticPreview, true)

        // Pre-rasterize every digit face BEFORE the outer render: a nested
        // ImageRenderer (FaceRaster) inside an active ImageRenderer pass can
        // recurse/deadlock. Cache hits during render are then pure lookups.
        mark("warming face cache…")
        for d in "0123456789" {
            _ = FaceRaster.image(digit: d, half: .top, size: Theme.digitSize)
            _ = FaceRaster.image(digit: d, half: .bottom, size: Theme.digitSize)
        }
        mark("face cache warm")

        mark("model ready")
        let renderer = ImageRenderer(content: root)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        mark("renderer created, rendering…")
        guard let uiImage = renderer.nsImage,
              let uiCG = uiImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("UIPreview: render failed")
            return
        }
        mark("UI rendered")

        let px = Int(size.width * 2)
        let py = Int(size.height * 2)
        guard let ctx = CGContext(
            data: nil, width: px, height: py, bitsPerComponent: 8,
            bytesPerRow: px * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

        ctx.scaleBy(x: 2, y: 2)
        let rect = CGRect(origin: .zero, size: size)

        // 1) Mock chart backdrop (the only non-production part).
        drawMockChart(ctx: ctx, rect: rect)

        // 2) Simulated glass: light blur of the chart clipped to the card.
        let chartSnap = ctx.makeImage()
        ctx.saveGState()
        let cardPath = CGPath(roundedRect: rect.insetBy(dx: 10, dy: 10),
                              cornerWidth: Theme.cornerRadius, cornerHeight: Theme.cornerRadius,
                              transform: nil)
        ctx.addPath(cardPath)
        ctx.clip()
        if let chart = chartSnap {
            let ci = CIImage(cgImage: chart)
            let blur = CIFilter(name: "CIGaussianBlur")
            blur?.setValue(ci, forKey: kCIInputImageKey)
            blur?.setValue(7, forKey: kCIInputRadiusKey)
            if let out = blur?.outputImage?.cropped(to: ci.extent),
               let blurred = CIContext(options: nil).createCGImage(out, from: ci.extent) {
                ctx.setAlpha(1)
                ctx.draw(blurred, in: rect)
                ctx.setAlpha(0.62)   // keep the chart mostly readable through the glass
                ctx.draw(chart, in: rect)
            }
        }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.10).cgColor)
        ctx.fill(rect)
        ctx.restoreGState()

        // 3) Production UI on top.
        ctx.draw(uiCG, in: rect)

        guard let outCG = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: outCG)
        rep.size = size
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("app-screenshot.png")
        try? png.write(to: url)
        print("Wrote \(url.path)")
    }

    /// Dark trading-terminal look: grid + a run of green/red candles.
    private static func drawMockChart(ctx: CGContext, rect: CGRect) {
        ctx.setFillColor(NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1).cgColor)
        ctx.fill(rect)

        // Grid.
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.05))
        ctx.setLineWidth(1)
        var x: CGFloat = 30
        while x < rect.width {
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: rect.height))
            x += 60
        }
        var y: CGFloat = 30
        while y < rect.height {
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: rect.width, y: y))
            y += 50
        }
        ctx.strokePath()

        // Deterministic candlestick run (open/close/high/low in unit space).
        let candles: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.62, 0.55, 0.66, 0.52), (0.55, 0.58, 0.61, 0.53), (0.58, 0.50, 0.60, 0.48),
            (0.50, 0.46, 0.52, 0.44), (0.46, 0.52, 0.55, 0.45), (0.52, 0.48, 0.54, 0.46),
            (0.48, 0.40, 0.49, 0.38), (0.40, 0.44, 0.47, 0.39), (0.44, 0.38, 0.45, 0.35),
            (0.38, 0.42, 0.44, 0.36), (0.42, 0.36, 0.43, 0.34), (0.36, 0.30, 0.38, 0.28),
        ]
        let step = rect.width / CGFloat(candles.count + 1)
        for (i, c) in candles.enumerated() {
            let cx = step * CGFloat(i + 1)
            let up = c.1 >= c.0
            let color = NSColor(srgbRed: up ? 0.18 : 0.85, green: up ? 0.72 : 0.25,
                                blue: up ? 0.45 : 0.30, alpha: 1).cgColor
            let h = { (v: CGFloat) in rect.height * (1 - v) } // unit → canvas y
            ctx.setStrokeColor(color)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: cx, y: h(c.2)))
            ctx.addLine(to: CGPoint(x: cx, y: h(c.3)))
            ctx.strokePath()
            let top = max(h(c.0), h(c.1))
            let bot = min(h(c.0), h(c.1))
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: cx - step * 0.22, y: top, width: step * 0.44, height: max(bot - top, 4)))
        }
    }
}
