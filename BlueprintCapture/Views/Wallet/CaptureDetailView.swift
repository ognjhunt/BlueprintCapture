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
        .navigationTitle("Capture Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .blueprintAppBackground()
        .task(id: entry.id) {
            await loadDetail()
        }
    }

    private var statusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.targetAddress)
                    .font(.headline)
                    .lineLimit(2)
                Text(entry.capturedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
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
            Label("Location", systemImage: "mappin.circle.fill")
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
            Label("Needs Fix", systemImage: "exclamationmark.triangle.fill")
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
            Label("Status Timeline", systemImage: "clock.fill")
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

    private var statusLabel: String {
        switch entry.status {
        case .processing: return "Processing"
        case .qc: return "In Review"
        case .approved: return "Approved"
        case .needsFix: return "Needs Fix"
        }
    }

    private var statusIcon: String {
        switch entry.status {
        case .processing: return "arrow.triangle.2.circlepath"
        case .qc: return "clock.fill"
        case .approved: return "checkmark.circle.fill"
        case .needsFix: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .processing: return .secondary
        case .qc: return BlueprintTheme.brandTeal
        case .approved: return BlueprintTheme.successGreen
        case .needsFix: return .red
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
