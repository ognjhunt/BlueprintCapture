import SwiftUI

struct CaptureDetailView: View {
    private enum LoadState: Equatable {
        case loading
        case loaded(CaptureDetailResponse)
        case unavailable
        case failed(String)
    }

    let entry: CaptureHistoryEntry

    @State private var loadState: LoadState = .loading
    private let apiService = APIService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusHeader
                stageOverviewCard
                locationCard

                switch loadState {
                case .loading:
                    loadingCard
                case .unavailable:
                    unavailableCard(message: "Detailed quality and payout data is not available for this capture yet.")
                case .failed(let message):
                    unavailableCard(message: message)
                case .loaded(let detail):
                    if let quality = detail.quality {
                        qualityCard(quality)
                    }

                    if let earnings = detail.earnings,
                       let basePayoutCents = earnings.basePayoutCents {
                        EarningsBonusBreakdownView(
                            basePayoutCents: basePayoutCents,
                            deviceMultiplier: earnings.deviceMultiplier ?? 1.0,
                            bonuses: earnings.bonuses,
                            totalPayoutCents: earnings.totalPayoutCents
                        )
                    }

                    if let rejectionReason = detail.rejectionReason?.nilIfEmpty {
                        rejectionCard(reason: rejectionReason)
                    }

                    if !detail.timeline.isEmpty {
                        timelineCard(detail.timeline)
                    } else if !detail.hasRenderableDetail {
                        unavailableCard(message: "Detailed quality and payout data is not available for this capture yet.")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle("Submission")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .blueprintAppBackground()
        .task(id: entry.id) {
            await loadDetail()
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(statusHeadline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(statusSubheadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge
            }

            HStack(spacing: 12) {
                Label(entry.capturedAt.formatted(.dateTime.month().day()), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let payout = entry.estimatedPayout {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                        Text(payout, format: .currency(code: "USD"))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.successGreen)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var stageOverviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(stageLabel, systemImage: stageIcon)
                .font(.headline)
                .foregroundStyle(stageColor)

            Text(stageMessage)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let helper = stageHelper {
                Text(helper)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(stageColor.opacity(0.1))
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption)
            Text(statusLabel)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Capture location", systemImage: "mappin.circle.fill")
                .font(.headline)

            Text(entry.targetAddress)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(BlueprintTheme.brandTeal)
            Text("Loading capture details…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func unavailableCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Detail Unavailable", systemImage: "info.circle.fill")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func qualityCard(_ quality: CaptureQualityBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quality Score", systemImage: "chart.bar.fill")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                qualityMetric(label: "Coverage", value: quality.coverage)
                qualityMetric(label: "Steadiness", value: quality.steadiness)
                qualityMetric(label: "Completeness", value: quality.completeness)
                qualityMetric(label: "Depth Quality", value: quality.depthQuality)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func qualityMetric(label: String, value: Int?) -> some View {
        VStack(spacing: 4) {
            Text(value.map { "\($0)%" } ?? "N/A")
                .font(.title3.weight(.bold))
                .foregroundStyle(valueColor(value))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private func rejectionCard(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(entry.status == .needsRecapture || entry.status == .needsFix ? "Needs recapture" : "Review note", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.1))
        )
    }

    private func timelineCard(_ events: [CaptureTimelineEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Submission timeline", systemImage: "clock.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    timelineRow(event: event, isLast: index == events.count - 1)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func timelineRow(event: CaptureTimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(event.isCompleted ? BlueprintTheme.successGreen : Color(.tertiarySystemFill))
                    .frame(width: 12, height: 12)
                if !isLast {
                    Rectangle()
                        .fill(event.isCompleted ? BlueprintTheme.successGreen.opacity(0.3) : Color(.tertiarySystemFill))
                        .frame(width: 2, height: 24)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.label)
                    .font(.subheadline.weight(event.isCompleted ? .medium : .regular))
                    .foregroundStyle(event.isCompleted ? .primary : .secondary)
                if let completedAt = event.completedAt {
                    Text(completedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadDetail() async {
        loadState = .loading
        do {
            if let detail = try await apiService.fetchCaptureDetail(id: entry.id), detail.hasRenderableDetail {
                loadState = .loaded(detail)
            } else {
                loadState = .unavailable
            }
        } catch {
            loadState = .failed("Detailed quality and payout data could not be loaded right now.")
        }
    }

    private func valueColor(_ value: Int?) -> Color {
        guard let value else { return .secondary }
        switch value {
        case 85...:
            return BlueprintTheme.successGreen
        case 70...84:
            return .orange
        default:
            return .red
        }
    }

    private var statusHeadline: String {
        switch entry.status {
        case .draft, .readyToSubmit:
            return "Waiting to enter review"
        case .submitted, .underReview, .processing, .qc:
            return "Submission in review"
        case .approved:
            return "Approved capture"
        case .needsRecapture, .needsFix:
            return "Another pass is needed"
        case .rejected:
            return "Submission closed"
        case .paid:
            return "Paid out"
        }
    }

    private var statusSubheadline: String {
        switch entry.status {
        case .draft:
            return "The bundle exists locally but has not been submitted."
        case .readyToSubmit:
            return "Everything is prepared and waiting for upload."
        case .submitted, .underReview, .processing, .qc:
            return "Blueprint is checking quality, rights, and deployment readiness."
        case .approved:
            return "This submission passed review and is queued for payout or buyer delivery."
        case .needsRecapture, .needsFix:
            return "A clearer or more complete capture is required."
        case .rejected:
            return "The submission could not move forward in its current form."
        case .paid:
            return "The submission completed review and payout was issued."
        }
    }

    private var stageLabel: String {
        switch entry.status {
        case .paid:
            return "Paid"
        case .needsRecapture, .needsFix:
            return "Needs recapture"
        default:
            return "In review"
        }
    }

    private var stageMessage: String {
        switch entry.status {
        case .draft, .readyToSubmit:
            return "Upload this capture when you are ready to move it into review."
        case .submitted, .underReview, .processing, .qc:
            return "No action needed right now. We will update this timeline as review moves forward."
        case .approved:
            return "Approved captures stay visible here until payout or downstream buyer delivery finishes."
        case .needsRecapture, .needsFix:
            return "Use the review note below to guide the next pass before resubmitting."
        case .rejected:
            return "This submission is closed. Review notes explain why it stopped."
        case .paid:
            return "This submission is complete and its payout is recorded."
        }
    }

    private var stageHelper: String? {
        switch entry.status {
        case .approved:
            return "You do not need to resubmit unless a reviewer requests another pass."
        case .needsRecapture, .needsFix:
            return "Focus on stronger coverage, cleaner framing, and restricted-zone boundaries."
        case .paid:
            return "See Wallet for payout timing and ledger details."
        default:
            return nil
        }
    }

    private var stageIcon: String {
        switch entry.status {
        case .paid:
            return "banknote.fill"
        case .needsRecapture, .needsFix:
            return "arrow.clockwise.circle.fill"
        default:
            return "clock.badge.checkmark"
        }
    }

    private var stageColor: Color {
        switch entry.status {
        case .paid:
            return BlueprintTheme.successGreen
        case .needsRecapture, .needsFix, .rejected:
            return .orange
        default:
            return BlueprintTheme.brandTeal
        }
    }

    private var statusLabel: String {
        switch entry.status {
        case .draft: return "Draft"
        case .readyToSubmit: return "Ready to submit"
        case .submitted: return "Submitted"
        case .underReview: return "Under review"
        case .processing: return "Processing"
        case .qc: return "In Review"
        case .approved: return "Approved"
        case .needsRecapture: return "Needs recapture"
        case .needsFix: return "Needs Fix"
        case .rejected: return "Rejected"
        case .paid: return "Paid"
        }
    }

    private var statusIcon: String {
        switch entry.status {
        case .draft: return "doc.badge.plus"
        case .readyToSubmit: return "arrow.up.circle.fill"
        case .submitted: return "paperplane.fill"
        case .underReview: return "hourglass"
        case .processing: return "arrow.triangle.2.circlepath"
        case .qc: return "clock.fill"
        case .approved: return "checkmark.circle.fill"
        case .needsRecapture: return "arrow.clockwise.circle.fill"
        case .needsFix: return "xmark.circle.fill"
        case .rejected: return "slash.circle.fill"
        case .paid: return "banknote.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .draft: return .secondary
        case .readyToSubmit: return .orange
        case .submitted: return BlueprintTheme.brandTeal
        case .underReview: return BlueprintTheme.brandTeal
        case .processing: return .secondary
        case .qc: return BlueprintTheme.brandTeal
        case .approved: return BlueprintTheme.successGreen
        case .needsRecapture: return .orange
        case .needsFix: return .red
        case .rejected: return .red
        case .paid: return BlueprintTheme.successGreen
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
