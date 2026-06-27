import SwiftUI

// MARK: - Task detail & accept (NavBar "Task")

struct BPTaskDetailView: View {
    let task: BPCaptureTask
    @EnvironmentObject private var coordinator: RedesignCoordinator

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar("Task")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    pathHero
                    titleBlock
                    requirements
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
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    // MARK: Capture-path hero

    private var pathHero: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            BPFacilityImage(name: task.imageName, height: 200)
                .overlay { BPRegistrationCorners() }
                .overlay { capturePath }
            Text("Suggested capture path")
                .font(.bpMono(BPType.caption))
                .foregroundStyle(BP.textMuted)
        }
    }

    private var capturePath: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let start = CGPoint(x: w * 0.18, y: h * 0.74)
            let end = CGPoint(x: w * 0.82, y: h * 0.30)
            ZStack {
                Path { p in
                    p.move(to: start)
                    p.addCurve(
                        to: end,
                        control1: CGPoint(x: w * 0.30, y: h * 0.20),
                        control2: CGPoint(x: w * 0.60, y: h * 0.86)
                    )
                }
                .stroke(BP.brass, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))

                Circle().fill(BP.brass).frame(width: 11, height: 11).position(start)
                Image(systemName: "mappin")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BP.brassLit)
                    .position(end)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(task.title)
                .font(.bpSans(BPType.largeTitle, .bold))
                .tracking(BPTracking.headlineLarge)
                .foregroundStyle(BP.textStrong)
            Text(([task.site] + task.meta.dropFirst()).joined(separator: "  ·  "))
                .font(.bpMono(BPType.caption))
                .foregroundStyle(BP.textMuted)
        }
    }

    // MARK: Requirements

    private var requirements: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Requirements")
                .font(.bpSans(BPType.title, .semibold))
                .tracking(BPTracking.headline)
                .foregroundStyle(BP.textStrong)

            BPCard {
                ForEach(Array(task.requirements.enumerated()), id: \.element.id) { idx, req in
                    HStack(alignment: .top, spacing: Space.m) {
                        Circle()
                            .fill(req.signal.fg)
                            .frame(width: 9, height: 9)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(req.title)
                                .font(.bpSans(BPType.body, .semibold))
                                .foregroundStyle(BP.textStrong)
                            Text(req.detail)
                                .font(.bpSans(BPType.caption, .regular))
                                .foregroundStyle(BP.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    if idx < task.requirements.count - 1 {
                        BPDivider(color: BP.lineSoft)
                    }
                }
            }
        }
    }

    // MARK: Pinned bottom bar

    private var bottomBar: some View {
        HStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Est. payout")
                    .bpEyebrow()
                Text(BPFormat.currency(task.estPayout))
                    .font(.bpMono(BPType.title))
                    .foregroundStyle(BP.textStrong)
            }
            Spacer(minLength: Space.m)
            BPPrimaryButton(title: "Accept & start capture") {
                coordinator.startCapture(task: task)
            }
            .frame(maxWidth: 220)
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
        BPTaskDetailView(task: BPSample.captureTask)
            .environmentObject(RedesignCoordinator())
    }
}
#endif
