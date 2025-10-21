import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Personal Information")) {
                    TextField("Full Name", text: $viewModel.editingProfile.fullName)
                    
                    TextField("Email", text: $viewModel.editingProfile.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                    
                    TextField("Phone Number", text: $viewModel.editingProfile.phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                
                Section(header: Text("Business Information")) {
                    TextField("Company", text: $viewModel.editingProfile.company)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelEditingProfile()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.saveProfile()
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isLoading || !isProfileValid())
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.1))
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
    
    private func isProfileValid() -> Bool {
        !viewModel.editingProfile.fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !viewModel.editingProfile.email.trimmingCharacters(in: .whitespaces).isEmpty &&
        viewModel.editingProfile.email.contains("@")
    }
}

#Preview {
    EditProfileView(viewModel: SettingsViewModel())
}
