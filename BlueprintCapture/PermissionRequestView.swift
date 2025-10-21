import SwiftUI

struct PermissionRequestView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enable capture sensors")
                    .font(.title2)
                    .bold()
                Text("We need access to your camera, microphone, and motion data to produce a metrically accurate walkthrough.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            PermissionRow(title: "Camera", description: "Records the visual walkthrough", granted: viewModel.cameraAuthorized)
            PermissionRow(title: "Microphone", description: "Captures spatial audio for AI transcription", granted: viewModel.microphoneAuthorized)
            PermissionRow(title: "Motion & Fitness", description: "Adds device pose information for metric scale", granted: viewModel.motionAuthorized)

            Spacer()

            Button {
                viewModel.requestPermissions()
            } label: {
                Text("Grant permissions")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(granted ? .green : .orange)
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
        .padding()
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

#Preview {
    PermissionRequestView(viewModel: CaptureFlowViewModel())
}
