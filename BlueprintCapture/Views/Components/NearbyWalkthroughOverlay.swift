//
//  NearbyWalkthroughOverlay.swift
//  BlueprintCapture
//
//  Created by Nijel A. Hunt on 10/30/25.
//

import SwiftUI
import AVFoundation
import Combine

struct NearbyWalkthroughOverlay: View {
    @Binding var isVisible: Bool
    @Binding var pageIndex: Int
    let items: [NearbyTargetsViewModel.NearbyItem]
    let currentAddress: String?
    let filterBarFrame: CGRect
    let onComplete: () -> Void

    private let totalPages = 7

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $pageIndex) {
                highlightTargetsPage
                    .tag(0)

                filtersPage
                    .tag(1)

                searchPage
                    .tag(2)

                reservePage
                    .tag(3)

                checkInPage
                    .tag(4)

                mappingTipsPage
                    .tag(5)

                payoutPage
                    .tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Button(pageIndex == totalPages - 1 ? "Done" : "Skip") {
                finish()
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
            .padding(.top, 40)
            .padding(.trailing, 24)

            // Custom page indicator – centered near the bottom to hint scrollability
            VStack { Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    pageIndicator
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 96)
                }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: pageIndex)
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isVisible = false
        }
        onComplete()
    }
}

// MARK: - Individual pages

