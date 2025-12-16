//
//  LocationSearchSheetView.swift
//  BlueprintCapture
//
//  Created by Nijel A. Hunt on 10/30/25.
//

import SwiftUI

struct LocationSearchSheetView: View {
    @Binding var query: String
    let results: [NearbyTargetsViewModel.LocationSearchResult]
    let isSearching: Bool
    let usesGooglePlacesBranding: Bool
    let isUsingCustomSearchCenter: Bool

    let onQueryChange: (String) -> Void
    let onSelectResult: (NearbyTargetsViewModel.LocationSearchResult) -> Void
    let onUseCurrentLocation: () -> Void

    @FocusState private var isSearchFieldFocused: Bool
    @State private var animateHeroPulse = false

    private let suggestionChips = [
        "Coffee shop near me",
        "Grocery store",
        "123 Main Street"
    ]

    var body: some View {
        VStack(spacing: 24) {
            header
            content
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(background)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isSearchFieldFocused = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                animateHeroPulse = true
            }
        }
    }

    private var background: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            BlueprintTheme.heroGradient
                .opacity(0.6)
                .frame(height: 260)
                .ignoresSafeArea(edges: .top)
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchField
            if usesGooglePlacesBranding {
                HStack(spacing: 8) {
                    Image(systemName: "globe.americas.fill")
                        .foregroundStyle(BlueprintTheme.brandTeal)
                    Text("Autocomplete powered by Google Places")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(BlueprintTheme.brandTeal)

            TextField("Search another address", text: $query)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .focused($isSearchFieldFocused)
                .onChange(of: query, perform: onQueryChange)

            if !query.isEmpty {
                Button {
                    query = ""
                    onQueryChange("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .transition(.scale)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.9))
                .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BorderStyle.searchFieldStroke, lineWidth: 1)
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.8, blendDuration: 0.3), value: query.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            loadingState
        } else if !results.isEmpty {
            resultsList
        } else if query.count >= 3 {
            emptyState
        } else {
            heroState
        }

        if isUsingCustomSearchCenter {
            useCurrentLocationButton
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ForEach(Array(0..<3), id: \.self) { index in
                SearchSkeletonRow(delay: Double(index) * 0.2)
            }
            ProgressView("Searching nearby places…")
                .font(.subheadline)
                .tint(BlueprintTheme.brandTeal)
                .padding(.top, 4)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .scale))
    }

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                ForEach(results) { result in
                    Button {
                        onSelectResult(result)
                    } label: {
                        LocationSearchResultRow(result: result)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .transition(.opacity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No matches yet")
                .font(.headline)
            Text("Try broadening your search or check the spelling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private var heroState: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [BlueprintTheme.primary.opacity(0.88), BlueprintTheme.brandTeal.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: BlueprintTheme.primary.opacity(0.35), radius: 24, x: 0, y: 16)
                    .scaleEffect(animateHeroPulse ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: animateHeroPulse)

                VStack(spacing: 12) {
                    Image(systemName: "map.circle.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(.white)
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    Text("Search for a location")
                        .font(.title3.weight(.semibold))
                        .blueprintPrimaryOnDark()
                    Text("Enter a store, landmark, or street address to zero in on the perfect target area.")
                        .font(.callout)
                        .blueprintSecondaryOnDark()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 12) {
                Text("Quick suggestions")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(suggestionChips, id: \.self) { suggestion in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                query = suggestion
                            }
                            onQueryChange(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.subheadline)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemBackground))
                                        .overlay(
                                            Capsule()
                                                .stroke(BlueprintTheme.brandTeal.opacity(0.4), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .transition(.opacity)
    }

    private var useCurrentLocationButton: some View {
        Button(action: onUseCurrentLocation) {
            Label("Use my current location", systemImage: "location.fill")
                .font(.headline)
        }
        .buttonStyle(BlueprintSecondaryButtonStyle())
        .padding(.top, 12)
    }
}

// MARK: - Supporting Views

private struct SearchSkeletonRow: View {
    let delay: Double
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .frame(height: 74)
            .overlay(
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.6)
                        .overlay(
                            LinearGradient(
                                colors: [Color.white.opacity(0.0), Color.white.opacity(0.45), Color.white.opacity(0.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.55)
                            .offset(x: animate ? geo.size.width : -geo.size.width)
                            .animation(
                                .easeInOut(duration: 1.4)
                                    .delay(delay)
                                    .repeatForever(autoreverses: false),
                                value: animate
                            )
                        )
                }
            )
            .onAppear { animate = true }
    }
}

private struct LocationSearchResultRow: View {
    let result: NearbyTargetsViewModel.LocationSearchResult

    var body: some View {
        HStack(spacing: 16) {
            icon
            VStack(alignment: .leading, spacing: 6) {
                Text(result.title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(result.subtitle.isEmpty ? "Tap to set this search area" : result.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary.opacity(0.6))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(resultBackground)
    }

    private var icon: some View {
        Image(systemName: result.isEstablishment ? "building.2.fill" : "mappin.and.ellipse")
            .font(.title3)
            .frame(width: 42, height: 42)
            .background(
                Circle()
                    .fill(iconGradient)
            )
            .foregroundStyle(result.isEstablishment ? Color.white : BlueprintTheme.brandTeal)
    }

    private var iconGradient: LinearGradient {
        if result.isEstablishment {
            return BlueprintTheme.reservedGradient
        }
        return LinearGradient(
            colors: [BlueprintTheme.brandTeal.opacity(0.35), BlueprintTheme.brandTeal.opacity(0.15)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var resultBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
            )
    }
}

private enum BorderStyle {
    static let searchFieldStroke = Color.white.opacity(0.35)
}
