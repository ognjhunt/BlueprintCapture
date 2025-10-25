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
            GeometryReader { geometry in
                ZStack {
                    // Premium gradient background using Blueprint theme
                    LinearGradient(
                        colors: [
                            BlueprintTheme.primaryDeep.opacity(0.90),
                            BlueprintTheme.primary.opacity(0.70),
                            BlueprintTheme.brandTeal.opacity(0.50)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    // Responsive animated brand glows
                    Circle()
                        .fill(BlueprintTheme.primary.opacity(0.20))
                        .frame(width: geometry.size.width * 1.2, height: geometry.size.width * 1.2)
                        .blur(radius: 100)
                        .offset(x: geometry.size.width * 0.3, y: -geometry.size.height * 0.15)

                    Circle()
                        .fill(BlueprintTheme.brandTeal.opacity(0.18))
                        .frame(width: geometry.size.width * 1.1, height: geometry.size.width * 1.1)
                        .blur(radius: 100)
                        .offset(x: -geometry.size.width * 0.3, y: geometry.size.height * 0.3)

                    ScrollView {
                        VStack(spacing: 0) {
                            // Header Section
                            VStack(spacing: 12) {
                                Text("Welcome to Blueprint")
                                    .font(.system(size: min(32, geometry.size.width * 0.085), weight: .bold, design: .default))
                                    .foregroundStyle(Color.white)
                                    .minimumScaleFactor(0.8)
                                    .lineLimit(1)

                                Text("Capture properties. Get paid instantly.")
                                    .font(.system(size: 16, weight: .regular, design: .default))
                                    .foregroundStyle(Color.white.opacity(0.85))
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 20)
                            .padding(.bottom, 24)
                            .padding(.horizontal, 24)

                        // Main Content Card
                        VStack(spacing: 20) {
                            // Google Sign-In Button
                            #if canImport(GoogleSignInSwift)
                            GoogleSignInButton(viewModel: .init(scheme: .light, style: .wide, state: .normal)) {
                                Task { await viewModel.signInWithGoogle() }
                            }
                            .frame(height: 52)
                            #else
                            Button {
                                Task { await viewModel.signInWithGoogle() }
                            } label: {
                                HStack(spacing: 14) {
                                    GoogleLogo(size: 20)
                                    Text("Continue with Google")
                                        .font(.system(size: 15, weight: .semibold, design: .default))
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 52)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white)
                                )
                                .foregroundStyle(Color(red: 0.25, green: 0.25, blue: 0.25))
                                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            #endif

                            // Divider
                            HStack(spacing: 12) {
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundStyle(Color.white.opacity(0.20))
                                Text("or")
                                    .font(.system(size: 13, weight: .medium, design: .default))
                                    .foregroundStyle(Color.white.opacity(0.70))
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundStyle(Color.white.opacity(0.20))
                            }
                            .padding(.vertical, 4)

                            // Mode Selector
                            segmentedControl

                            // Form Fields
                            formFields

                            // Error Message
                            if let err = viewModel.errorMessage, !err.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 14))
                                    Text(err)
                                        .font(.system(size: 13, weight: .regular, design: .default))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(BlueprintTheme.errorRed)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(BlueprintTheme.errorRed.opacity(0.12))
                                )
                            }

                            // Submit Button
                            Button {
                                Task { await viewModel.submit() }
                            } label: {
                                if viewModel.isBusy {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white)
                                        Text("Processing...")
                                            .fontWeight(.semibold)
                                    }
                                } else {
                                    Text(viewModel.mode == .signIn ? "Sign In" : "Create Account")
                                        .fontWeight(.semibold)
                                }
                            }
                            .buttonStyle(BlueprintPrimaryButtonStyle())
                            .disabled(!viewModel.canSubmit)
                            .opacity(viewModel.canSubmit ? 1.0 : 0.6)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.30),
                                                    Color.white.opacity(0.10)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .padding(.horizontal, 20)

                        // Footer
                        VStack(spacing: 12) {
                            Text("By continuing, you agree to Blueprint's")
                                .font(.system(size: 12, weight: .regular, design: .default))
                            + Text(" Terms of Service")
                                .font(.system(size: 12, weight: .semibold, design: .default))
                            + Text(" and ")
                                .font(.system(size: 12, weight: .regular, design: .default))
                            + Text("Privacy Policy")
                                .font(.system(size: 12, weight: .semibold, design: .default))

                            Text("Questions? Contact support@blueprint.app")
                                .font(.system(size: 11, weight: .regular, design: .default))
                                .foregroundStyle(Color.white.opacity(0.60))
                        }
                        .foregroundStyle(Color.white.opacity(0.80))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 20)
                }
                .scrollIndicators(.hidden)
            }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Close")
                        }
                        .foregroundStyle(Color.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                        )
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onReceive(NotificationCenter.default.publisher(for: .AuthStateDidChange)) { _ in
                dismiss()
            }
        }
    }

    private var segmentedControl: some View {
        HStack(spacing: 8) {
            ForEach([AuthViewModel.Mode.signIn, .signUp], id: \.self) { mode in
                Button(action: { 
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.mode = mode
                    }
                }) {
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    viewModel.mode == mode
                                        ? LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.25),
                                                Color.white.opacity(0.15)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        : LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.08),
                                                Color.white.opacity(0.04)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            Color.white.opacity(
                                                viewModel.mode == mode ? 0.30 : 0.10
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
    }

    private var formFields: some View {
        VStack(spacing: 12) {
            if viewModel.mode == .signUp {
                CustomTextField(
                    title: "Full Name",
                    placeholder: "John Doe",
                    text: $viewModel.name,
                    systemImage: "person.fill",
                    isFocused: focusedField == .name
                )
                .onTapGesture { focusedField = .name }
            }

            CustomTextField(
                title: "Email Address",
                placeholder: "you@example.com",
                text: $viewModel.email,
                systemImage: "envelope.fill",
                keyboardType: .emailAddress,
                isFocused: focusedField == .email
            )
            .onTapGesture { focusedField = .email }

            CustomSecureField(
                title: "Password",
                placeholder: "At least 8 characters",
                text: $viewModel.password,
                isFocused: focusedField == .password
            )
            .onTapGesture { focusedField = .password }

            if viewModel.mode == .signUp {
                CustomSecureField(
                    title: "Confirm Password",
                    placeholder: "Re-enter your password",
                    text: $viewModel.confirmPassword,
                    isFocused: focusedField == .confirmPassword
                )
                .onTapGesture { focusedField = .confirmPassword }
            }
        }
    }
}

