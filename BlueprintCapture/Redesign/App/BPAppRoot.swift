import SwiftUI

// MARK: - BPAppRoot
//
// The redesign is the shipping UI. Unauthenticated capturers see the dark sign-in
// hero; once onboarded they land on the paper tab experience. The onboarding flag
// reuses the app's existing AppStorage key so state is shared with the rest of the app.

struct BPAppRoot: View {
    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false

    var body: some View {
        Group {
            if isOnboarded {
                BPRootView()
            } else {
                BPSignInView(
                    onContinue: { isOnboarded = true },
                    onHasAccount: { isOnboarded = true }
                )
            }
        }
    }
}

#if DEBUG
#Preview {
    BPAppRoot()
}
#endif
