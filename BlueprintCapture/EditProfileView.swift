import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Edit Profile")
                                .font(BlueprintTheme.display(34, weight: .semibold))
                                .foregroundStyle(BlueprintTheme.textPrimary)
                            Text("Update the details attached to your Blueprint capture activity.")
                                .font(BlueprintTheme.body(14, weight: .medium))
                                .foregroundStyle(BlueprintTheme.textSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 24)

                        sectionCard(
                            title: "Personal Information",
                            fields: [
                                profileField("Full Name", text: $viewModel.editingProfile.fullName),
                                profileField("Email", text: $viewModel.editingProfile.email, keyboardType: .emailAddress, textContentType: .emailAddress),
                                profileField("Phone Number", text: $viewModel.editingProfile.phoneNumber, keyboardType: .phonePad, textContentType: .telephoneNumber)
                            ]
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)

                        sectionCard(
                            title: "Business Information",
                            fields: [
                                profileField("Company", text: $viewModel.editingProfile.company)
                            ]
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await viewModel.saveProfile()
                                    dismiss()
                                }
                            } label: {
                                Text("Save")
                                    .font(BlueprintTheme.body(16, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        (viewModel.isLoading || !isProfileValid()) ? Color.white.opacity(0.28) : Color.white,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLoading || !isProfileValid())

                            Button("Cancel") {
                                viewModel.cancelEditingProfile()
                                dismiss()
                            }
                            .font(BlueprintTheme.body(14, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .blueprintAppBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.cancelEditingProfile()
                        dismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Back")
                                .font(BlueprintTheme.body(14, weight: .semibold))
                        }
                        .foregroundStyle(BlueprintTheme.textSecondary)
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.25))
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.showError = false
                }
            } message: {
                if let error = viewModel.error {
                    Text(error.errorDescription ?? "An error occurred")
                }
            }
        }
    }

    private func sectionCard(title: String, fields: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(BlueprintTheme.body(12, weight: .bold))
                .foregroundStyle(BlueprintTheme.textTertiary)
                .tracking(1.0)

            VStack(spacing: 12) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    field
                }
            }
        }
        .padding(18)
        .blueprintEditorialCard(radius: 20, fill: BlueprintTheme.panel)
    }

    private func profileField(
        _ title: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil
    ) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(BlueprintTheme.body(12, weight: .semibold))
                    .foregroundStyle(BlueprintTheme.textTertiary)

                TextField(title, text: text)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .font(BlueprintTheme.body(15, weight: .medium))
                    .foregroundStyle(BlueprintTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(BlueprintTheme.hairline, lineWidth: 1)
                    )
            }
        )
    }

    private func isProfileValid() -> Bool {
        !viewModel.editingProfile.fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !viewModel.editingProfile.email.trimmingCharacters(in: .whitespaces).isEmpty &&
        viewModel.editingProfile.email.contains("@")
    }
}

#Preview {
    EditProfileView(viewModel: SettingsViewModel())
}
