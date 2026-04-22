import SwiftUI

struct ProfileReviewView: View {
    let profile: UserProfile
    let onContinue: () -> Void
    var title: String = "Welcome back"
    var subtitle: String = "Please confirm your details before we begin the capture walkthrough."
    var buttonTitle: String = "Looks good — continue"

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(BlueprintTheme.display(34, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                    Text(subtitle)
                        .font(BlueprintTheme.body(15, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 28)

                // Section label
                Text("YOUR DETAILS")
                    .font(BlueprintTheme.body(12, weight: .bold))
                    .foregroundStyle(BlueprintTheme.textTertiary)
                    .tracking(1.0)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                // Profile card
                VStack(spacing: 0) {
                    profileRow(label: "Name", value: profile.fullName)
                    rowDivider
                    profileRow(label: "Email", value: profile.email)
                    rowDivider
                    profileRow(label: "Phone", value: profile.phoneNumber)
                    rowDivider
                    profileRow(label: "Company", value: profile.company)
                }
                .blueprintEditorialCard(radius: 18, fill: BlueprintTheme.panel)
                .padding(.horizontal, 20)

                Spacer()

                // CTA
                Button(action: onContinue) {
                    Text(buttonTitle)
                        .font(BlueprintTheme.body(16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
        }
        .blueprintAppBackground()
    }

    private func profileRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(BlueprintTheme.body(14, weight: .medium))
                .foregroundStyle(BlueprintTheme.textSecondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(BlueprintTheme.body(14, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(BlueprintTheme.hairline)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

#Preview {
    ProfileReviewView(profile: .sample, onContinue: {})
}
