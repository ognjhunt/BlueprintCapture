import SwiftUI

// MARK: - BPProgressRing
//
// Brass progress ring with a mono value inside. Two circles: a sunken track and a
// brass trimmed arc rotated to start at 12 o'clock.

struct BPProgressRing: View {
    var progress: Double            // 0...1
    var lineWidth: CGFloat = 10
    var size: CGFloat = 180
    var centerTop: String           // e.g. "68%"
    var centerBottom: String        // e.g. "1.8 / 2.6 GB"

    var body: some View {
        ZStack {
            Circle()
                .stroke(BP.sunken, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(BP.brass, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(BPMotion.ring, value: progress)
            VStack(spacing: 4) {
                Text(centerTop)
                    .font(.bpMono(34))
                    .foregroundStyle(BP.textStrong)
                Text(centerBottom)
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
            }
        }
        .frame(width: size, height: size)
    }
}
