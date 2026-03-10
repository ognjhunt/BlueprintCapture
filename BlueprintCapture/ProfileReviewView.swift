import SwiftUI

struct ProfileReviewView: View {
    let profile: UserProfile
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Operator profile")
                    .font(.largeTitle.weight(.bold))
                    .blueprintGradientText()
                Text("Confirm who is creating this qualification submission before the evidence workflow begins.")
                    .font(.callout)
                    .blueprintSecondaryOnDark()
            }

            BlueprintGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    ProfileRow(title: "Name", value: profile.fullName)
                    Divider()
                    ProfileRow(title: "Email", value: profile.email)
                    Divider()
                    ProfileRow(title: "Phone", value: profile.phoneNumber)
                    Divider()
                    ProfileRow(title: "Company", value: profile.company)
                }
            }

            Spacer()

            Button(action: onContinue) {
                Text("Continue to intake")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
        }
        .padding()
    }
}

private struct ProfileRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .blueprintSecondaryOnDark()
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(.body)
                .blueprintPrimaryOnDark()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

#Preview {
    ProfileReviewView(profile: .sample, onContinue: {})
}
