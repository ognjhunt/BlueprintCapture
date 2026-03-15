import SwiftUI
import CoreLocation

struct JobDetailSheet: View {
    let item: ScanHomeViewModel.JobItem
    let userLocation: CLLocation?
    let onStartCapture: () -> Void
    let onSubmitForReview: () -> Void
    let onDirections: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var isOnSite: Bool {
        if AppConfig.allowOffsiteCheckIn() { return true }
        guard let userLocation else { return false }
        return item.distanceMeters <= Double(item.job.checkinRadiusM)
    }

    private var primaryChecklist: [String] {
        let base = item.job.rightsChecklist.isEmpty
            ? [
                "Stay in common or approved areas only.",
                "Keep faces, screens, and paperwork out of frame.",
                "Call out restricted zones before you begin."
            ]
            : item.job.rightsChecklist
        return Array(base.prefix(4))
    }

    private var restrictedAreas: [String] {
        let combined = item.job.inaccessibleAreasForCapture + item.job.privacyRestrictions + item.job.securityRestrictions
        return Array(NSOrderedSet(array: combined).array as? [String] ?? combined)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    scopeCard
                    restrictionsCard
                    reviewImpactCard
                    checklistCard
                    actionsCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Capture brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .blueprintAppBackground()
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            heroArtwork
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            LinearGradient(
                colors: [Color.black.opacity(0.1), Color.black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DetailPermissionBadge(tier: item.permissionTier)
                    Spacer()
                    if let availability = item.availabilityBadge {
                        Text(availability)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.job.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(item.job.address)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        detailMetric(item.payoutLabel, icon: "dollarsign.circle.fill")
                        detailMetric("\(item.job.estMinutes) min", icon: "clock")
                        detailMetric(item.distanceLabel, icon: "location")
                    }
                }
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var heroArtwork: some View {
        Group {
            if let url = item.previewURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_):
                        fallbackArtwork
                    case .empty:
                        fallbackArtwork.overlay(ProgressView().tint(BlueprintTheme.brandTeal))
                    @unknown default:
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
    }

    private var fallbackArtwork: some View {
        MapSnapshotView(coordinate: item.job.coordinate)
    }

    private var scopeCard: some View {
        sectionCard(title: "What to capture", icon: "scope") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(item.job.workflowStepsOrInstructions.prefix(5)), id: \.self) { line in
                    checklistRow(line, tone: .good)
                }
                if item.job.workflowStepsOrInstructions.isEmpty {
                    checklistRow("Capture the access route, primary zone, and the most important handoff or benchmark point.", tone: .good)
                }
            }
        }
    }

    private var restrictionsCard: some View {
        sectionCard(title: "Where not to capture", icon: "nosign") {
            VStack(alignment: .leading, spacing: 10) {
                if restrictedAreas.isEmpty {
                    checklistRow("No additional restrictions were attached. Stay in visible common areas and avoid private information.", tone: .warning)
                } else {
                    ForEach(restrictedAreas, id: \.self) { line in
                        checklistRow(line, tone: .warning)
                    }
                }
            }
        }
    }

    private var reviewImpactCard: some View {
        sectionCard(title: "Review and payout", icon: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.reviewNote)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    reviewCallout(title: "Expected review", value: reviewWindow)
                    reviewCallout(title: "Likely payout", value: item.payoutLabel)
                }
            }
        }
    }

    private var checklistCard: some View {
        sectionCard(title: "Before you begin", icon: "checklist") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(primaryChecklist, id: \.self) { line in
                    checklistRow(line, tone: .neutral)
                }
            }
        }
    }

    private var actionsCard: some View {
        VStack(spacing: 12) {
            actionButton

            if !isOnSite {
                Text("Move within \(item.job.checkinRadiusM)m of the address to start an approved capture from the exact location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if item.permissionTier == .permissionRequired || item.permissionTier == .blocked {
                Text(item.permissionTier == .blocked
                     ? "This capture is blocked. Do not record it."
                     : "Use care here: stay in public-facing areas, avoid restricted zones, and stop if staff objects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func checklistRow(_ text: String, tone: ChecklistTone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.icon)
                .foregroundStyle(tone.color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if !isOnSite {
            Button(actionTitle, action: primaryAction)
                .buttonStyle(BlueprintPrimaryButtonStyle())
        } else {
            switch item.permissionTier {
            case .approved:
                Button(actionTitle, action: primaryAction)
                    .buttonStyle(BlueprintSuccessButtonStyle())
            case .reviewRequired:
                Button(actionTitle, action: primaryAction)
                    .buttonStyle(BlueprintPrimaryButtonStyle())
            case .permissionRequired, .blocked:
                Button(actionTitle, action: {})
                    .buttonStyle(BlueprintSecondaryButtonStyle())
                    .disabled(true)
            }
        }
    }

    private func reviewCallout(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private func detailMetric(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.82))
    }

    private var reviewWindow: String {
        switch item.permissionTier {
        case .approved:
            return "Usually within 24h"
        case .reviewRequired:
            return "Reviewed before approval"
        case .permissionRequired:
            return "Depends on scope review"
        case .blocked:
            return "Unavailable"
        }
    }

    private var actionTitle: String {
        if !isOnSite {
            return "Get closer"
        }

        switch item.permissionTier {
        case .approved:
            return "Start capture"
        case .reviewRequired:
            return "Submit for review"
        case .permissionRequired:
            return "Check access first"
        case .blocked:
            return "Not allowed"
        }
    }

    private func primaryAction() {
        if !isOnSite {
            onDirections()
            dismiss()
            return
        }

        switch item.permissionTier {
        case .approved:
            onStartCapture()
        case .reviewRequired:
            onSubmitForReview()
        case .permissionRequired, .blocked:
            return
        }
        dismiss()
    }

    private enum ChecklistTone {
        case good
        case warning
        case neutral

        var color: Color {
            switch self {
            case .good:
                return BlueprintTheme.successGreen
            case .warning:
                return .orange
            case .neutral:
                return BlueprintTheme.brandTeal
            }
        }

        var icon: String {
            switch self {
            case .good:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .neutral:
                return "checkmark.seal.fill"
            }
        }
    }
}

private struct DetailPermissionBadge: View {
    let tier: ScanHomeViewModel.CapturePermissionTier

    var body: some View {
        Label(tier.label, systemImage: tier.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(0.16))
            )
    }

    private var color: Color {
        switch tier {
        case .approved:
            return BlueprintTheme.successGreen
        case .reviewRequired:
            return BlueprintTheme.brandTeal
        case .permissionRequired:
            return .orange
        case .blocked:
            return .red
        }
    }
}
