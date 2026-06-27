import SwiftUI
import UIKit

// MARK: - BPFacilityImage
//
// Grayscale facility photography (assignment thumbnails, capture-path hero).
// Placeholder POV imagery from the handoff; swap for real assignment photos.

struct BPFacilityImage: View {
    let name: String
    var height: CGFloat? = nil
    var corner: CGFloat = Radius.md

    var body: some View {
        Group {
            if let ui = UIImage(named: name) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .grayscale(1)
                    .overlay(BP.ink.opacity(0.06))
            } else {
                ZStack {
                    BP.sunken
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(BP.textFaint)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(BP.line, lineWidth: 1)
        )
    }
}
