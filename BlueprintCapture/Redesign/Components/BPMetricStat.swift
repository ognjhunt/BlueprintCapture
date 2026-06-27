import SwiftUI

// MARK: - BPMetricStat
//
// Big mono number + small sans label. Used for the stat trios (Captures /
// Rating / Pass rate) and the earnings mini cards.

struct BPMetricStat: View {
    let value: String
    let label: String
    var valueColor: Color = BP.textStrong
    var framed: Bool = true
    var valueSize: CGFloat = 22

    init(value: String, label: String, valueColor: Color = BP.textStrong, framed: Bool = true, valueSize: CGFloat = 22) {
        self.value = value
        self.label = label
        self.valueColor = valueColor
        self.framed = framed
        self.valueSize = valueSize
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(value)
                .font(.bpMono(valueSize, true))
                .foregroundStyle(valueColor)
            Text(label)
                .bpEyebrow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        if framed {
            content
                .padding(Space.m)
                .bpCard()
        } else {
            content
        }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 12) {
        BPMetricStat(value: "27", label: "Captures")
        BPMetricStat(value: "4.9", label: "Rating")
        BPMetricStat(value: "98%", label: "Pass rate", valueColor: BP.proofFg)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .bpPaperBackground()
}
#endif
