import SwiftUI
import CoreLocation

struct JobDetailSheet: View {
    let item: ScanHomeViewModel.JobItem
    let userLocation: CLLocation?
    let onStartCapture: () -> Void          // glasses path
    let onStartPhoneCapture: () -> Void     // ARKit / phone camera path
    let onSubmitForReview: () -> Void
    let onDirections: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var focusTip: String? = nil
    @State private var isLoadingTip = false
    @State private var showCapturePicker = false

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
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Full-bleed hero
                    heroBlock

                    // Content below hero
                    VStack(alignment: .leading, spacing: 0) {
                        // Category + title block
                        titleBlock
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 16)

                        // Payout boost banner (like Kled's "Contributing boosts rate" banner)
                        payoutBanner
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        // AI Focus Tip
                        if isLoadingTip || focusTip != nil {
                            aiFocusTipCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                        }

                        // Divider
                        Divider()
                            .background(Color(white: 0.15))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

                        // Description / What to capture
                        detailSection(title: "Description") {
                            Text(item.job.workflowStepsOrInstructions.first ?? "Capture the primary zone, access routes, and key reference points.")
                                .font(.subheadline)
                                .foregroundStyle(Color(white: 0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                        // Task Requirements
                        detailSection(title: "Capture Requirements") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(item.job.workflowStepsOrInstructions.dropFirst().prefix(4)), id: \.self) { line in
                                    requirementRow(line)
                                }
                                if item.job.workflowStepsOrInstructions.count <= 1 {
                                    requirementRow("Start with entry and egress routes.")
                                    requirementRow("Capture every benchmark and handoff point.")
                                    requirementRow("Avoid faces, screens, and private documents.")
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                        // Restrictions (if any)
                        if !restrictedAreas.isEmpty {
                            detailSection(title: "Off-limits areas") {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(restrictedAreas.prefix(4), id: \.self) { area in
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: "nosign")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.red.opacity(0.8))
                                                .frame(width: 18)
                                            Text(area)
                                                .font(.subheadline)
                                                .foregroundStyle(Color(white: 0.7))
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }

                        // Capture zone / CTA
                        captureZoneBlock
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
            }

            // Floating back button
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Task { await generateFocusTip() }
        }
        .confirmationDialog("How do you want to capture?", isPresented: $showCapturePicker, titleVisibility: .visible) {
            Button("📱  Use iPhone Camera") {
                dismiss()
                onStartPhoneCapture()
            }
            Button("🥽  Use Glasses") {
                dismiss()
                onStartCapture()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("iPhone uses ARKit + LiDAR. Glasses record hands-free.")
        }
    }

    @MainActor
    private func generateFocusTip() async {
        guard SpaceDraftGenerator.shared.isAvailable, focusTip == nil else { return }
        isLoadingTip = true
        let description = item.job.workflowStepsOrInstructions.first ?? ""
        let requirements = Array(item.job.workflowStepsOrInstructions.dropFirst())
        let result = await SpaceDraftGenerator.shared.streamFocusTip(
            jobTitle: item.job.title,
            description: description,
            requirements: requirements,
            restrictedAreas: restrictedAreas
        ) { partial in
            Task { @MainActor in self.focusTip = partial }
        }
        if let r = result { focusTip = r }
        isLoadingTip = false
    }

    // MARK: - AI Focus Tip Card

    private var aiFocusTipCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(BlueprintTheme.brandTeal)
                .frame(width: 3)
                .cornerRadius(2)

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.brandTeal)
                    .frame(width: 22)

