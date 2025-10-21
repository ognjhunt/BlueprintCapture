import SwiftUI

struct NearbyTargetsView: View {
    @StateObject private var viewModel = NearbyTargetsViewModel()
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                FilterBar(radius: $viewModel.selectedRadius, limit: $viewModel.selectedLimit, sort: $viewModel.selectedSort)
                    .padding(.horizontal)
                    .padding(.top)

                content
            }
            .navigationTitle("Nearby Targets")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            VStack(spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(BlueprintTheme.warningOrange)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await viewModel.refresh() } }
                    .buttonStyle(BlueprintPrimaryButtonStyle())
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        case .loaded:
            if viewModel.items.isEmpty {
                VStack(spacing: 8) {
                    Text("No targets within \(String(format: "%.1f", viewModel.selectedRadius.rawValue)) miles")
                        .font(.headline)
                    Button("Expand radius to 5 mi") { viewModel.selectedRadius = .five }
                        .buttonStyle(BlueprintSecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(viewModel.items) { item in
                        TargetRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Optional detail placeholder
                            }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
    }
}

#Preview {
    NearbyTargetsView()
}


