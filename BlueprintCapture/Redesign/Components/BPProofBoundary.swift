import SwiftUI

// MARK: - BPProofBoundary
//
// Left-accent callout that names a truth boundary honestly: low coverage,
// recertify yearly, upload-as-is. Signal-tinted, never alarmist decoration.

struct BPProofBoundary: View {
    let title: String
    var message: String? = nil
    var signal: BPSignal = .caution
    var systemImage: String? = nil

    init(_ title: String, message: String? = nil, signal: BPSignal = .caution, systemImage: String? = nil) {
        self.title = title
        self.message = message
        self.signal = signal
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(signal.fg)
                .frame(width: 3)
            HStack(alignment: .top, spacing: Space.m) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(signal.fg)
                        .padding(.top, 1)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.bpSans(BPType.bodyS, .semibold))
                        .foregroundStyle(BP.textStrong)
                    if let message {
                        Text(message)
                            .font(.bpSans(BPType.caption, .regular))
                            .foregroundStyle(BP.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.m)
        }
        .background(signal.bg)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(signal.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        BPProofBoundary("Coverage low — recapture or upload as-is",
                        message: "The far end of the aisle is under the depth threshold.",
                        signal: .caution, systemImage: "exclamationmark.triangle")
        BPProofBoundary("Recertify yearly",
                        message: "Your rights & privacy certification expires in 47 days.",
                        signal: .info, systemImage: "calendar")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .bpPaperBackground()
}
#endif