// MARK: - Custom Input Components

struct CustomTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let systemImage: String
    var keyboardType: UIKeyboardType = .default
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(Color.white.opacity(0.90))

            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(isFocused ? 1.0 : 0.60))

                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .foregroundStyle(Color.white)
                    .tint(BlueprintTheme.brandTeal)

                if !text.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(BlueprintTheme.successGreen)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isFocused
                            ? LinearGradient(
                                colors: [
                                    BlueprintTheme.brandTeal.opacity(0.60),
                                    BlueprintTheme.primary.opacity(0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(0.20),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: 1.5
                    )
            )
        }
    }
}

struct CustomSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isFocused: Bool
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(Color.white.opacity(0.90))

            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(isFocused ? 1.0 : 0.60))

                if isVisible {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundStyle(Color.white)
                        .tint(BlueprintTheme.brandTeal)
                } else {
                    SecureField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundStyle(Color.white)
                        .tint(BlueprintTheme.brandTeal)
                }

                Button(action: { isVisible.toggle() }) {
                    Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isFocused
                            ? LinearGradient(
                                colors: [
                                    BlueprintTheme.brandTeal.opacity(0.60),
                                    BlueprintTheme.primary.opacity(0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(0.20),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: 1.5
                    )
            )
        }
    }
}

// MARK: - Google Logo Component
struct GoogleLogo: View {
    var size: CGFloat = 20
    
    var body: some View {
        ZStack {
            // Google "G" logo recreation
            Circle()
                .strokeBorder(lineWidth: size * 0.12)
                .foregroundStyle(
                    AngularGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96), // Blue
                            Color(red: 0.20, green: 0.66, blue: 0.33), // Green
                            Color(red: 0.98, green: 0.74, blue: 0.02), // Yellow
                            Color(red: 0.92, green: 0.25, blue: 0.21), // Red
                            Color(red: 0.26, green: 0.52, blue: 0.96)  // Blue (complete circle)
                        ],
                        center: .center
                    )
                )
                .frame(width: size, height: size)
            
            // Inner details
            Circle()
                .trim(from: 0.0, to: 0.75)
                .stroke(lineWidth: size * 0.15)
                .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                .frame(width: size * 0.65, height: size * 0.65)
                .rotationEffect(.degrees(-45))
        }
    }
}

#Preview { AuthView() }


