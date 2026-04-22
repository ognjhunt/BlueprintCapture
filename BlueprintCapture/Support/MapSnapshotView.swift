import SwiftUI
import MapKit

struct MapSnapshotView: View {
    let coordinate: CLLocationCoordinate2D
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    fallback
                }
            }
            .clipped()
            .task(id: taskKey(for: geo.size)) {
                await loadSnapshot(for: geo.size)
            }
        }
    }

    private var fallback: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "map")
                .foregroundStyle(.secondary)
        }
    }

    private func loadSnapshot(for size: CGSize) async {
        guard size.width > 0, size.height > 0 else { return }
        image = await AppleLocationPreviewService.shared.mapSnapshot(
            for: coordinate,
            size: size,
            scale: displayScale
        )
    }

    private func taskKey(for size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }
}

struct CapturePreviewView: View {
    let coordinate: CLLocationCoordinate2D
    let remoteImageURL: URL?
    var preferredAssetName: String? = nil
    @Environment(\.displayScale) private var displayScale
    @State private var preview: LocationPreviewResult?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let preferredAssetName {
                    Image(preferredAssetName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let remoteImageURL {
                    AsyncImage(url: remoteImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            localPreview(for: geo.size)
                        case .empty:
                            localPreview(for: geo.size, loading: true)
                        @unknown default:
                            localPreview(for: geo.size)
                        }
                    }
                } else {
                    localPreview(for: geo.size, loading: preview == nil)
                }
            }
            .clipped()
            .task(id: taskKey(for: geo.size)) {
                await loadPreview(for: geo.size)
            }
        }
    }

    @ViewBuilder
    private func localPreview(for size: CGSize, loading: Bool = false) -> some View {
        if let image = preview?.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if loading {
            fallbackOverlay
        } else {
            MapSnapshotView(coordinate: coordinate)
        }
    }

    private var fallbackOverlay: some View {
        ZStack {
            Color(.tertiarySystemBackground)
            ProgressView()
                .controlSize(.small)
        }
    }

    private func loadPreview(for size: CGSize) async {
        guard size.width > 0, size.height > 0 else { return }
        preview = await AppleLocationPreviewService.shared.preview(
            for: coordinate,
            size: size,
            scale: displayScale
        )
    }

    private func taskKey(for size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }
}
