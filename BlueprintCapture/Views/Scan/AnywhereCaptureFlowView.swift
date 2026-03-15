import SwiftUI

struct AnywhereCaptureFlowView: View {
    let seed: SpaceReviewSeed?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CaptureFlowViewModel

    init(seed: SpaceReviewSeed? = nil) {
        self.seed = seed
        _viewModel = StateObject(wrappedValue: CaptureFlowViewModel(flowMode: .spaceReview(seed: seed)))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .collectProfile:
                    ProfileReviewView(
                        profile: viewModel.profile,
                        onContinue: viewModel.requestLocation,
                        title: "Before you capture",
                        subtitle: "We review these submissions before they become approved capture opportunities. Confirm your details, then tell us about the space.",
                        buttonTitle: "Continue"
                    )
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
            return seed?.title ?? "Submit a space"
        case .confirmLocation:
            return "Submit a space"
        case .requestPermissions:
            return "Review access"
        case .readyToCapture:
            return ""
        }
    }
}

#Preview {
    AnywhereCaptureFlowView(seed: SpaceReviewSeed(title: "Loading dock review", address: "18 Kent Ave, Brooklyn, NY"))
}
