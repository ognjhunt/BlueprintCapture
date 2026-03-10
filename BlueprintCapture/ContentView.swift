import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CaptureFlowViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .collectProfile:
                    ProfileReviewView(profile: viewModel.profile, onContinue: viewModel.continueFromProfile)
                case .defineSubmission:
                    QualificationIntakeView(viewModel: viewModel)
                case .confirmLocation:
                    LocationConfirmationView(viewModel: viewModel)
                case .requestPermissions:
                    PermissionRequestView(viewModel: viewModel)
                case .reviewCapture:
                    CaptureReviewView(viewModel: viewModel)
                case .readyToCapture:
                    if let captureContext = viewModel.activeCaptureContext {
                        CaptureSessionView(viewModel: viewModel, captureContext: captureContext)
                    } else {
                        ProgressView("Preparing capture…")
                    }
                case .captureSummary:
                    CaptureSummaryView(viewModel: viewModel)
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
