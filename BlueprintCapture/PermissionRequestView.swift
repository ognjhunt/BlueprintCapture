import SwiftUI

struct PermissionRequestView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.isSpaceReviewMode ? "Enable Capture Access" : "Enable Capture Sensors")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                        Text(viewModel.isSpaceReviewMode
                             ? "We use these sensors to review the space accurately and decide whether it qualifies as an approved capture opportunity."
                             : "We need access to your camera, microphone, and motion data to produce a metrically accurate walkthrough.")
                            .font(.subheadline)
                            .foregroundStyle(Color(white: 0.45))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 64)
                    .padding(.bottom, 28)

                    // Section label
                    Text("PERMISSIONS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(white: 0.35))
                        .tracking(1.0)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    // Permissions card
                    VStack(spacing: 0) {
                        permissionRow(
                            icon: "camera.fill",
                            iconColor: BlueprintTheme.brandTeal,
                            title: "Camera",
                            description: "Records the visual walkthrough",
                            granted: viewModel.cameraAuthorized
                        )
                        rowDivider
                        permissionRow(
                            icon: "mic.fill",
                            iconColor: Color(red: 0.9, green: 0.55, blue: 0.1),
                            title: "Microphone",
                            description: "Captures spatial audio for AI transcription",
                            granted: viewModel.microphoneAuthorized
                        )
                        rowDivider
                        permissionRow(
                            icon: "figure.walk",
                            iconColor: Color(red: 0.6, green: 0.4, blue: 0.9),
                            title: "Motion & Fitness",
                            description: "Adds device pose for metric scale",
                            granted: viewModel.motionAuthorized
                        )
                    }
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(white: 0.12), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)

                    // CTA
                    Button {
                        viewModel.requestPermissions()
                    } label: {
                        Text(viewModel.isSpaceReviewMode ? "Allow Access & Continue" : "Grant Permissions")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(BlueprintTheme.successGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
                }
            }
        }
    }

    private func permissionRow(icon: String, iconColor: Color, title: String, description: String, granted: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
            }

            Spacer()

            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.subheadline)
                .foregroundStyle(granted ? BlueprintTheme.successGreen : Color(white: 0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(white: 0.12))
            .frame(height: 1)
            .padding(.leading, 66)
    }
}

#Preview {
    PermissionRequestView(viewModel: CaptureFlowViewModel())
}
