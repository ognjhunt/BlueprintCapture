import SwiftUI

struct ProfileReviewView: View {
    let profile: UserProfile
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome back")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Please confirm your details before we begin the capture walkthrough.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            BlueprintCard {
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
                Text("Looks good — continue")
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
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

#Preview {
    ProfileReviewView(profile: .sample, onContinue: {})
}
