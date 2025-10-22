import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CaptureFlowViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .collectProfile:
                    ProfileReviewView(profile: viewModel.profile, onContinue: viewModel.requestLocation)
                case .confirmLocation:
                    LocationConfirmationView(viewModel: viewModel)
                case .requestPermissions:
                    PermissionRequestView(viewModel: viewModel)
                case .readyToCapture:
                    CaptureSessionView(viewModel: viewModel, targetId: nil, reservationId: nil)
                }
            }
            .navigationTitle("Blueprint Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .blueprintAppBackground()
        .task {
            await viewModel.loadProfile()
        }
    }
}

#Preview {
    ContentView()
}
