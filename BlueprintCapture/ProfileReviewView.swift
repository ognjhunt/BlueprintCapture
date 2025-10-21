import SwiftUI

struct ProfileReviewView: View {
    let profile: UserProfile
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome back")
                    .font(.title2)
                    .bold()
                Text("Please confirm your details before we begin the capture walkthrough.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ProfileRow(title: "Name", value: profile.fullName)
                ProfileRow(title: "Email", value: profile.email)
                ProfileRow(title: "Phone", value: profile.phoneNumber)
                ProfileRow(title: "Company", value: profile.company)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))

            Spacer()

            Button(action: onContinue) {
                Text("Looks good — continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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
