import SwiftUI

// MARK: - BPDataField
//
// Mono key / value row — the manifest line. Both sides mono so IDs, counts,
// checksums and sizes line up like a readout.

struct BPDataField: View {
    let key: String
    let value: String
    var valueColor: Color = BP.textStrong
    var valueSignal: BPSignal? = nil

    init(_ key: String, _ value: String, valueColor: Color = BP.textStrong, valueSignal: BPSignal? = nil) {
        self.key = key
        self.value = value
        self.valueColor = valueColor
        self.valueSignal = valueSignal
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(key)
                .font(.bpMono(BPType.caption))
                .foregroundStyle(BP.textMuted)
            Spacer(minLength: Space.m)
            Text(value)
                .font(.bpMono(BPType.caption))
                .foregroundStyle(valueSignal?.fg ?? valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A manifest: a card of mono key/value rows under an optional eyebrow.
struct BPManifestCard: View {
    var eyebrow: String? = nil
    let rows: [(String, String)]

    var body: some View {
        BPCard {
            if let eyebrow {
                BPEyebrow(eyebrow)
            }
            VStack(spacing: Space.s) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    BPDataField(row.0, row.1)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    BPManifestCard(eyebrow: "Manifest", rows: [
        ("capture_id", "CX-4821-A"),
        ("walkthrough", "WT-0093"),
        ("frames", "1,284"),
        ("meshes", "37")
    ])
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .bpPaperBackground()
}
#endif
