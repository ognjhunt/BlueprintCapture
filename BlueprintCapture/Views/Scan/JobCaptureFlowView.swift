import SwiftUI

/// Recording the walkthrough for a paid job, on the phone.
///
/// This replaces the smart-glasses recorder that used to sit here. The product
/// is one thing now: a capturer goes to a site and records one video with the
/// phone in their hand. That video is the only input the world model needs —
/// frames are pulled from it server-side and sent to World Labs, which does the
/// reconstruction. Nothing about the capture device has to be special.
///
/// Structurally this is `AnywhereCaptureFlowView` pointed at a job instead of
/// an open capture: same permission and location steps, same capture session,
/// with the job's id carried through so the upload lands against the right
/// target and the right payout.
struct JobCaptureFlowView: View {
    let job: ScanJob

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CaptureFlowViewModel

    init(job: ScanJob) {
        self.job = job
        _viewModel = StateObject(wrappedValue: CaptureFlowViewModel(flowMode: .standard))
    }

    var body: some View {
        ZStack(alignment: .top) {
            BP.viewfinder.ignoresSafeArea()

            Group {
                switch viewModel.step {
                case .collectProfile:
                    ProfileReviewView(
                        profile: viewModel.profile,
                        onContinue: { viewModel.requestLocation() },
                        title: "Before you capture",
                        subtitle: "Confirm your details, then we'll get you to the site.",
                        buttonTitle: "Continue"
                    )
                case .confirmLocation:
                    LocationConfirmationView(viewModel: viewModel)
                case .requestPermissions:
                    PermissionRequestView(viewModel: viewModel)
                case .readyToCapture:
                    CaptureSessionView(
                        viewModel: viewModel,
                        targetId: job.id,
                        reservationId: nil
                    )
                }
            }

            // Hidden during capture: there is a dedicated stop control there,
            // and a second dismiss next to it invites ending a paid walkthrough
            // by accident.
            if viewModel.step != .readyToCapture {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.bpSans(BPType.body, .medium))
                            .foregroundStyle(BP.onInk)
                            .padding(Space.m)
                    }
                    .accessibilityLabel("Close capture")
                }
                .padding(.top, Space.s)
            }
        }
        .onAppear {
            viewModel.currentTargetInfo = (
                name: job.title,
                estimatedPayoutRange: job.explicitPayoutDollarRange
            )
        }
    }
}
