import SwiftUI

/// Card root: proportional canvas (flip clock + countdown) + alert flash +
/// 凝光 edge ring + right-click menu. The Liquid Glass material itself lives at
/// the AppKit layer (NSGlassEffectView), so the SwiftUI layer stays clear here.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if model.glassMode == .solid {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .fill(Color(nsColor: .windowBackgroundColor))
                }

                content
                    .scaleEffect(scale(in: geo.size), anchor: .center)

                FlashOverlayView(alert: model.alert, pulseToken: model.pulseToken,
                                 windowSize: geo.size)

                rimRing
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .contextMenu {
            ContextMenuContent()
        }
    }

    private var content: some View {
        VStack(spacing: Theme.countdownSpacing) {
            FlipClockView(digits: model.digitChars)
            CountdownView(text: model.countdownText, alert: model.alert)
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
    }

    /// Uniform fit: content scales proportionally inside any window aspect.
    private func scale(in size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(size.width / Theme.canvasSize.width, size.height / Theme.canvasSize.height)
    }

    /// 凝光 edge highlight: dark outer ring + uniform specular inner rim —
    /// constant brightness the whole way around (a gradient here used to make
    /// the top/bottom edges glow several times brighter than the sides).
    private var rimRing: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Color.black.opacity(Theme.idleRingOpacity(colorScheme)), lineWidth: 2)
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Color.white.opacity(0.30), lineWidth: 1.2)
        }
    }
}
