import SwiftUI

/// Six split-flap cards, `HH MM SS`, no colons — groups are separated by a
/// wider gap only. Staggers a mechanical ripple right-to-left when several
/// places roll together.
struct FlipClockView: View {
    let digits: [Character]

    var body: some View {
        HStack(spacing: Theme.groupGap) {
            group(0)
            group(2)
            group(4)
        }
    }

    private func group(_ start: Int) -> some View {
        HStack(spacing: Theme.intraGroupGap) {
            ForEach(0..<2, id: \.self) { i in
                let index = start + i
                FlipDigitView(value: digits.indices.contains(index) ? digits[index] : "0")
            }
        }
    }
}
