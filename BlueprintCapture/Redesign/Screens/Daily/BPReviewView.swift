import SwiftUI

// MARK: - Bundle review & QA (paper, NavBar "Review capture")

struct BPReviewView: View {
    var onUpload: () -> Void
    var onRecapture: () -> Void

    private let gates = BPSample.qaGates
    private let manifest = BPSample.manifest

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar(title: "Review capture") {
                BPStatusChip("1 to review", signal: .caution)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    gatesSection
                    BPManifestCard(eyebrow: "Manifest", rows: manifest)
                    BPProofBoundary(
                        "Coverage low — recapture or upload as-is",
                        message: "The far end of the aisle is below the depth threshold. You can recapture it now or upload this bundle as-is; QA will flag the gap.",
                        signal: .caution,
                        systemImage: "exclamationmark.triangle"
                    )
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(BP.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var gatesSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("QA gates")
                .font(.bpSans(BPType.title, .semibold))
                .tracking(BPTracking.headline)
                .foregroundStyle(BP.textStrong)
            BPCard {
                ForEach(Array(gates.enumerated()), id: \.element.id) { idx, gate in
                    HStack(alignment: .center, spacing: Space.m) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(gate.title)
                                .font(.bpSans(BPType.body, .semibold))
                                .foregroundStyle(BP.textStrong)
                            Text(gate.sub)
                                .font(.bpSans(BPType.caption, .regular))
                                .foregroundStyle(BP.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Space.s)
                        BPStatusChip(gate.status.label, signal: gate.status.signal)
                    }
                    if idx < gates.count - 1 { BPDivider(color: BP.lineSoft) }
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Space.s) {
            BPPrimaryButton(title: "Upload bundle", action: onUpload)
            BPGhostButton(title: "Recapture far end", action: onRecapture)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
        .background(
            BP.canvas
                .overlay(alignment: .top) { BPDivider(color: BP.line) }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BPReviewView(onUpload: {}, onRecapture: {})
    }
}
#endif