                if isLoadingTip && focusTip == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(Color(white: 0.5))
                        Text("Generating focus tip…")
                            .font(.subheadline)
                            .foregroundStyle(Color(white: 0.45))
                    }
                } else {
                    Text(focusTip ?? "")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(white: 0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BlueprintTheme.brandTeal.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Hero Block

    private var heroBlock: some View {
        ZStack(alignment: .bottomLeading) {
            CapturePreviewView(coordinate: item.job.coordinate, remoteImageURL: item.previewURL)
            .frame(height: 320)
            .clipped()

            // Bottom fade
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black],
                startPoint: .init(x: 0.5, y: 0.4),
                endPoint: .bottom
            )
        }
        .frame(height: 320)
    }
    // MARK: - Title Block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cat = item.job.category {
                Text(cat.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(white: 0.5))
                    .tracking(1.2)
            }

            Text(item.job.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            HStack(spacing: 14) {
                Label(item.job.address, systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.5))
                    .lineLimit(1)
            }

            HStack(spacing: 14) {
                metricChip(item.payoutLabel, icon: "dollarsign.circle.fill", color: BlueprintTheme.successGreen)
                metricChip(item.distanceLabel, icon: "location", color: item.isReadyNow ? BlueprintTheme.brandTeal : Color(white: 0.45))
                metricChip("\(item.job.estMinutes) min", icon: "clock", color: Color(white: 0.45))
            }
        }
    }

    // MARK: - Payout Banner (Kled "Contributing boosts your payout rate" style)

    private var payoutBanner: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(BlueprintTheme.successGreen)
                .frame(width: 3)
                .cornerRadius(2)

            HStack(spacing: 10) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(BlueprintTheme.successGreen)
                    .font(.subheadline)

                Text("Completing this capture earns \(item.payoutLabel).")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(white: 0.85))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BlueprintTheme.successGreen.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Capture Zone Block

    private var captureZoneBlock: some View {
        VStack(spacing: 16) {
            // Dashed capture zone (like Kled's upload area)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        Color(white: 0.2),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .frame(height: 110)

                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                        .foregroundStyle(Color(white: 0.35))
                    Text("Capture Content to Upload")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(white: 0.4))
                    Text("All captures are reviewed. Only submit content that matches the requirements.")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.3))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }

            // Primary action button
            actionButton

            // Disclaimer
            if !isOnSite && item.permissionTier != .blocked {
                Text("Move within \(item.job.checkinRadiusM)m of the address to start an approved capture.")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.35))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if item.permissionTier == .blocked {
                Text("This location is restricted. Do not capture it.")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        Button(actionTitle, action: primaryAction)
            .font(.headline)
            .foregroundStyle(actionTextColor)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(actionBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(item.permissionTier == .blocked)
            .accessibilityIdentifier("job-detail-primary-action")
    }

    private var actionTitle: String {
        if !isOnSite { return "Get Directions" }
        switch item.permissionTier {
        case .approved: return "Start Capture"
        case .reviewRequired: return "Submit for Review"
        case .permissionRequired: return "Check Access First"
        case .blocked: return "Not Allowed"
        }
    }

    private var actionBackgroundColor: Color {
        if item.permissionTier == .blocked { return Color(white: 0.12) }
        if !isOnSite { return Color(white: 0.14) }
        switch item.permissionTier {
        case .approved: return BlueprintTheme.successGreen
        case .reviewRequired: return BlueprintTheme.brandTeal.opacity(0.85)
        case .permissionRequired: return Color(white: 0.14)
        case .blocked: return Color(white: 0.12)
        }
    }

    private var actionTextColor: Color {
        item.permissionTier == .blocked ? Color(white: 0.3) : .white
    }

    private func primaryAction() {
        if !isOnSite {
            onDirections()
            dismiss()
            return
        }
        switch item.permissionTier {
        case .approved:
            // Ask the user whether to use iPhone camera or glasses before routing.
            showCapturePicker = true
        case .reviewRequired:
            onSubmitForReview()
            dismiss()
        case .permissionRequired, .blocked:
            return
        }
    }

    // MARK: - Subviews

    private func detailSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requirementRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(white: 0.3))
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricChip(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .foregroundStyle(Color(white: 0.7))
        }
        .font(.caption.weight(.semibold))
    }
}
