import SwiftUI

struct CaptureSiteTypePicker: View {
    @Binding var selection: CaptureSiteType?

    var body: some View {
        Menu {
            ForEach(CaptureSiteType.allCases) { siteType in
                Button {
                    selection = siteType
                } label: {
                    Label(siteType.displayName, systemImage: siteType.systemImage)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection?.systemImage ?? "building.2.crop.circle")
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Site type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(selection?.displayName ?? "Select before recording")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selection == nil ? Color.orange.opacity(0.65) : Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }
}
