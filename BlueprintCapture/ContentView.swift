import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var viewModel: CaptureFlowViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: CaptureFlowViewModel())
    }

    var body: some View {
        NavigationStack {
            content
            .navigationTitle("Blueprint Capture")
            .navigationBarTitleDisplayMode(.inline)
#if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
#endif
        }
        .blueprintAppBackground()
        .task {
            await viewModel.loadProfile()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .collectProfile:
            ProfileReviewView(profile: viewModel.profile, onContinue: { viewModel.requestLocation() })
        case .confirmLocation:
            LocationConfirmationView(viewModel: viewModel)
        case .requestPermissions:
            PermissionRequestView(viewModel: viewModel)
        case .readyToCapture:
            CaptureSessionView(viewModel: viewModel, targetId: nil, reservationId: nil)
        }
    }
}

#Preview {
    ContentView()
}
