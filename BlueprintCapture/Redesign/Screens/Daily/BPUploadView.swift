import SwiftUI
import Combine

// MARK: - Upload / sync handoff (paper, NavBar "Upload")

struct BPUploadView: View {
    var onFinish: () -> Void

    private let totalGB = 2.6
    private let totalChunks = 271
    @State private var progress: Double = 0.62
    @State private var paused = false
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar("Upload")
            ScrollView {
                VStack(spacing: Space.xl) {
                    ringBlock
                    BPManifestCard(eyebrow: "Transfer", rows: manifestRows)
                    BPProofBoundary(
                        "Payout is released after QA",
                        message: "This bundle pays out once it passes quality review — not at upload. You'll get a notification when it clears.",
                        signal: .info,
                        systemImage: "checkmark.seal"
                    )
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(BP.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onReceive(ticker) { _ in
            guard !paused else { return }
            progress = min(0.99, progress + 0.015)
        }
    }

    private var ringBlock: some View {
        VStack(spacing: Space.l) {
            BPProgressRing(
                progress: progress,
                centerTop: "\(Int(progress * 100))%",
                centerBottom: String(format: "%.1f / %.1f GB", progress * totalGB, totalGB)
            )
            VStack(spacing: Space.s) {
                Text(paused ? "Upload paused" : "Syncing bundle")
                    .font(.bpSans(BPType.title, .semibold))
                    .tracking(BPTracking.headline)
                    .foregroundStyle(BP.textStrong)
                HStack(spacing: Space.s) {
                    BPStatusChip("Encrypted", signal: .proof)
                    BPStatusChip("Resumable", signal: .info)
                }
            }
        }
        .padding(.top, Space.s)
    }

    private var manifestRows: [(String, String)] {
        let chunksDone = Int(progress * Double(totalChunks))
        let etaSeconds = Int((1 - progress) * 120)
        return [
            ("upload_id", "UP-2207"),
            ("chunks", "\(chunksDone) / \(totalChunks)"),
            ("checksum", "sha256:9f3c…b1"),
            ("eta", String(format: "00:%02d", max(0, etaSeconds % 60)))
        ]
    }

    private var bottomBar: some View {
        HStack(spacing: Space.m) {
            BPGhostButton(title: paused ? "Resume" : "Pause") { paused.toggle() }
            BPPrimaryButton(title: "Run in background", action: onFinish)
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
        BPUploadView(onFinish: {})
    }
}
#endif
