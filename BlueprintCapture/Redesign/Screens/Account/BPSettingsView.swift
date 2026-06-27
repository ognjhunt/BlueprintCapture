import SwiftUI

// MARK: - Settings (NavBar "Settings")

struct BPSettingsView: View {
    @State private var depthDefault = true
    @State private var autoUpload = true
    @State private var smartGlasses = false
    @State private var assignmentAlerts = true
    @State private var payoutUpdates = true
    @State private var qaRecapture = true
    @State private var preciseLocation = true
    @State private var faceBlur = true

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar("Settings")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    group("Capture") {
                        toggleRow("Depth sensor default", "Use LiDAR depth whenever the device supports it.", $depthDefault)
                        BPDivider(color: BP.lineSoft)
                        toggleRow("Auto-upload on Wi-Fi", "Sync finished bundles only on Wi-Fi.", $autoUpload)
                        BPDivider(color: BP.lineSoft)
                        toggleRow("Smart glasses", "Meta smart-glasses capture (approved).", $smartGlasses)
                    }
                    group("Alerts") {
                        toggleRow("Assignment alerts", "New assignments near you.", $assignmentAlerts)
                        BPDivider(color: BP.lineSoft)
                        toggleRow("Payout updates", "Payout sent and processing updates.", $payoutUpdates)
                        BPDivider(color: BP.lineSoft)
                        toggleRow("QA / recapture", "When a capture passes QA or needs recapture.", $qaRecapture)
                    }
                    group("Privacy") {
                        toggleRow("Precise location", "Anchor captures to the exact address.", $preciseLocation)
                        BPDivider(color: BP.lineSoft)
                        toggleRow("Face-blur preview", "Preview on-device face blur before upload.", $faceBlur)
                    }
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
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow(title)
            BPCard(padding: 0) { content() }
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                Text(subtitle)
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.m)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(BP.brass)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }
}

#if DEBUG
#Preview {
    NavigationStack { BPSettingsView() }
}
#endif
