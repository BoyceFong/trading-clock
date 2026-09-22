import AppKit

/// Dev CLI (`--glow-preview`): renders the flash glow into PNGs over black/
/// white quadrants and numerically verifies perimeter uniformity by sampling
/// the rasterized mask at equal edge distance on top / bottom / left / right /
/// rounded corner. Uses the exact production `EdgeGlowMask` code path.
enum GlowPreview {
    static func run(directory: String) {
        let profile = EdgeGlowMask.Profile()
        let landscape = CGSize(width: 726, height: 317)
        let portrait = CGSize(width: 340, height: 560)

        verifyUniformity(size: landscape, profile: profile)
        render(size: landscape, name: "glow_landscape.png", directory: directory, profile: profile)
        render(size: portrait, name: "glow_portrait.png", directory: directory, profile: profile)
    }

    // MARK: Uniformity proof

    private static func verifyUniformity(size: CGSize, profile: EdgeGlowMask.Profile) {
        let scale: CGFloat = 2
        let img = EdgeGlowMask.image(size: size, scale: scale, profile: profile)
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cg.dataProvider?.data as Data? else {
            print("UNIFORMITY: could not rasterize mask")
            return
        }
        let w = cg.width
        let t: Double = 10 // probe 10 pt inside the edge
        let r = profile.cornerRadius
        // Points at interior distance t: middle of each side + 45° into the
        // top-left rounded corner (radius r − t from the arc center).
        let c = r - (r - t) / 2.squareRoot()
        let probes: [(String, Double, Double)] = [
            ("top-mid", size.width / 2, t),
            ("bottom-mid", size.width / 2, size.height - t),
            ("left-mid", t, size.height / 2),
            ("right-mid", size.width - t, size.height / 2),
            ("corner-TL", c, c),
            ("corner-BR", size.width - c, size.height - c),
        ]
        print("Uniformity @ t=\(t)pt (alpha byte, expect equal):")
        var values: [UInt8] = []
        for (name, x, y) in probes {
            let px = min(max(Int(x * scale), 0), w - 1)
            let py = min(max(Int(y * scale), 0), cg.height - 1)
            let a = data[py * cg.bytesPerRow + px * 4 + 3]
            values.append(a)
            print("  \(name): \(a)")
        }
        if let mn = values.min(), let mx = values.max(), mx - mn <= 2 {
            print("UNIFORMITY: PASS (spread \(mx - mn) ≤ 2)")
        } else {
            print("UNIFORMITY: FAIL")
        }
    }

    // MARK: Visual preview over black/white quadrants

    private static func render(size: CGSize, name: String, directory: String, profile: EdgeGlowMask.Profile) {
        let scale: CGFloat = 2
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

        ctx.scaleBy(x: scale, y: scale)
        let rect = CGRect(origin: .zero, size: size)

        // Backdrop quadrants: judge the ring over pure black and pure white.
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: size.height / 2, width: size.width / 2, height: size.height / 2))
        ctx.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height / 2))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
        ctx.fill(CGRect(x: size.width / 2, y: size.height / 2, width: size.width / 2, height: size.height / 2))

        // Haze: color × mask alpha (production path: tint + mask).
        let mask = EdgeGlowMask.image(size: size, scale: scale, profile: profile)
        if let maskCG = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.saveGState()
            ctx.clip(to: rect, mask: maskCG)
            ctx.setFillColor(NSColor(srgbRed: 0.86, green: 0.24, blue: 0.20, alpha: 1).cgColor)
            ctx.fill(rect)
            ctx.restoreGState()
        }

        // Ring: colored body + white core (strokeBorder ≈ centered stroke on
        // the path inset by half the width).
        func ring(width: CGFloat, color: CGColor) {
            let inset = width / 2
            let r = max(profile.cornerRadius - inset, 0)
            let path = CGPath(
                roundedRect: rect.insetBy(dx: inset, dy: inset),
                cornerWidth: r, cornerHeight: r, transform: nil)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.addPath(path)
            ctx.strokePath()
        }
        ring(width: Theme.flashRingWidth,
             color: NSColor(srgbRed: 0.86, green: 0.24, blue: 0.20, alpha: 1).cgColor)
        ring(width: Theme.flashCoreWidth,
             color: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.7).cgColor)

        guard let cg = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = size
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try? png.write(to: url)
        print("Wrote \(url.path)")
    }
}
