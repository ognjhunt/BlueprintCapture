import SwiftUI
import CoreLocation

struct LocationConfirmationView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel
    @State private var showManualEntry = false
    @State private var searchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm location")
                    .font(.largeTitle.weight(.bold))
                    .blueprintGradientText()
                Text("We use your current position to anchor the walkthrough to an exact address.")
                    .font(.callout)
                    .blueprintSecondaryOnDark()
            }

            BlueprintGlassCard {
                Group {
                    if let address = viewModel.currentAddress {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .font(.body)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(BlueprintTheme.brandTeal)
                    } else if let error = viewModel.locationError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(BlueprintTheme.errorRed)
                    } else {
                        ProgressView("Detecting your venue…")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Manual address entry toggle
            if !showManualEntry {
                Button {
                    showManualEntry = true
                } label: {
                    HStack {
                        Image(systemName: "pencil.circle")
                        Text("Can't find it? Enter address manually")
                    }
                }
                .foregroundStyle(BlueprintTheme.accentAqua)
                .font(.subheadline)
            } else {
                // Manual address entry section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Enter address")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Done") {
                            showManualEntry = false
                            searchQuery = ""
                            viewModel.addressSearchResults = []
                        }
                        .foregroundStyle(BlueprintTheme.brandTeal)
                        .font(.caption)
                        .fontWeight(.semibold)
                    }
                    
                    TextField("Search address...", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textContentType(.addressCityAndState)
                        .onChange(of: searchQuery) { oldValue, newValue in
                            if newValue.count > 2 {
                                Task {
                                    await viewModel.searchAddresses(query: newValue)
                                }
                            } else {
                                viewModel.addressSearchResults = []
                            }
                        }
                    
                    // Search results
                    if viewModel.isSearchingAddress {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Searching addresses...")
                                .font(.caption)
                                .blueprintSecondaryOnDark()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else if !viewModel.addressSearchResults.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(viewModel.addressSearchResults) { result in
                                Button {
                                    viewModel.selectAddress(result)
                                    showManualEntry = false
                                    searchQuery = ""
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .blueprintPrimaryOnDark()
                                        
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(.caption)
                                                .blueprintSecondaryOnDark()
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(BlueprintTheme.surfaceElevated.opacity(0.7))
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(BlueprintTheme.surface.opacity(0.85))
                )
            }

            Spacer()

            Button {
                if viewModel.currentAddress != nil {
                    viewModel.confirmAddress()
                } else {
                    viewModel.locationManager.requestLocation()
                }
            } label: {
                Text(viewModel.currentAddress == nil ? "Retry location" : "Use this location")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .disabled(viewModel.currentAddress == nil && viewModel.locationError == nil)
        }
        .padding()
        .blueprintAppBackground()
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
