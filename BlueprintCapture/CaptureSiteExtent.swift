import Foundation
import SwiftUI
import UIKit

struct CaptureSiteExtent: Equatable {
    let approximateFloorAreaM2: Double?
    let ceilingHeightM: Double?
    let floorCount: Int?
    let dominantAisleWidthM: Double?
    let siteScaleClass: String?

    var hasDeclaredDimension: Bool {
        approximateFloorAreaM2 != nil ||
            ceilingHeightM != nil ||
            floorCount != nil ||
            dominantAisleWidthM != nil
    }

    var status: String {
        if hasDeclaredDimension {
            return "capturer_declared_review_required"
        }
        if siteScaleClass != nil {
            return "coarse_site_scale_class_only_review_required"
        }
        return "not_provided"
    }

    var source: String {
        if hasDeclaredDimension {
            return "capturer_declared"
        }
        if siteScaleClass != nil {
            return "capturer_selected_site_scale_class"
        }
        return "not_provided"
    }

    var manifestPayload: [String: Any] {
        var payload: [String: Any] = [
            "status": status,
            "source": source,
            "claim_boundary": "site_extent_is_capturer_recorded_context_not_verified_measurement"
        ]
        if let approximateFloorAreaM2 {
            payload["approx_floor_area_m2"] = approximateFloorAreaM2
        }
        if let ceilingHeightM {
            payload["ceiling_height_m"] = ceilingHeightM
        }
        if let floorCount {
            payload["floor_count"] = floorCount
        }
        if let dominantAisleWidthM {
            payload["dominant_aisle_width_m"] = dominantAisleWidthM
        }
        if let siteScaleClass {
            payload["site_scale_class"] = siteScaleClass
        }
        return payload
    }

    func apply(to manifest: inout [String: Any]) {
        manifest["site_extent"] = manifestPayload
        manifest["site_extent_status"] = status
        manifest["site_extent_source"] = source
        if let approximateFloorAreaM2 {
            manifest["approx_floor_area_m2"] = approximateFloorAreaM2
        }
        if let ceilingHeightM {
            manifest["ceiling_height_m"] = ceilingHeightM
        }
        if let floorCount {
            manifest["floor_count"] = floorCount
        }
        if let dominantAisleWidthM {
            manifest["dominant_aisle_width_m"] = dominantAisleWidthM
        }
        if let siteScaleClass {
            manifest["site_scale_class"] = siteScaleClass
        }
    }
}

struct CaptureSiteExtentFormState: Equatable {
    var floorAreaM2 = ""
    var ceilingHeightM = ""
    var floorCount = ""
    var dominantAisleWidthM = ""

    func makeExtent(siteScaleClass: String?) -> CaptureSiteExtent {
        CaptureSiteExtent(
            approximateFloorAreaM2: Self.positiveDouble(from: floorAreaM2),
            ceilingHeightM: Self.positiveDouble(from: ceilingHeightM),
            floorCount: Self.positiveInt(from: floorCount),
            dominantAisleWidthM: Self.positiveDouble(from: dominantAisleWidthM),
            siteScaleClass: siteScaleClass
        )
    }

    private static func positiveDouble(from text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private static func positiveInt(from text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard let value = Int(normalized), value > 0 else { return nil }
        return value
    }
}

struct CaptureSiteExtentEditor: View {
    @Binding var form: CaptureSiteExtentFormState
    var compact = false

    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text("Site dimensions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
            LazyVGrid(columns: columns, spacing: 8) {
                dimensionField("Area m2", text: $form.floorAreaM2, keyboard: .decimalPad)
                dimensionField("Ceiling m", text: $form.ceilingHeightM, keyboard: .decimalPad)
                dimensionField("Floors", text: $form.floorCount, keyboard: .numberPad)
                dimensionField("Aisle m", text: $form.dominantAisleWidthM, keyboard: .decimalPad)
            }
            Text("Optional approximate values. Missing fields stay marked for review.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.56))
        }
    }

    private func dimensionField(
        _ placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
