import SwiftUI

struct LocationConfirmationView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm location")
                    .font(.title2)
                    .bold()
                Text("We use your current position to anchor the walkthrough to an exact address.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Group {
                if let address = viewModel.currentAddress {
                    Label(address, systemImage: "mappin.and.ellipse")
                        .font(.body)
                } else if let error = viewModel.locationError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else {
                    ProgressView("Detecting your venue…")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))

            Spacer()

            Button {
                if viewModel.currentAddress != nil {
                    viewModel.confirmAddress()
                } else {
                    viewModel.locationManager.requestLocation()
                }
            } label: {
                Text(viewModel.currentAddress == nil ? "Retry location" : "Use this location")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.currentAddress == nil && viewModel.locationError == nil)
        }
        .padding()
        .task {
            if viewModel.currentAddress == nil {
                viewModel.locationManager.requestLocation()
            }
        }
    }
}

#Preview {
    LocationConfirmationView(viewModel: CaptureFlowViewModel())
}
