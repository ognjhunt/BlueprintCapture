import SwiftUI

// MARK: - BPStatusChip
//
// Signal pill: signal bg fill + border + fg text, micro uppercase, square-ish.
// Optionally a leading filled dot (used for "REC", availability, etc.).

struct BPStatusChip: View {
    let label: String
    var signal: BPSignal = .neutral
    var showsDot: Bool = false
    var mono: Bool = false

    init(_ label: String, signal: BPSignal = .neutral, showsDot: Bool = false, mono: Bool = false) {
        self.label = label
        self.signal = signal
        self.showsDot = showsDot
        self.mono = mono
    }

    var body: some View {
        HStack(spacing: Space.xs + 2) {
            if showsDot {
                Circle()
                    .fill(signal.fg)
                    .frame(width: 6, height: 6)
            }
            Text(label)
                .font(mono ? .bpMono(BPType.micro) : .bpSans(BPType.micro, .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(signal.fg)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(signal.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(signal.border, lineWidth: 1)
        )
        .fixedSize()
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        BPStatusChip("Validated", signal: .proof)
        BPStatusChip("Recapture", signal: .caution)
        BPStatusChip("REC", signal: .blocker, showsDot: true)
        BPStatusChip("In review", signal: .info)
        BPStatusChip("Rights pending", signal: .caution)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .bpPaperBackground()
}
#endif
