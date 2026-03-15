import SwiftUI

struct CaptureTutorialView: View {
    let onContinue: () -> Void

    @State private var currentStep = 0

    private let steps: [TutorialStep] = [
        TutorialStep(
            icon: "iphone.gen3",
            title: "Hold your phone upright",
            detail: "Walk naturally with your phone in front of you, like you're taking a video."
        ),
        TutorialStep(
            icon: "figure.walk",
            title: "Move slowly and steadily",
            detail: "Cover all areas of the space. Walk at a calm, even pace for the best results."
        ),
        TutorialStep(
            icon: "lightbulb.fill",
            title: "Good lighting helps",
            detail: "Well-lit spaces produce higher quality captures and bigger payouts."
        ),
        TutorialStep(
            icon: "clock.fill",
            title: "15–30 minutes",
            detail: "A complete capture takes 15–30 minutes. Longer, thorough captures earn more."
        ),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Step content
            VStack(spacing: 20) {
                Image(systemName: steps[currentStep].icon)
                    .font(.system(size: 64))
                    .foregroundStyle(BlueprintTheme.brandTeal)
                    .frame(height: 80)

                Text(steps[currentStep].title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(steps[currentStep].detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            Spacer()

            // Step indicators
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? BlueprintTheme.brandTeal : Color(.tertiarySystemFill))
                        .frame(width: 8, height: 8)
                }
            }

            // Navigation buttons
            VStack(spacing: 12) {
                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(BlueprintPrimaryButtonStyle())

                    Button("Skip Tutorial", action: onContinue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Got It", action: onContinue)
                        .buttonStyle(BlueprintPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

private struct TutorialStep {
    let icon: String
    let title: String
    let detail: String
}

#Preview {
    CaptureTutorialView { }
        .preferredColorScheme(.dark)
}
