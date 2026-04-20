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
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            // Step content
            Group {
                switch viewModel.step {
                case .collectProfile:
                    ProfileReviewView(
                        profile: viewModel.profile,
                        onContinue: { viewModel.requestLocation() },
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

            // Floating close button — hidden during capture session
            if viewModel.step != .readyToCapture {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(white: 0.7))
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadProfile()
        }
    }
}

#Preview {
    AnywhereCaptureFlowView(seed: SpaceReviewSeed(title: "Loading dock review", address: "18 Kent Ave, Brooklyn, NY"))
}
