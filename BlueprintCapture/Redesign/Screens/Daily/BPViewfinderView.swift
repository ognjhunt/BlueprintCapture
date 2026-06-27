import SwiftUI
import Combine

// MARK: - Capture flow container
//
// The viewfinder cover: a self-contained NavigationStack running
// Viewfinder → Bundle review → Upload. The viewfinder is dark; review and upload
// are paper (each screen sets its own color scheme).

enum CaptureStep: Hashable { case review, upload }

struct BPCaptureFlow: View {
    let task: BPCaptureTask?
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @State private var path: [CaptureStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            BPViewfinderView(
                task: task,
                onCancel: { coordinator.finishCapture() },
                onStop: { path.append(.review) }
            )
            .navigationDestination(for: CaptureStep.self) { step in
                switch step {
                case .review:
                    BPReviewView(
                        onUpload: { path.append(.upload) },
                        onRecapture: { path.removeAll() }
                    )
                case .upload:
                    BPUploadView(onFinish: { coordinator.finishCapture() })
                }
            }
        }
    }
}

// MARK: - Live viewfinder (dark)

struct BPViewfinderView: View {
    let task: BPCaptureTask?
    var onCancel: () -> Void
    var onStop: () -> Void

    @State private var elapsed: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            BPCameraPreview()
                .ignoresSafeArea()
                .background(BP.viewfinder.ignoresSafeArea())

            // Legibility gradients top/bottom.
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear, .clear, Color.black.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            BPRegistrationCorners(color: BP.brass, length: 28, thickness: 2, inset: 26)
                .padding(28)

            VStack(spacing: 0) {
                statusRow
                Spacer()
                reticle
                Spacer()
                sensorStrip
                    .padding(.bottom, Space.l)
                controls
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.l)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onReceive(ticker) { _ in elapsed += 1 }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                blink = 0.2
            }
        }
    }

    // MARK: Status row

    private var statusRow: some View {
        HStack(spacing: Space.s) {
            darkPill {
                HStack(spacing: 6) {
                    Circle().fill(BP.blockFg).frame(width: 7, height: 7)
                        .opacity(reduceMotion ? 1 : blink)
                    Text("REC")
                        .font(.bpMono(BPType.micro))
                        .tracking(1)
                        .foregroundStyle(BP.onInk)
                }
            }
            if let task {
                darkPill {
                    Text(task.title)
                        .font(.bpSans(BPType.caption, .semibold))
                        .foregroundStyle(BP.onInk)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BP.onInk)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
        }
    }

    @State private var blink = 1.0
    private var reticle: some View {
        VStack(spacing: Space.m) {
            ZStack {
                Circle()
                    .strokeBorder(BP.onInk.opacity(0.5), lineWidth: 1)
                    .frame(width: 74, height: 74)
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(BP.onInk.opacity(0.8))
            }
            Text("Hold steady · pan left")
                .font(.bpSans(BPType.bodyS, .medium))
                .foregroundStyle(BP.onInk.opacity(0.92))
                .padding(.horizontal, Space.m)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.35)))
        }
    }

    // MARK: Sensor readouts

    private var sensorStrip: some View {
        HStack(spacing: Space.s) {
            sensorTile("DEPTH", "0.91", tint: BP.proofLit)
            sensorTile("POSES", "LOCK", tint: BP.proofLit)
            sensorTile("COVER", "62%", tint: BP.warnLit)
            sensorTile("DRIFT", "0.4°", tint: BP.onInk)
        }
    }

    private func sensorTile(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.bpMono(9))
                .tracking(1.4)
                .foregroundStyle(BP.onInk.opacity(0.6))
            Text(value)
                .font(.bpMono(BPType.body))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: Bottom controls

    private var controls: some View {
        HStack {
            Text(timeString)
                .font(.bpMono(BPType.bodyL))
                .foregroundStyle(BP.onInk)
                .frame(width: 72, alignment: .leading)

            Spacer()

            Button(action: onStop) {
                ZStack {
                    Circle().strokeBorder(BP.onInk.opacity(0.8), lineWidth: 3).frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(BP.blockFg)
                        .frame(width: 30, height: 30)
                }
            }
            .accessibilityLabel("Stop capture")

            Spacer()

            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(BP.onInk.opacity(0.8))
                )
                .frame(width: 72, alignment: .trailing)
        }
    }

    private var timeString: String {
        String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    // MARK: Dark pill helper

    private func darkPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Space.m)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(.ultraThinMaterial)
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

#if DEBUG
#Preview {
    BPViewfinderView(task: BPSample.captureTask, onCancel: {}, onStop: {})
}
#endif
