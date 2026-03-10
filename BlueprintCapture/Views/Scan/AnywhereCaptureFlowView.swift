import SwiftUI

struct AnywhereCaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(viewModel.step == .readyToCapture ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if viewModel.step != .readyToCapture {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .blueprintAppBackground()
        .task {
            await viewModel.loadProfile()
        }
    }

    private var navigationTitle: String {
        switch viewModel.step {
        case .collectProfile:
            return "Capture Anywhere"
        case .confirmLocation:
            return "Confirm Location"
        case .requestPermissions:
            return "Enable Sensors"
        case .readyToCapture:
            return ""
        }
    }
}

#Preview {
    AnywhereCaptureFlowView()
}
