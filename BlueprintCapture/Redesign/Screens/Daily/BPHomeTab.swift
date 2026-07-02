import SwiftUI

// MARK: - Home / assignments (tab: Home)

struct BPHomeTab: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator

    private let active = BPSample.activeAssignment
    private let nearby = BPSample.nearby

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    activeCard
                    nearbySection
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
            .background(BP.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
            .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
            .navigationDestination(for: BPAssignment.self) { assignment in
                BPTaskDetailView(task: assignment.asCaptureTask)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.xs) {
                BPEyebrow(coordinator.capturerCity, color: BP.brassDeep)
                Text("\(greeting), \(coordinator.capturerName)")
                    .font(.bpSans(BPType.largeTitle, .bold))
                    .tracking(BPTracking.headlineLarge)
                    .foregroundStyle(BP.textStrong)
            }
            Spacer(minLength: Space.m)
            NavigationLink {
                BPNotificationsView()
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BP.textStrong)
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(BP.blockFg).frame(width: 8, height: 8).offset(x: -10, y: 12)
                    }
                    .contentShape(Rectangle())
            }
            .offset(x: 8)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: Active assignment

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPFacilityImage(name: active.imageName, height: 156)
                .overlay(alignment: .topLeading) {
                    BPStatusChip(active.status.label, signal: active.status.signal)
                        .padding(Space.m)
                }

            HStack(alignment: .firstTextBaseline) {
                Text(active.site)
                    .font(.bpSans(BPType.bodyL, .semibold))
                    .foregroundStyle(BP.textStrong)
                Spacer(minLength: Space.m)
                if let payout = active.payout {
                    Text(BPFormat.currency(payout))
                        .font(.bpMono(BPType.bodyL))
                        .foregroundStyle(BP.textStrong)
                }
            }

            Text([active.task, active.aisle, active.distance].joined(separator: "  ·  "))
                .font(.bpMono(BPType.caption))
                .foregroundStyle(BP.textMuted)

            BPPrimaryButton(title: "Continue capture", systemImage: "camera.aperture") {
                coordinator.startCapture(task: active.asCaptureTask)
            }
            .padding(.top, Space.xs)
        }
        .padding(Space.l)
        .bpCard()
    }

    // MARK: Nearby

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nearby")
                    .font(.bpSans(BPType.title, .semibold))
                    .tracking(BPTracking.headline)
                    .foregroundStyle(BP.textStrong)
                Spacer()
                BPTextAction(title: "Map") {}
            }

            VStack(spacing: Space.m) {
                ForEach(nearby) { assignment in
                    NavigationLink(value: assignment) {
                        BPAssignmentRow(assignment: assignment)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Assignment row

struct BPAssignmentRow: View {
    let assignment: BPAssignment

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(assignment.site)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                    .lineLimit(1)
                Text([assignment.task, assignment.aisle, assignment.distance].joined(separator: "  ·  "))
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: Space.s) {
                if let payout = assignment.payout {
                    Text(BPFormat.currency(payout))
                        .font(.bpMono(BPType.body))
                        .foregroundStyle(BP.textStrong)
                } else {
                    // Rights pending: no payout shown — the boundary stays honest.
                    Text("—")
                        .font(.bpMono(BPType.body))
                        .foregroundStyle(BP.textFaint)
                }
                BPStatusChip(assignment.status.label, signal: assignment.status.signal)
            }
        }
        .padding(Space.l)
        .bpCard()
    }
}

// MARK: - Assignment → capture task

extension BPAssignment {
    var asCaptureTask: BPCaptureTask {
        BPCaptureTask(
            id: id,
            title: task,
            site: site,
            imageName: imageName,
            meta: [task, aisle, distance],
            requirements: BPSample.captureTask.requirements,
            estPayout: payout
        )
    }
}

#if DEBUG
#Preview {
    BPHomeTab().environmentObject(RedesignCoordinator())
}
#endif
