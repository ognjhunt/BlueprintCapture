import SwiftUI

struct PostCaptureSummaryView: View {
    let duration: TimeInterval
    let estimatedDataSizeMB: Double
    let spaceTitle: String
    let spaceAddress: String?
    let actionState: CaptureFlowViewModel.FinishedCaptureActionState
    let workflowReview: SiteWorldPassReview?
    let onContinueWorkflow: (() -> Void)?
    let onUploadNow: () -> Void
    let onUploadLater: () -> Void
    let onExport: () -> Void
    @Binding var userNotes: String

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── Hero ──────────────────────────────────────────────
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(BlueprintTheme.textPrimary)
                            .padding(.top, 48)

                        Text(spaceTitle.isEmpty ? "Capture complete" : spaceTitle)
                            .font(BlueprintTheme.display(32, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textPrimary)
                            .multilineTextAlignment(.center)

                        if let address = spaceAddress, !address.isEmpty {
                            Text(address)
                                .font(BlueprintTheme.body(14, weight: .medium))
                                .foregroundStyle(BlueprintTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)

                    // ── Summary card ──────────────────────────────────────
                    VStack(spacing: 0) {
                        summaryRow(label: "Duration", value: formattedDuration)
                        Divider().background(Color(white: 0.15))
                        summaryRow(label: "Size", value: formattedDataSize)
                    }
                    .blueprintEditorialCard(radius: 16, fill: BlueprintTheme.panel)
                    .padding(.horizontal, 20)

                    if let workflowReview {
                        workflowReviewCard(workflowReview)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }

                    // ── Notes ─────────────────────────────────────────────
                    TextField("Add a note (optional)", text: $userNotes, axis: .vertical)
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                        .tint(Color.white)
                        .lineLimit(2...4)
                        .padding(14)
                        .blueprintEditorialCard(radius: 16, fill: BlueprintTheme.panel)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    if let statusMessage {
                        HStack(spacing: 10) {
                            if isBusy {
                                ProgressView()
                                    .tint(Color.white)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(BlueprintTheme.textPrimary)
                            }

                            Text(statusMessage)
                                .font(BlueprintTheme.body(14, weight: .medium))
                                .foregroundStyle(BlueprintTheme.textPrimary)

                            Spacer()
                        }
                        .padding(14)
                        .background(backgroundTone, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }

                    // ── CTAs ─────────────────────────────────────────────
                    VStack(spacing: 10) {
                        if let continueLabel = workflowReview?.nextActionLabel,
                           let onContinueWorkflow {
                            Button(action: onContinueWorkflow) {
                                HStack(spacing: 10) {
                                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(continueLabel)
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .disabled(isBusy)
                        }

                        // Primary — Upload
                        Button(action: onUploadNow) {
                            HStack(spacing: 10) {
                                if isPreparingUpload {
                                    ProgressView()
                                        .tint(.black)
                                }
                                Text(isPreparingUpload ? "Preparing upload…" : "Upload")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(.white.opacity(isBusy ? 0.75 : 1.0))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isBusy)
                        .accessibilityIdentifier("post-capture-upload")

                        // Secondary — Export / AirDrop
                        Button(action: onExport) {
                            HStack(spacing: 8) {
                                if isExporting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                Text(isExporting ? "Preparing export…" : "Export bundle")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(BlueprintTheme.panelStrong)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(BlueprintTheme.hairline, lineWidth: 1)
                            )
                        }
                        .disabled(isBusy)
                        .accessibilityIdentifier("post-capture-export")

                        // Tertiary — save for later
                        Button(action: onUploadLater) {
                            Text("Save for later")
                                .font(BlueprintTheme.body(14, weight: .semibold))
                                .foregroundStyle(BlueprintTheme.textSecondary)
                        }
                        .disabled(isBusy)
                        .accessibilityIdentifier("post-capture-save-later")
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 48)
                }
            }
        }
        .blueprintAppBackground()
    }

    // MARK: - Row helper

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(BlueprintTheme.body(14, weight: .medium))
                .foregroundStyle(BlueprintTheme.textSecondary)
            Spacer()
            Text(value)
                .font(BlueprintTheme.body(14, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func workflowReviewCard(_ review: SiteWorldPassReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(review.title)
                        .font(BlueprintTheme.body(15, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                    Text(review.summary)
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(review.tone.title)
                        .font(BlueprintTheme.body(12, weight: .semibold))
                        .foregroundStyle(reviewToneColor(review.tone))
                    Text("\(review.score)")
                        .font(BlueprintTheme.display(22, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                }
            }

            Text("Workflow progress \(review.completedRequiredPasses)/\(review.totalRequiredPasses)")
                .font(BlueprintTheme.body(12, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textSecondary)

            if !review.completedItems.isEmpty {
                workflowList(title: "Completed", items: review.completedItems, tint: Color(red: 0.2, green: 0.85, blue: 0.45))
            }

            if !review.missingItems.isEmpty {
                workflowList(title: "Still needed", items: review.missingItems, tint: Color(red: 0.95, green: 0.54, blue: 0.34))
            }

            if let weakSignalSummary = review.weakSignalSummary {
                Text(weakSignalSummary.replacingOccurrences(of: "weak_signal:", with: "Weak signal: "))
                    .font(BlueprintTheme.body(12, weight: .medium))
                    .foregroundStyle(BlueprintTheme.textSecondary)
            }
        }
        .padding(14)
        .blueprintEditorialCard(radius: 16, fill: BlueprintTheme.panel)
    }

    private func workflowList(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
        }
    }

    private func reviewToneColor(_ tone: SiteWorldReviewTone) -> Color {
        switch tone {
        case .ready:
            return Color(red: 0.2, green: 0.85, blue: 0.45)
        case .caution:
            return Color(red: 0.97, green: 0.75, blue: 0.28)
        case .actionRequired:
            return Color(red: 0.95, green: 0.54, blue: 0.34)
        }
    }

    // MARK: - Computed

    private var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var formattedDataSize: String {
        if estimatedDataSizeMB < 1.0 {
            return String(format: "%.0f KB", estimatedDataSizeMB * 1024)
        }
        if estimatedDataSizeMB < 1024 {
            return String(format: "%.1f MB", estimatedDataSizeMB)
        }
        return String(format: "%.1f GB", estimatedDataSizeMB / 1024)
    }

    private var isPreparingUpload: Bool {
        if case .generatingIntake = actionState { return true }
        return false
    }

    private var isExporting: Bool {
        if case .exporting = actionState { return true }
        return false
    }

    private var isBusy: Bool {
        isPreparingUpload || isExporting
    }

    private var statusMessage: String? {
        switch actionState {
        case .idle:
            return nil
        case .generatingIntake:
            return "Preparing your upload and returning you to the queue…"
        case .exporting:
            return "Finalizing the export bundle…"
        case .failed(let message):
            return message
        }
    }

    private var backgroundTone: Color {
        switch actionState {
        case .failed:
            return Color.red.opacity(0.12)
        default:
            return Color(white: 0.07)
        }
    }
}

#Preview {
    PostCaptureSummaryView(
        duration: 82,
        estimatedDataSizeMB: 103.9,
        spaceTitle: "Current Location",
        spaceAddress: "1005 Crete St, Durham",
        actionState: .idle,
        workflowReview: nil,
        onContinueWorkflow: nil,
        onUploadNow: {},
        onUploadLater: {},
        onExport: {},
        userNotes: .constant("")
    )
    .preferredColorScheme(.dark)
}
