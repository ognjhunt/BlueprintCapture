import SwiftUI
import AVFoundation

// MARK: - Main view

@MainActor
struct CaptureTutorialView: View {
    let onContinue: () -> Void

    @State private var currentStep = 0
    /// 0 = walkthrough (portrait 720×1296), 1 = interior (landscape 3840×2160)
    @State private var videoVariant = 0

    private let steps: [TutorialStep] = [
        TutorialStep(
            icon: "iphone.gen3",
            title: "Hold your phone upright",
            detail: "Walk naturally with your phone in front of you, like you're taking a video."
        ),
        TutorialStep(
            icon: "figure.walk",
            title: "Move slowly and steadily",
            detail: "Cover all areas of the space. Walk at a calm, even pace for the best results."
        ),
        TutorialStep(
            icon: "lightbulb.fill",
            title: "Good lighting helps",
            detail: "Well-lit spaces produce higher quality captures and bigger payouts."
        ),
        TutorialStep(
            icon: "clock.fill",
            title: "15–30 minutes",
            detail: "A complete capture takes 15–30 minutes. Longer, thorough captures earn more."
        ),
    ]

    var body: some View {
        ZStack {
            // ── Background video ──────────────────────────────────────────
            TutorialVideoBackground(variant: videoVariant)

            // Dark scrim so text stays readable over any video
            LinearGradient(
                colors: [Color.black.opacity(0.35), Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // ── Foreground ───────────────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()

                // Swipeable step cards
                TabView(selection: $currentStep) {
                    ForEach(steps.indices, id: \.self) { index in
                        TutorialStepCard(step: steps[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 280)

                Spacer()

                // Dot indicators (tappable to jump)
                HStack(spacing: 10) {
                    ForEach(steps.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == currentStep ? Color.white : Color.white.opacity(0.3))
                            .frame(width: index == currentStep ? 20 : 8, height: 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentStep)
                            .onTapGesture { withAnimation { currentStep = index } }
                    }
                }
                .padding(.bottom, 28)

                // Action buttons
                VStack(spacing: 12) {
                    if currentStep < steps.count - 1 {
                        Button("Next") {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(BlueprintPrimaryButtonStyle())

                        Button("Skip Tutorial", action: onContinue)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.55))
                    } else {
                        Button("Got It", action: onContinue)
                            .buttonStyle(BlueprintPrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }

            // ── A/B toggle badge (top-right) ─────────────────────────────
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            videoVariant = videoVariant == 0 ? 1 : 0
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(videoVariant == 0 ? "A" : "B")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                            Text(videoVariant == 0 ? "Walkthrough" : "Interior")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                    }
                    .padding(.top, 56)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Step card

private struct TutorialStepCard: View {
    let step: TutorialStep

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: step.icon)
                .font(.system(size: 64))
                .foregroundStyle(BlueprintTheme.brandTeal)
                .frame(height: 80)
                .shadow(color: BlueprintTheme.brandTeal.opacity(0.5), radius: 16)

            Text(step.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(step.detail)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Video background

/// Plays a looping muted video behind the tutorial.
/// - Variant 0: `tutorial_bg_walkthrough.mp4` — portrait 720×1296, man walking (A)
/// - Variant 1: `tutorial_bg_interior.mp4`    — landscape 3840×2160, house pan (B)
///
/// Both files live at BlueprintCapture/Resources/Videos/ and must be added to the
/// Xcode target (drag in, tick "Add to targets"). `.resizeAspectFill` crops the
/// landscape clip to fill the portrait screen naturally.
///
/// The `.id(url)` modifier forces SwiftUI to tear down and recreate the player
/// whenever the variant (and thus URL) changes.
private struct TutorialVideoBackground: View {
    let variant: Int

    private var videoURL: URL? {
        let name = variant == 0 ? "tutorial_bg_walkthrough" : "tutorial_bg_interior"
        return Bundle.main.url(forResource: name, withExtension: "mp4")
    }

    var body: some View {
        if let url = videoURL {
            LoopingVideoPlayer(url: url)
                .id(url)          // recreate player when variant switches
                .ignoresSafeArea()
        } else {
            // Fallback: animated dark gradient until video is added to Xcode target
            ZStack {
                Color.black.ignoresSafeArea()
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    LinearGradient(
                        colors: [
                            Color(hue: 0.52, saturation: 0.4, brightness: 0.08 + 0.04 * sin(t * 0.4)),
                            Color.black,
                            Color(hue: 0.52, saturation: 0.3, brightness: 0.06 + 0.03 * cos(t * 0.3)),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }
}

// MARK: - UIKit looping player

private struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}
}

final class LoopingPlayerUIView: UIView {
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func configure(url: URL) {
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let player = AVQueuePlayer()
        playerLooper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill   // crops landscape clip to fill portrait screen
        layer.frame = bounds
        self.layer.insertSublayer(layer, at: 0)
        playerLayer = layer

        player.isMuted = true
        player.play()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resumePlayback),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func resumePlayback() { queuePlayer?.play() }

    deinit {
        NotificationCenter.default.removeObserver(self)
        queuePlayer?.pause()
    }
}

// MARK: - Model

private struct TutorialStep {
    let icon: String
    let title: String
    let detail: String
}

// MARK: - Preview

#Preview {
    CaptureTutorialView { }
        .preferredColorScheme(.dark)
}
