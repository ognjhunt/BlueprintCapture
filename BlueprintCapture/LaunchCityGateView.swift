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
        if let websiteURL = AppConfig.mainWebsiteURL() {
            var components = URLComponents(
                url: websiteURL.appendingPathComponent("capture-app/launch-access"),
                resolvingAgainstBaseURL: false
            )
            var queryItems = [URLQueryItem(name: "source", value: "ios-capture-app-launch-gate")]
            if let resolvedCity = viewModel.resolvedCity?.displayName {
                queryItems.append(URLQueryItem(name: "city", value: resolvedCity))
            }
            components?.queryItems = queryItems
            return components?.url
        }

        return AppConfig.helpCenterURL()
            ?? AppConfig.supportEmailURL(subject: "Request launch access")
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = LaunchCityGateLayoutMetrics(containerWidth: proxy.size.width)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header(metrics: metrics)
                        .padding(.top, metrics.headerTopPadding)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 22)

                    statusCard(metrics: metrics)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    liveCitiesCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom) {
                footerActions
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                    .background(
                        Rectangle()
                            .fill(Color.black.opacity(0.92))
                            .ignoresSafeArea(edges: .bottom)
                    )
            }
            .blueprintAppBackground()
        }
    }

    private func header(metrics: LaunchCityGateLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Blueprint city launch")
                .font(BlueprintTheme.body(12, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textTertiary)
                .tracking(2.0)
                .lineLimit(1)

            Text("We’re only live in a few cities right now.")
                .font(BlueprintTheme.display(metrics.heroTitleSize, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text("Your location determines whether the capture network unlocks. Launch availability follows Blueprint's active city program.")
                .font(BlueprintTheme.body(15, weight: .medium))
                .foregroundStyle(BlueprintTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func statusCard(metrics: LaunchCityGateLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if metrics.usesVerticalStatusLayout {
                VStack(alignment: .leading, spacing: 14) {
                    statusIcon

                    VStack(alignment: .leading, spacing: 6) {
                        Text(statusTitle)
                            .font(BlueprintTheme.display(metrics.statusTitleSize, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textPrimary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(statusMessage)
                            .font(BlueprintTheme.body(14, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    statusIcon

                    VStack(alignment: .leading, spacing: 6) {
                        Text(statusTitle)
                            .font(BlueprintTheme.display(metrics.statusTitleSize, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textPrimary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(statusMessage)
                            .font(BlueprintTheme.body(14, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let resolvedCity = viewModel.resolvedCity,
               case .unsupported = viewModel.state {
                HStack(spacing: 8) {
                    Image(systemName: "location.circle.fill")
                        .foregroundStyle(BlueprintTheme.textSecondary)
                    Text("Detected: \(resolvedCity.displayName)")
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                }
            }

            if case .checking = viewModel.state {
                ProgressView()
                    .tint(BlueprintTheme.textPrimary)
            }
        }
        .padding(22)
        .blueprintEditorialCard(radius: 24, fill: BlueprintTheme.panel)
    }

    private var liveCitiesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Supported cities")
                .font(BlueprintTheme.body(14, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)

            Text(viewModel.supportedCities.isEmpty
                 ? "We’ll show supported launch cities as soon as availability syncs."
                 : "These cities are synced from Blueprint's current launch program.")
                .font(BlueprintTheme.body(13, weight: .medium))
                .foregroundStyle(BlueprintTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(viewModel.supportedCities) { city in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(city.displayName)
                            .font(BlueprintTheme.body(15, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textPrimary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Launch market")
                            .font(BlueprintTheme.body(12, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BlueprintTheme.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .blueprintPanelBackground(radius: 16, fill: BlueprintTheme.panelMuted)
            }
        }
        .padding(22)
        .blueprintEditorialCard(radius: 24, fill: BlueprintTheme.panel)
    }

    private var footerActions: some View {
        VStack(spacing: 12) {
            primaryAction

            Button {
                viewModel.refresh()
            } label: {
                Text("Check again")
                    .font(BlueprintTheme.body(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .blueprintPanelBackground(radius: 16, fill: BlueprintTheme.panelStrong)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BlueprintTheme.textPrimary)
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
            .font(BlueprintTheme.body(16, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
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
                .foregroundStyle(BlueprintTheme.textPrimary)
                .frame(width: 50, height: 50)
                .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .locationPermissionRequired, .locationPermissionDenied:
            Image(systemName: "location.slash.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)
                .frame(width: 50, height: 50)
                .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .supported:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)
                .frame(width: 50, height: 50)
                .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .unsupported:
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)
                .frame(width: 50, height: 50)
                .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)
                .frame(width: 50, height: 50)
                .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct LaunchCityGateLayoutMetrics: Equatable {
    let containerWidth: CGFloat

    var isCompactWidth: Bool { containerWidth <= 400 }
    var heroTitleSize: CGFloat { isCompactWidth ? 32 : 38 }
    var statusTitleSize: CGFloat { isCompactWidth ? 20 : 24 }
    var headerTopPadding: CGFloat { isCompactWidth ? 52 : 68 }
    var usesVerticalStatusLayout: Bool { isCompactWidth }
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
