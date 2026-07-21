import SwiftUI
import MapKit

// MARK: - BPNearbyMapView
//
// Spatial view of the live discovery feed. Every pin is a real `capture_jobs`
// item from `ScanHomeViewModel` — the map never invents supply. Selecting a pin
// surfaces the job's honest state (payout, permission tier, distance) with a
// path into the full task detail.

struct BPNearbyMapView: View {
    @Environment(\.dismiss) private var dismiss

    let items: [ScanHomeViewModel.JobItem]
    var onSelect: (ScanHomeViewModel.JobItem) -> Void = { _ in }

    @State private var selectedItemId: String?
    @State private var position: MapCameraPosition = .automatic

    private var selectedItem: ScanHomeViewModel.JobItem? {
        items.first { $0.id == selectedItemId }
    }

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar(title: "Nearby map", showsBack: false) {
                BPTextAction(title: "Done") { dismiss() }
            }

            ZStack(alignment: .bottom) {
                map
                if let selectedItem {
                    selectionCard(selectedItem)
                        .padding(Space.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(BP.canvas.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var map: some View {
        Map(position: $position, selection: $selectedItemId) {
            UserAnnotation()
            ForEach(items) { item in
                Annotation(item.job.title, coordinate: CLLocationCoordinate2D(latitude: item.job.lat, longitude: item.job.lng)) {
                    pin(for: item)
                        .onTapGesture {
                            withAnimation(BPMotion.transition) { selectedItemId = item.id }
                        }
                }
                .tag(item.id)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    private func pin(for item: ScanHomeViewModel.JobItem) -> some View {
        let isSelected = item.id == selectedItemId
        return ZStack {
            Circle()
                .fill(isSelected ? BP.ink : BP.brass)
            Circle()
                .strokeBorder(isSelected ? BP.brass : BP.brassDeep.opacity(0.5), lineWidth: 1.5)
            Image(systemName: "camera.aperture")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? BP.brass : BP.ink)
        }
        .frame(width: isSelected ? 36 : 30, height: isSelected ? 36 : 30)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .accessibilityLabel("\(item.job.title), \(item.payoutLabel), \(item.distanceLabel)")
    }

    private func selectionCard(_ item: ScanHomeViewModel.JobItem) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.job.title)
                        .font(.bpSans(BPType.bodyL, .semibold))
                        .foregroundStyle(BP.textStrong)
                        .lineLimit(1)
                    Text([item.job.category ?? item.job.address, item.distanceLabel].joined(separator: "  ·  "))
                        .font(.bpMono(BPType.caption))
                        .foregroundStyle(BP.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.m)
                VStack(alignment: .trailing, spacing: Space.s) {
                    Text(item.payoutLabel)
                        .font(.bpMono(BPType.body))
                        .foregroundStyle(BP.textStrong)
                    BPStatusChip(item.permissionTier.shortLabel, signal: BPSignalMapping.signal(for: item.permissionTier))
                }
            }

            BPPrimaryButton(title: "View task", systemImage: "arrow.right") {
                dismiss()
                onSelect(item)
            }
        }
        .padding(Space.l)
        .bpCard()
    }
}
