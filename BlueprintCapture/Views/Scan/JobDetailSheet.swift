import SwiftUI
import CoreLocation

struct JobDetailSheet: View {
    let item: ScanHomeViewModel.JobItem
    let userLocation: CLLocation?
    let onStartScan: () -> Void
    let onDirections: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var isOnSite: Bool {
        if AppConfig.allowOffsiteCheckIn() { return true }
        guard let userLocation else { return false }
        return item.distanceMeters <= Double(item.job.checkinRadiusM)
    }

    private var venuePermission: VenuePermission? {
        // Treat jobs as "permissioned" if the backend provides any explicit policy info.
        let hasAny = !(item.job.allowedAreas.isEmpty && item.job.restrictedAreas.isEmpty) || item.job.permissionDocURL != nil
        guard hasAny else { return nil }
        return VenuePermission(
            id: UUID(),
            venueName: item.job.title,
            venueAddress: item.job.address,
            authorizedBy: "Blueprint",
            authorizedTitle: "Scan job",
            signedAt: item.job.updatedAt,
            validUntil: nil,
            captureAreas: item.job.allowedAreas,
            restrictions: item.job.restrictedAreas,
            documentURL: item.job.permissionDocURL
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    if !item.job.instructions.isEmpty {
                        sectionCard(title: "Instructions", icon: "list.bullet") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(item.job.instructions.prefix(5), id: \.self) { line in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("•")
                                            .foregroundStyle(.secondary)
                                        Text(line)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }

                    if !item.job.allowedAreas.isEmpty {
                        sectionCard(title: "Allowed Areas", icon: "checkmark.shield.fill") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(item.job.allowedAreas, id: \.self) { area in
                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(BlueprintTheme.successGreen)
                                        Text(area)
                                    }
                                }
                            }
                        }
                    }

                    if !item.job.restrictedAreas.isEmpty {
                        sectionCard(title: "Restricted Areas", icon: "nosign") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(item.job.restrictedAreas, id: \.self) { area in
                                    HStack(spacing: 10) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(BlueprintTheme.errorRed)
                                        Text(area)
                                    }
                                }
                            }
                        }
                    }

                    actions
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Scan Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .blueprintAppBackground()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.job.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(item.job.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VenuePermissionBadge(permission: venuePermission)
            }

            HStack(spacing: 12) {
                Label("\(item.job.estMinutes) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("$\(item.job.payoutDollars)", systemImage: "dollarsign.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.successGreen)

                Label("\(String(format: "%.1f", item.distanceMiles)) mi", systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let badge = item.statusBadge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.systemFill)))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func sectionCard(title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if !isOnSite {
                Button {
                    onDirections()
                } label: {
                    Text("Directions")
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())

                Text("Move closer to start scanning (within \(item.job.checkinRadiusM)m).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Button {
                    onStartScan()
                    dismiss()
                } label: {
                    Text("Start Scan")
                }
                .buttonStyle(BlueprintSuccessButtonStyle())
            }
        }
    }
}

