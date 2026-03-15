import SwiftUI

struct ProfileReviewView: View {
    let profile: UserProfile
    let onContinue: () -> Void
    var title: String = "Welcome back"
    var subtitle: String = "Please confirm your details before we begin the capture walkthrough."
    var buttonTitle: String = "Looks good — continue"

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.45))
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 28)

                // Section label
                Text("YOUR DETAILS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(white: 0.35))
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
                .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(white: 0.12), lineWidth: 1)
                )
                .padding(.horizontal, 20)

                Spacer()

                // CTA
                Button(action: onContinue) {
                    Text(buttonTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(BlueprintTheme.brandTeal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
        }
    }

    private func profileRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.4))
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(white: 0.12))
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

#Preview {
    ProfileReviewView(profile: .sample, onContinue: {})
}
