import SwiftUI

struct TargetRow: View {
    let item: NearbyTargetsViewModel.NearbyItem

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 96, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.target.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.target.address ?? "Address pending…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(String(format: "%.1f", item.distanceMiles)) mi", systemImage: "location")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    skuBadge(item.target.sku)

                    Spacer()

                    Text("Est. $\(formatCurrency(item.estimatedPayoutUsd))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(item.target.sku == .B ? BlueprintTheme.primary : .primary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder private var thumbnail: some View {
        if let url = item.streetImageURL, item.hasStreetView {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                case .failure(_): placeholder
                case .empty: ProgressView()
                @unknown default: placeholder
                }
            }
        } else {
            MapSnapshotView(coordinate: item.target.coordinate)
        }
    }

    private func skuBadge(_ sku: SKU) -> some View {
        let color: Color = {
            switch sku {
            case .A: return Color.blue
            case .B: return Color.purple
            case .C: return Color.teal
            }
        }()
        return Text("SKU \(sku.rawValue)")
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
            .foregroundStyle(color)
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.1)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private func formatCurrency(_ value: Int) -> String {
        let number = NSNumber(value: value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: number) ?? "\(value)"
    }
}


