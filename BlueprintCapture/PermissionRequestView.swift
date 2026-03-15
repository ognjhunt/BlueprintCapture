import SwiftUI

struct PermissionRequestView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.isSpaceReviewMode ? "Enable capture access" : "Enable capture sensors")
                        .font(.largeTitle.weight(.bold))
                        .blueprintGradientText()
                    Text(viewModel.isSpaceReviewMode
                         ? "We use these sensors to review the space accurately and decide whether it can become an approved capture opportunity."
                         : "We need access to your camera, microphone, and motion data to produce a metrically accurate walkthrough.")
                        .font(.callout)
                        .blueprintSecondaryOnDark()
                }

                BlueprintGlassCard {
                    PermissionRow(title: "Camera", description: "Records the visual walkthrough", granted: viewModel.cameraAuthorized)
                }
                BlueprintGlassCard {
                    PermissionRow(title: "Microphone", description: "Captures spatial audio for AI transcription", granted: viewModel.microphoneAuthorized)
                }
                BlueprintGlassCard {
                    PermissionRow(title: "Motion & Fitness", description: "Adds device pose information for metric scale", granted: viewModel.motionAuthorized)
                }

                Spacer()

                Button {
                    viewModel.requestPermissions()
                } label: {
                    Text(viewModel.isSpaceReviewMode ? "Allow access and continue" : "Grant permissions")
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())
            }
            .padding()
        }
        .blueprintAppBackground()
    }
}

private struct PermissionRow: View {
    let title: String
    let description: String
    let granted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(granted ? BlueprintTheme.successGreen : BlueprintTheme.warningOrange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .blueprintSecondaryOnDark()
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PermissionRequestView(viewModel: CaptureFlowViewModel())
}
