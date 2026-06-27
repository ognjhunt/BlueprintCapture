import SwiftUI

// MARK: - BPNavBar
//
// Pushed-screen header: back chevron + centered title + optional trailing action.
// We hide the system bar and draw this so the paper look stays exact.

struct BPNavBar<Trailing: View>: View {
    let title: String
    var showsBack: Bool = true
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(.bpSans(BPType.bodyL, .semibold))
                .tracking(BPTracking.headline)
                .foregroundStyle(BP.textStrong)
                .frame(maxWidth: .infinity)
                .lineLimit(1)

            HStack(spacing: 0) {
                if showsBack {
                    Button {
                        if let onBack { onBack() } else { dismiss() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(BP.textStrong)
                            .frame(width: 44, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
                Spacer(minLength: 0)
                trailing()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Space.l)
        .background(BP.canvas)
        .overlay(alignment: .bottom) { BPDivider(color: BP.lineSoft) }
    }
}

extension BPNavBar where Trailing == EmptyView {
    init(_ title: String, showsBack: Bool = true, onBack: (() -> Void)? = nil) {
        self.init(title: title, showsBack: showsBack, onBack: onBack) { EmptyView() }
    }
}

// MARK: - BPLargeTitle
//
// Tab-root header: brass/muted eyebrow over a large title, optional trailing action.

struct BPLargeTitle<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var useDisplayFace: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.xs) {
                BPEyebrow(eyebrow, color: BP.brassDeep)
                Text(title)
                    .font(useDisplayFace ? .bpDisplay(BPType.largeTitle) : .bpSans(BPType.largeTitle, .bold))
                    .tracking(useDisplayFace ? 0 : BPTracking.headlineLarge)
                    .foregroundStyle(BP.textStrong)
            }
            Spacer(minLength: Space.m)
            trailing()
        }
    }
}

extension BPLargeTitle where Trailing == EmptyView {
    init(eyebrow: String, title: String, useDisplayFace: Bool = false) {
        self.init(eyebrow: eyebrow, title: title, useDisplayFace: useDisplayFace) { EmptyView() }
    }
}

// MARK: - Icon button (trailing actions, bell, etc.)

struct BPIconButton: View {
    let systemName: String
    var badge: Bool = false
    var tint: Color = BP.textStrong
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(BP.blockFg)
                            .frame(width: 8, height: 8)
                            .offset(x: -10, y: 12)
                    }
                }
                .contentShape(Rectangle())
        }
    }
}

/// Small text action used in nav bars ("Map", "Mark read").
struct BPTextAction: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.bpSans(BPType.bodyS, .semibold))
                .foregroundStyle(BP.brassDeep)
        }
    }
}
