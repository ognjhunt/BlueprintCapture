import SwiftUI
#if canImport(GoogleSignInSwift)
import GoogleSignInSwift
#endif

struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AuthViewModel()
    @FocusState private var focusedField: FocusField?

    enum FocusField { case name, email, password, confirmPassword }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Welcome to Blueprint")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Capture spaces for review. Get paid after approval.")
                                .font(.subheadline)
                                .foregroundStyle(Color(white: 0.45))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                        .padding(.horizontal, 20)

                        // Form
                        VStack(spacing: 14) {
                            // Social sign-in
                            socialButtons

                            // Divider
                            HStack(spacing: 12) {
                                Rectangle()
                                    .fill(Color(white: 0.15))
                                    .frame(height: 1)
                                Text("or")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color(white: 0.4))
                                Rectangle()
                                    .fill(Color(white: 0.15))
                                    .frame(height: 1)
                            }
                            .padding(.vertical, 4)

                            // Mode toggle
                            modeToggle

                            // Fields
                            formFields

                            // Error
                            if let err = viewModel.errorMessage, !err.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                    Text(err)
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.35))
                                .padding(12)
                                .background(
                                    Color(red: 0.95, green: 0.35, blue: 0.35).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }

                            // Submit
                            Button {
                                Task { await viewModel.submit() }
                            } label: {
                                Group {
                                    if viewModel.isBusy {
                                        HStack(spacing: 8) {
                                            ProgressView().tint(.black).controlSize(.small)
                                            Text("Processing…").fontWeight(.semibold)
                                        }
                                    } else {
                                        Text(viewModel.mode == .signIn ? "Sign In" : "Create Account")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    viewModel.canSubmit ? Color.white : Color(white: 0.35),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!viewModel.canSubmit)
                        }
                        .padding(.horizontal, 20)

                        // Footer
                        VStack(spacing: 8) {
                            Text("By continuing, you agree to Blueprint's ")
                                .foregroundStyle(Color(white: 0.4))
                            + Text("Terms of Service")
                                .foregroundStyle(Color(white: 0.6))
                                .underline()
                            + Text(" and ")
                                .foregroundStyle(Color(white: 0.4))
                            + Text("Privacy Policy")
                                .foregroundStyle(Color(white: 0.6))
                                .underline()

                            Text("Questions? Contact support@blueprint.app")
                                .foregroundStyle(Color(white: 0.3))
                        }
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.top, 32)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Close")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color(white: 0.6))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onReceive(NotificationCenter.default.publisher(for: .AuthStateDidChange)) { _ in
                dismiss()
            }
            .task {
                viewModel.consumePasteboardReferralIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Social buttons

    private var socialButtons: some View {
        VStack(spacing: 10) {
            #if canImport(GoogleSignInSwift)
            GoogleSignInButton(
                viewModel: .init(scheme: .dark, style: .wide, state: viewModel.isBusy ? .disabled : .normal)
            ) {
                Task { await viewModel.signInWithGoogle() }
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            #else
            Button {
                Task { await viewModel.signInWithGoogle() }
            } label: {
                HStack(spacing: 12) {
                    GoogleLogo(size: 18)
                    Text("Continue with Google")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(white: 0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    // MARK: - Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 6) {
            ForEach([AuthViewModel.Mode.signIn, .signUp], id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { viewModel.mode = mode }
                } label: {
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(viewModel.mode == mode ? .white : Color(white: 0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            viewModel.mode == mode
                                ? Color(white: 0.18)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    // MARK: - Form fields

    private var formFields: some View {
        VStack(spacing: 12) {
            if viewModel.mode == .signUp {
                kledTextField(
                    title: "Full Name",
                    placeholder: "John Doe",
                    text: $viewModel.name,
                    icon: "person.fill",
                    focusBinding: $focusedField,
                    focusValue: .name,
                    submitLabel: .next
                ) { focusedField = .email }
            }

            kledTextField(
                title: "Email Address",
                placeholder: "you@example.com",
                text: $viewModel.email,
                icon: "envelope.fill",
                keyboardType: .emailAddress,
                focusBinding: $focusedField,
                focusValue: .email,
                submitLabel: .next
            ) { focusedField = .password }

            kledSecureField(
                title: "Password",
                placeholder: "At least 8 characters",
                text: $viewModel.password,
                focusBinding: $focusedField,
                focusValue: .password,
                submitLabel: viewModel.mode == .signUp ? .next : .go
            ) {
                if viewModel.mode == .signUp { focusedField = .confirmPassword }
                else { Task { await viewModel.submit() } }
            }

            if viewModel.mode == .signUp {
                kledSecureField(
                    title: "Confirm Password",
                    placeholder: "Re-enter your password",
                    text: $viewModel.confirmPassword,
                    focusBinding: $focusedField,
                    focusValue: .confirmPassword,
                    submitLabel: .go
                ) { Task { await viewModel.submit() } }
            }
        }
    }

    // MARK: - Field builders

    private func kledTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        keyboardType: UIKeyboardType = .default,
        focusBinding: FocusState<FocusField?>.Binding,
        focusValue: FocusField,
        submitLabel: SubmitLabel = .next,
        onSubmit: @escaping () -> Void = {}
    ) -> some View {
        let focused = focusBinding.wrappedValue == focusValue
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.6))

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(focused ? BlueprintTheme.brandTeal : Color(white: 0.4))
                    .frame(width: 20)

                TextField(placeholder, text: text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .foregroundStyle(.white)
                    .tint(BlueprintTheme.brandTeal)
                    .focused(focusBinding, equals: focusValue)
                    .submitLabel(submitLabel)
                    .onSubmit(onSubmit)

                if !text.wrappedValue.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.successGreen)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        focused ? BlueprintTheme.brandTeal.opacity(0.6) : Color(white: 0.18),
                        lineWidth: focused ? 1.5 : 1
                    )
            )
        }
    }

    private func kledSecureField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        focusBinding: FocusState<FocusField?>.Binding,
        focusValue: FocusField,
        submitLabel: SubmitLabel = .next,
        onSubmit: @escaping () -> Void = {}
    ) -> some View {
        KledSecureFieldView(
            title: title,
            placeholder: placeholder,
            text: text,
            focusBinding: focusBinding,
            focusValue: focusValue,
            submitLabel: submitLabel,
            onSubmit: onSubmit
        )
    }
}

// MARK: - Kled Secure Field

private struct KledSecureFieldView<F: Hashable>: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var focusBinding: FocusState<F?>.Binding
    let focusValue: F
    let submitLabel: SubmitLabel
    let onSubmit: () -> Void
    @State private var visible = false

    var focused: Bool { focusBinding.wrappedValue == focusValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.6))

            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(focused ? BlueprintTheme.brandTeal : Color(white: 0.4))
                    .frame(width: 20)

                if visible {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundStyle(.white)
                        .tint(BlueprintTheme.brandTeal)
                        .focused(focusBinding, equals: focusValue)
                        .submitLabel(submitLabel)
                        .onSubmit(onSubmit)
                } else {
                    SecureField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundStyle(.white)
                        .tint(BlueprintTheme.brandTeal)
                        .focused(focusBinding, equals: focusValue)
                        .submitLabel(submitLabel)
                        .onSubmit(onSubmit)
                }

                Button { visible.toggle() } label: {
                    Image(systemName: visible ? "eye.slash.fill" : "eye.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        focused ? BlueprintTheme.brandTeal.opacity(0.6) : Color(white: 0.18),
                        lineWidth: focused ? 1.5 : 1
                    )
            )
        }
    }
}

// MARK: - Google Logo

struct GoogleLogo: View {
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(lineWidth: size * 0.12)
                .foregroundStyle(
                    AngularGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),
                            Color(red: 0.20, green: 0.66, blue: 0.33),
                            Color(red: 0.98, green: 0.74, blue: 0.02),
                            Color(red: 0.92, green: 0.25, blue: 0.21),
                            Color(red: 0.26, green: 0.52, blue: 0.96)
                        ],
                        center: .center
                    )
                )
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0.0, to: 0.75)
                .stroke(lineWidth: size * 0.15)
                .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                .frame(width: size * 0.65, height: size * 0.65)
                .rotationEffect(.degrees(-45))
        }
    }
}

// MARK: - Removed: CustomTextField / CustomSecureField
// Replaced by kledTextField / KledSecureFieldView above.

#Preview { AuthView() }
