import SwiftUI
import CoreLocation
import UIKit

struct LaunchCityGateRootView<Content: View>: View {
    @Bindable var viewModel: LaunchCityGateViewModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            switch viewModel.state {
            case .supported:
                content()
            default:
                LaunchCityGateView(viewModel: viewModel)
            }
        }
        .task {
            viewModel.start()
        }
    }
}

struct LaunchCityGateView: View {
    @Bindable var viewModel: LaunchCityGateViewModel
    @Environment(\.openURL) private var openURL

    private var launchRequestURL: URL? {
        AppConfig.mainWebsiteURL()
            ?? AppConfig.helpCenterURL()
            ?? AppConfig.supportEmailURL(subject: "Request launch access")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [BlueprintTheme.bgDarker, BlueprintTheme.bgDark, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 68)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                statusCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                liveCitiesCard
                    .padding(.horizontal, 20)

                Spacer(minLength: 28)

                footerActions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 34)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Blueprint city launch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.brandTeal)
                .tracking(1.2)

            Text("We’re only live in a few cities right now.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Your location determines whether the capture network unlocks. Launch availability follows Blueprint's active city program.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                statusIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let resolvedCity = viewModel.resolvedCity,
               case .unsupported = viewModel.state {
                HStack(spacing: 8) {
                    Image(systemName: "location.circle.fill")
                        .foregroundStyle(BlueprintTheme.warningOrange)
                    Text("Detected: \(resolvedCity.displayName)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                }
            }

            if case .checking = viewModel.state {
                ProgressView()
                    .tint(BlueprintTheme.brandTeal)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var liveCitiesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Currently live")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(viewModel.supportedCities.isEmpty
                 ? "We’ll show supported launch cities as soon as availability syncs."
                 : "These cities are synced from Blueprint's current launch program.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(viewModel.supportedCities) { city in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(city.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Launch market")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.5))
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BlueprintTheme.brandTeal)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var footerActions: some View {
        VStack(spacing: 12) {
            primaryAction

            Button {
                viewModel.refresh()
            } label: {
                Text("Check again")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch viewModel.state {
        case .locationPermissionRequired:
            Button {
                Task { await viewModel.requestLocationAccess() }
            } label: {
                primaryLabel("Allow location")
            }
            .buttonStyle(.plain)

        case .locationPermissionDenied:
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Button {
                    openURL(settingsURL)
                } label: {
                    primaryLabel("Open settings")
                }
                .buttonStyle(.plain)
            }

        case .unsupported, .failed:
            if let launchRequestURL {
                Button {
                    openURL(launchRequestURL)
                } label: {
                    primaryLabel("Request launch access")
                }
                .buttonStyle(.plain)
            }

        case .checking, .supported:
            EmptyView()
        }
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BlueprintTheme.brandTeal)
            )
    }

    private var statusTitle: String {
        switch viewModel.state {
        case .checking:
            return "Checking your launch city"
        case .locationPermissionRequired:
            return "Location required"
        case .locationPermissionDenied:
            return "Location access is off"
        case .supported(let city):
            return "\(city.displayName) is live"
        case .unsupported:
            return "Blueprint isn’t live here yet"
        case .failed:
            return "We couldn’t verify your city"
        }
    }

    private var statusMessage: String {
        switch viewModel.state {
        case .checking:
            return "We’re verifying whether your current city is one of the launch markets."
        case .locationPermissionRequired:
            return "Enable location so Blueprint can verify whether you’re in one of the cities we support today."
        case .locationPermissionDenied:
            return "Turn location access back on in Settings to verify whether Blueprint is available in your city."
        case .supported:
            return "Your city is inside the current launch footprint. The capture app will unlock automatically."
        case .unsupported:
            return "We’re rolling out city by city. You can request access or check again after you move into a supported market."
        case .failed(let message):
            return message
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.state {
        case .checking:
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BlueprintTheme.brandTeal)
                .frame(width: 50, height: 50)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .locationPermissionRequired, .locationPermissionDenied:
            Image(systemName: "location.slash.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BlueprintTheme.warningOrange)
                .frame(width: 50, height: 50)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .supported:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BlueprintTheme.brandTeal)
                .frame(width: 50, height: 50)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .unsupported:
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BlueprintTheme.warningOrange)
                .frame(width: 50, height: 50)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BlueprintTheme.warningOrange)
                .frame(width: 50, height: 50)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

#Preview("Unsupported City") {
    let viewModel = LaunchCityGateViewModel(
        locationService: UITestLocationService(location: CLLocation(latitude: 47.6062, longitude: -122.3321)),
        resolver: PreviewLaunchCityResolver(resolvedCity: ResolvedLaunchCity(city: "Seattle", stateCode: "WA", countryCode: "US"))
    )
    viewModel.supportedCities = [
        .init(city: "Austin", stateCode: "TX", displayName: "Austin, TX", citySlug: "austin-tx"),
        .init(city: "San Francisco", stateCode: "CA", displayName: "San Francisco, CA", citySlug: "san-francisco-ca")
    ]
    viewModel.state = .unsupported(.init(city: "Seattle", stateCode: "WA", displayName: "Seattle, WA", citySlug: nil, isSupported: false))
    return LaunchCityGateView(viewModel: viewModel)
        .preferredColorScheme(.dark)
}

private struct PreviewLaunchCityResolver: LaunchCityResolving {
    let resolvedCity: ResolvedLaunchCity?

    func resolveCity(for location: CLLocation) async throws -> ResolvedLaunchCity? {
        resolvedCity
    }
}
