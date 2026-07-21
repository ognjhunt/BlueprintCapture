import SwiftUI

// MARK: - Rights & privacy training (NavBar + "Certified" proof chip)
//
// A real gated module: certification can only be confirmed after the
// acknowledgement is checked. Advisory copy stays honest; nothing is auto-granted.

struct BPRightsTrainingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var capturerState = BPCapturerStateStore.shared
    @State private var acknowledged = false
    private let principles = BPSample.principles

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar(title: "Rights & privacy") {
                if capturerState.isRightsCertified {
                    BPStatusChip("Certified", signal: .proof)
                } else {
                    BPStatusChip("Not certified", signal: .caution)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    intro
                    ForEach(principles) { principle in
                        principleCard(principle)
                    }
                    BPProofBoundary(
                        "Recertify yearly",
                        message: "This certification expires 12 months after you confirm it. When it lapses, your Home setup checklist will ask you to recertify here.",
                        signal: .info,
                        systemImage: "calendar"
                    )
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
        }
        .background(BP.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("How Blueprint captures stay trustworthy")
                .font(.bpSans(BPType.title, .semibold))
                .tracking(BPTracking.headline)
                .foregroundStyle(BP.textStrong)
            Text("Three principles govern every capture. Read each one, then confirm your certification.")
                .font(.bpSans(BPType.bodyS, .regular))
                .foregroundStyle(BP.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func principleCard(_ p: BPPrinciple) -> some View {
        BPCard {
            HStack(alignment: .top, spacing: Space.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(BP.proofBg)
                    Text("\(p.index)")
                        .font(.bpMono(BPType.body))
                        .foregroundStyle(BP.proofFg)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(p.title)
                        .font(.bpSans(BPType.bodyL, .semibold))
                        .foregroundStyle(BP.textStrong)
                    Text(p.body)
                        .font(.bpSans(BPType.bodyS, .regular))
                        .foregroundStyle(BP.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var acknowledgement: some View {
        Button {
            acknowledged.toggle()
        } label: {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: acknowledged ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(acknowledged ? BP.brassDeep : BP.lineStrong)
                Text("I understand these principles and will capture truthful, privacy-aware evidence with operator permission.")
                    .font(.bpSans(BPType.bodyS, .regular))
                    .foregroundStyle(BP.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        VStack(spacing: Space.m) {
            acknowledgement
            if let certifiedAt = capturerState.rightsCertifiedAt, capturerState.isRightsCertified {
                Text("Certified \(certifiedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            BPPrimaryButton(
                title: capturerState.isRightsCertified ? "Recertify" : "Confirm certification",
                enabled: acknowledged
            ) {
                capturerState.certifyRights()
                dismiss()
            }
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
    NavigationStack { BPRightsTrainingView() }
}
#endif
