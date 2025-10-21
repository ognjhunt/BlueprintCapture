import SwiftUI

struct PermissionRequestView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enable capture sensors")
                    .font(.largeTitle.weight(.bold))
                Text("We need access to your camera, microphone, and motion data to produce a metrically accurate walkthrough.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            BlueprintCard {
                PermissionRow(title: "Camera", description: "Records the visual walkthrough", granted: viewModel.cameraAuthorized)
            }
            BlueprintCard {
                PermissionRow(title: "Microphone", description: "Captures spatial audio for AI transcription", granted: viewModel.microphoneAuthorized)
            }
            BlueprintCard {
                PermissionRow(title: "Motion & Fitness", description: "Adds device pose information for metric scale", granted: viewModel.motionAuthorized)
            }

            Spacer()

            Button {
                viewModel.requestPermissions()
            } label: {
                Text("Grant permissions")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
        }
        .padding()
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
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PermissionRequestView(viewModel: CaptureFlowViewModel())
}
