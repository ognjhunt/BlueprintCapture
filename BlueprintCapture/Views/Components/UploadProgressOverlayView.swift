import SwiftUI

/// A floating overlay that shows upload progress and transitions to processing/completion states.
/// Designed to be non-intrusive while keeping users informed about their capture status.
struct UploadProgressOverlayView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel
    @State private var isExpanded = false
    @State private var showProcessingComplete = false

    /// The most recent active upload (uploading or just completed)
    private var activeUpload: CaptureFlowViewModel.UploadStatus? {
        // Prioritize uploads in progress, then recently completed
        viewModel.uploadStatuses.first { status in
            if case .uploading = status.state { return true }
            return false
        } ?? viewModel.uploadStatuses.first { status in
            if case .completed = status.state { return true }
            return false
        } ?? viewModel.uploadStatuses.first { status in
            if case .queued = status.state { return true }
            return false
        }
    }

    /// Whether to show the overlay at all
    private var shouldShowOverlay: Bool {
        guard let upload = activeUpload else { return false }
        switch upload.state {
        case .completed:
            // Keep showing for completed until dismissed
            return !showProcessingComplete || isExpanded
        case .queued, .uploading:
            return true
        case .failed:
            return true
        }
    }

    var body: some View {
        if shouldShowOverlay, let upload = activeUpload {
            VStack(spacing: 0) {
                Spacer()

                if isExpanded {
                    expandedView(upload: upload)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                } else {
                    compactView(upload: upload)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90) // Above tab bar
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
        }
    }

    // MARK: - Compact View (Pill)

    @ViewBuilder
    private func compactView(upload: CaptureFlowViewModel.UploadStatus) -> some View {
        Button {
            withAnimation { isExpanded = true }
        } label: {
            HStack(spacing: 12) {
                // Status icon
                statusIcon(for: upload.state)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24, height: 24)

                // Status text & progress
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle(for: upload.state))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    if case .uploading(let progress) = upload.state {
                        Text("\(Int(progress * 100))% complete")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                // Progress indicator or chevron
                if case .uploading(let progress) = upload.state {
                    CircularProgressView(progress: progress, size: 28)
                } else if case .completed = upload.state {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(BlueprintTheme.successGreen)
                } else {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color(.systemBackground).opacity(0.95))
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded View (Card)

    @ViewBuilder
    private func expandedView(upload: CaptureFlowViewModel.UploadStatus) -> some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 16)

            VStack(spacing: 20) {
                // Header with close button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headerTitle(for: upload.state))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        if let targetName = upload.targetName {
                            Text(targetName)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        } else if let targetId = upload.metadata.targetId {
                            Text("Location ID: \(targetId.prefix(8))...")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation { isExpanded = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                }

                // State-specific content
                stateContent(for: upload)

                // Action buttons
                actionButtons(for: upload)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        )
        .onTapGesture {
            // Prevent accidental collapse
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 50 {
                        withAnimation { isExpanded = false }
                    }
                }
        )
    }

    // MARK: - State Content

    @ViewBuilder
    private func stateContent(for upload: CaptureFlowViewModel.UploadStatus) -> some View {
        switch upload.state {
        case .queued:
            queuedContent()
        case .uploading(let progress):
            uploadingContent(progress: progress)
        case .completed:
            completedContent(for: upload)
        case .failed(let message):
            failedContent(message: message)
        }
    }

    @ViewBuilder
    private func queuedContent() -> some View {
        HStack(spacing: 16) {
            ProgressView()
                .tint(BlueprintTheme.brandTeal)

            Text("Preparing your capture for upload...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private func uploadingContent(progress: Double) -> some View {
        VStack(spacing: 16) {
            // Progress bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Uploading")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    Text("\(Int(progress * 100))%")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BlueprintTheme.brandTeal)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [BlueprintTheme.primary, BlueprintTheme.brandTeal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 8)
                            .animation(.easeOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 8)
            }

            // Info text
            Text("Keep the app open for fastest upload. You can browse other tabs while this completes.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private func completedContent(for upload: CaptureFlowViewModel.UploadStatus) -> some View {
        VStack(spacing: 16) {
            // Success animation
            ZStack {
                Circle()
                    .fill(BlueprintTheme.successGreen.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(BlueprintTheme.successGreen)
            }

            VStack(spacing: 8) {
                Text("Upload Complete!")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("We're now processing your capture and running quality checks.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            // Estimated earnings card
            estimatedEarningsCard(for: upload)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    @ViewBuilder
    private func estimatedEarningsCard(for upload: CaptureFlowViewModel.UploadStatus) -> some View {
        let payoutRange = upload.estimatedPayoutRange ?? 50...150

        VStack(spacing: 12) {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Estimated Payout")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                Text("$\(payoutRange.lowerBound) - $\(payoutRange.upperBound)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Based on quality")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Paid within 48 hours")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BlueprintTheme.primary.opacity(0.3), BlueprintTheme.brandTeal.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    @ViewBuilder
    private func failedContent(message: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(BlueprintTheme.errorRed)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Upload Failed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BlueprintTheme.errorRed.opacity(0.15))
        )
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private func actionButtons(for upload: CaptureFlowViewModel.UploadStatus) -> some View {
        switch upload.state {
        case .completed:
            Button {
                withAnimation {
                    viewModel.dismissUpload(id: upload.id)
                    isExpanded = false
                }
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(BlueprintTheme.successGreen)
                    )
            }

        case .failed:
            HStack(spacing: 12) {
                Button {
                    viewModel.retryUpload(id: upload.id)
                } label: {
                    Text("Retry")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(BlueprintTheme.primary)
                        )
                }

                Button {
                    withAnimation {
                        viewModel.dismissUpload(id: upload.id)
                        isExpanded = false
                    }
                } label: {
                    Text("Dismiss")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )
                }
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIcon(for state: CaptureFlowViewModel.UploadStatus.State) -> some View {
        switch state {
        case .queued:
            Image(systemName: "clock.fill")
                .foregroundStyle(BlueprintTheme.warningOrange)
        case .uploading:
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(BlueprintTheme.primary)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(BlueprintTheme.successGreen)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BlueprintTheme.errorRed)
        }
    }

    private func statusTitle(for state: CaptureFlowViewModel.UploadStatus.State) -> String {
        switch state {
        case .queued:
            return "Preparing upload..."
        case .uploading:
            return "Uploading capture"
        case .completed:
            return "Processing capture"
        case .failed:
            return "Upload failed"
        }
    }

    private func headerTitle(for state: CaptureFlowViewModel.UploadStatus.State) -> String {
        switch state {
        case .queued:
            return "Preparing Upload"
        case .uploading:
            return "Uploading Capture"
        case .completed:
            return "Processing Your Capture"
        case .failed:
            return "Upload Failed"
        }
    }
}

// MARK: - Circular Progress View

private struct CircularProgressView: View {
    let progress: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [BlueprintTheme.primary, BlueprintTheme.brandTeal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)

            Text("\(Int(progress * 100))")
                .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        // Mock view model would go here
        Text("Upload Progress Overlay Preview")
            .foregroundStyle(.white)
    }
}