private extension NearbyWalkthroughOverlay {
    // Always-visible custom page indicator positioned by the caller via overlay
    var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { idx in
                Capsule(style: .continuous)
                    .fill(idx == pageIndex ? BlueprintTheme.brandTeal : Color.white.opacity(0.45))
                    .frame(width: idx == pageIndex ? 18 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: pageIndex)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.9)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    var highlightTargetsPage: some View {
        GeometryReader { geo in
            walkthroughBackdrop
                .overlay(alignment: .top) {
                    VStack(spacing: 24) {
                        Spacer().frame(height: geo.size.height * 0.18)

                        highlightBox(height: geo.size.height * 0.38)
                            .overlay(
                                VStack(spacing: 12) {
                                    ForEach(Array(items.prefix(2))) { item in
                                        TargetRow(
                                            item: item,
                                            reservationSecondsRemaining: nil,
                                            isOnSite: false,
                                            reservedByMe: false
                                        )
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                    }
                                    if items.isEmpty {
                                        placeholderTargetRows
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 4)
                            )
                            .padding(.horizontal, 20)

                        calloutCard(
                            icon: "map.fill",
                            title: "Explore highlighted targets",
                            message: "These cards show nearby spaces we recommend scanning. Each cell lists the full address, how long the walkthrough should take, and what you’re estimated to earn."
                        )
                        .padding(.horizontal, 24)

                        Spacer()
                    }
                }
        }
    }

    var filtersPage: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Dark backdrop with a transparent hole over the actual FilterBar frame
                let globalFrame = geo.frame(in: .global)
                let localRect: CGRect = CGRect(
                    x: filterBarFrame.minX - globalFrame.minX,
                    y: filterBarFrame.minY - globalFrame.minY,
                    width: filterBarFrame.width,
                    height: filterBarFrame.height
                )

                walkthroughBackdrop
                    .overlay {
                        if filterBarFrame.height > 0 {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .frame(width: localRect.width, height: localRect.height)
                                .position(x: localRect.midX, y: localRect.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                    .overlay {
                        if filterBarFrame.height > 0 {
                            // Subtle ring to emphasize the spotlight area
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.55), lineWidth: 2)
                                .frame(width: localRect.width, height: localRect.height)
                                .position(x: localRect.midX, y: localRect.midY)
                        }
                    }

                VStack(spacing: 28) {
                    Spacer().frame(height: max(geo.safeAreaInsets.top + 20, (filterBarFrame.maxY - globalFrame.minY) + 16))

                    calloutCard(
                        icon: "slider.horizontal.3",
                        title: "Dial in your filters",
                        message: "Use distance, payout, and demand filters to surface the perfect target list for your day."
                    )
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
        }
    }

    var searchPage: some View {
        GeometryReader { geo in
            walkthroughBackdrop
                .overlay(alignment: .top) {
                    VStack(spacing: 24) {
                        // Position highlight directly over the current address chip
                        Spacer().frame(height: geo.safeAreaInsets.top + 16)

                        highlightBox(height: 70)
                            .padding(.horizontal, 20)
                            .overlay(
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(BlueprintTheme.brandTeal)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(currentAddress ?? "1005, Crete St, Durham, NC")
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(.white)
                                        Text("Tap \"Change\" to search other areas")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    Spacer()
                                    Capsule()
                                        .fill(BlueprintTheme.primary.opacity(0.18))
                                        .overlay(
                                            Label("Change", systemImage: "magnifyingglass")
                                                .font(.caption)
                                                .foregroundStyle(BlueprintTheme.primary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                        )
                                        .frame(height: 32)
                                }
                                .padding(.horizontal, 18)
                            )

                        calloutCard(
                            icon: "magnifyingglass",
                            title: "Search any city",
                            message: "Heading somewhere new? Update the address to see earning opportunities wherever you’re traveling next."
                        )
                        .padding(.horizontal, 24)

                        Spacer()
                    }
                }
        }
    }

    var reservePage: some View {
        GeometryReader { geo in
            walkthroughBackdrop
                .overlay {
                    VStack(spacing: 24) {
                        Spacer().frame(height: geo.size.height * 0.18)

                        calloutCard(
                            icon: "checkmark.seal.fill",
                            title: "Reserve when you need to",
                            message: "Tap a target, choose **Reserve**, and we’ll hold it for up to an hour so no one else claims it while you’re en route."
                        )
                        .padding(.horizontal, 24)

                        highlightBox(height: 160)
                            .overlay(reservePreview)
                            .padding(.horizontal, 30)

                        Spacer()
                    }
                }
        }
    }

    var checkInPage: some View {
        GeometryReader { geo in
            walkthroughBackdrop
                .overlay(alignment: .bottom) {
                    VStack(spacing: 24) {
                        Spacer()

                        highlightBox(height: 160)
                            .overlay(checkInPreview)
                            .padding(.horizontal, 30)

                        calloutCard(
                            icon: "location.fill",
                            title: "Ready on-site? Check in",
                            message: "Whether you reserved or not, tap **Check In & Start Mapping** to launch the camera and begin your walkthrough."
                        )
                        .padding(.horizontal, 24)

                        Spacer().frame(height: geo.safeAreaInsets.bottom + 40)
                    }
                }
        }
    }

    var mappingTipsPage: some View {
        GeometryReader { _ in
            ZStack {
                WalkthroughCameraBackdrop()
                Color.black.opacity(0.55).ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer().frame(height: 80)

                    calloutCard(
                        icon: "viewfinder",
                        title: "Capture every detail",
                        message: "Move slowly with the camera pointed forward. Walk down and back each aisle so the entire space is captured clearly. Quality beats speed every time."
                    )
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
        }
    }

    var payoutPage: some View {
        GeometryReader { geo in
            walkthroughBackdrop
                .overlay(alignment: .bottom) {
                    VStack(spacing: 24) {
                        Spacer()

                        calloutCard(
                            icon: "dollarsign.circle.fill",
                            title: "Get paid for quality",
                            message: "Expect payouts within 2–3 days. Final earnings depend on video quality, demand for the space, and the size of your scan. Repeated low-quality uploads can pause your access—so take your time and do it right."
                        )
                        .padding(.horizontal, 24)

                        highlightBox(height: 70)
                            .padding(.horizontal, 60)
                            .overlay(
                                HStack(spacing: 16) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.title3)
                                        .foregroundStyle(BlueprintTheme.brandTeal)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Track status later in Settings")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                        Text("We’ll notify you as soon as a payout is ready.")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                            )

                        Spacer().frame(height: geo.safeAreaInsets.bottom + 44)
                    }
                }
        }
    }
}

// MARK: - Shared helpers

private extension NearbyWalkthroughOverlay {
    var walkthroughBackdrop: some View {
        Color.black.opacity(0.65)
            .ignoresSafeArea()
    }

    func highlightBox(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .frame(height: height)
            .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 12)
    }

    func calloutCard(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            } icon: {
                Image(systemName: icon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BlueprintTheme.brandTeal)
                    .font(.title2.weight(.semibold))
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.85)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    var placeholderTargetRows: some View {
        VStack(spacing: 12) {
            ForEach(0..<2) { idx in
                HStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 72, height: 56)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.4))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.25))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(BlueprintTheme.brandTeal.opacity(0.45))
                            .frame(width: 120, height: 12)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .opacity(idx == 0 ? 1 : 0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    func filterChipRow(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    var reservePreview: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reserve target")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Hold this spot for the next hour while you travel.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "hourglass")
                    .font(.title2)
                    .foregroundStyle(BlueprintTheme.brandTeal)
            }
            .padding(.horizontal, 24)

            Capsule()
                .fill(BlueprintTheme.brandTeal)
                .frame(height: 52)
                .overlay(
                    Text("Reserve")
                        .font(.headline)
                        .foregroundStyle(.white)
                )
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 20)
    }

    var checkInPreview: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(width: 60, height: 6)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 12) {
                Text("Cold Water No Bleach")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("0.2 mi • Est. 1h 15m walk-through")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Capsule()
                .fill(BlueprintTheme.brandTeal)
                .frame(height: 56)
                .overlay(
                    Label("Check In & Start Mapping", systemImage: "record.circle")
                        .font(.headline)
                        .foregroundStyle(.white)
                )
                .padding(.horizontal, 24)

            Spacer().frame(height: 16)
        }
    }
}

// MARK: - Camera backdrop

private struct WalkthroughCameraBackdrop: View {
    @StateObject private var cameraController = WalkthroughCameraController()

    var body: some View {
        ZStack {
            LiveCameraPreview(session: cameraController.session)
                .ignoresSafeArea()
        }
        .onAppear {
            cameraController.start()
        }
        .onDisappear {
            cameraController.stop()
        }
    }
}

private final class WalkthroughCameraController: ObservableObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.blueprint.walkthrough.camera", qos: .userInitiated)

    func start() {
        queue.async {
            if self.session.inputs.isEmpty {
                self.configureSession()
            }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        do {
            if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                let input = try AVCaptureDeviceInput(device: videoDevice)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            }
        } catch {
            print("⚠️ Walkthrough camera preview failed: \(error.localizedDescription)")
        }

        session.commitConfiguration()
    }
}

private struct LiveCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.session = session
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set { previewLayer.session = newValue }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}
