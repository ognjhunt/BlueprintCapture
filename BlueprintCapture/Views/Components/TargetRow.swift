import SwiftUI

struct TargetRow: View {
    let item: NearbyTargetsViewModel.NearbyItem
    let reservationSecondsRemaining: Int?
    let isOnSite: Bool
    let reservedByMe: Bool

    var body: some View {
        let isReserved = reservationSecondsRemaining != nil
        let cardBackground: LinearGradient = {
            if isReserved {
                if reservedByMe {
                    return LinearGradient(
                        colors: [
                            BlueprintTheme.primary.opacity(0.3),
                            BlueprintTheme.accentAqua.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    return LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            Color.white.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            } else {
                return LinearGradient(
                    colors: [
                        Color.white.opacity(0.98),
                        BlueprintTheme.primary.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }()

        let borderGradient: LinearGradient = {
            if isReserved && reservedByMe {
                return LinearGradient(
                    colors: [Color.white.opacity(0.45), Color.white.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                return LinearGradient(
                    colors: [BlueprintTheme.primary.opacity(0.25), BlueprintTheme.accentAqua.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }()
        let primaryTextColor: Color = isReserved && reservedByMe ? .white : .primary
        let secondaryTextColor: Color = isReserved && reservedByMe ? Color.white.opacity(0.8) : .secondary
        let chevronColor: Color = isReserved && reservedByMe ? Color.white.opacity(0.7) : Color.secondary
        ZStack(alignment: .topLeading) {
            HStack(spacing: 12) {
                thumbnail
                    .frame(width: 96, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                    )
                    .overlay(alignment: .bottomLeading) {
                        if let seconds = reservationSecondsRemaining {
                            reservedPill(seconds: seconds, isMine: reservedByMe)
                                .padding(.leading, 4)
                                .padding(.bottom, 4)
                        }
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.target.displayName)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(primaryTextColor)
                            .layoutPriority(1)

                        if reservationSecondsRemaining != nil {
                            // No inline badge when reserved (top-left ribbon already indicates state)
                        } else if isOnSite {
                            onsitePill()
                        }
                    }

                    Text(item.target.address ?? "Address pending…")
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        distanceView()
                            .layoutPriority(0)

                        timeBadge()
                            .layoutPriority(0)

                        Spacer()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // Float payout badge above content so the name can use full width
                    payoutBadge()
                        .padding(.top, -6)
                        .padding(.trailing, -24)
                        .allowsHitTesting(false)
                }

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(chevronColor)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)

            if isReserved {
                // Corner ribbon accent for reserved state
                if reservedByMe {
                    Text("Reserved")
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            Capsule().fill(BlueprintTheme.reservedGradient)
                        )
                        .foregroundStyle(.white)
                        .offset(x: -4, y: -4)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                        Text("Held")
                    }
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            LinearGradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0.16)], startPoint: .leading, endPoint: .trailing)
                        )
                    )
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .offset(x: -4, y: -4)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderGradient, lineWidth: 1)
        )
        .overlay(
            Group {
                if isReserved && reservedByMe {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(BlueprintTheme.reservedGradient, lineWidth: 1.4)
                }
            }
        )
        .overlay(alignment: .leading) {
            if isOnSite && !isReserved {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(BlueprintTheme.successGreen)
                    .frame(width: 5)
                    .opacity(0.95)
            }
        }
        .shadow(color: BlueprintTheme.primary.opacity(0.22), radius: 18, x: 0, y: 10)
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

    private func distanceView() -> some View {
        if isOnSite {
            return AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                    Text("Nearby")
                        .lineLimit(1)
                }
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        LinearGradient(colors: [BlueprintTheme.successGreen, BlueprintTheme.successGreenDeep], startPoint: .leading, endPoint: .trailing)
                    )
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            )
        } else {
            return AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "location")
                    Text("\(String(format: "%.1f", item.distanceMiles)) mi")
                        .lineLimit(1)
                }
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        LinearGradient(colors: [BlueprintTheme.primary.opacity(0.6), BlueprintTheme.accentAqua.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                    )
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            )
        }
    }

    private func timeBadge() -> some View {
        let minutes = estimatedScanTimeMinutes(for: item.target)
        let timeText = formatDuration(minutes)
        return HStack(spacing: 4) {
            Image(systemName: "clock")
            HStack(spacing: 2) {
                Text("Scan")
                    .fontWeight(.medium)
                Text(timeText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .font(.caption).fontWeight(.semibold)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            Capsule().fill(
                LinearGradient(colors: [BlueprintTheme.primary, BlueprintTheme.accentAqua], startPoint: .leading, endPoint: .trailing)
            )
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        .foregroundStyle(Color.white)
        .accessibilityLabel("Estimated scan time \(timeText)")
        .accessibilityHint("Approximate time required to complete this capture")
        .fixedSize(horizontal: true, vertical: false)
        .lineLimit(1)
        .minimumScaleFactor(0.9)
    }

    private func payoutBadge() -> some View {
        let payoutText = "Est. $\(formatCurrency(item.estimatedPayoutUsd))"
        return HStack(spacing: 6) {
            Image(systemName: "dollarsign.circle")
            Text(payoutText)
                .lineLimit(1)
        }
        .font(.caption2).fontWeight(.bold)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            Capsule().fill(
                LinearGradient(colors: [BlueprintTheme.successGreen, BlueprintTheme.payoutTeal], startPoint: .leading, endPoint: .trailing)
            )
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
        .foregroundStyle(Color.white)
        .fixedSize(horizontal: true, vertical: false)
        .lineLimit(1)
        .minimumScaleFactor(0.95)
        .accessibilityLabel("Estimated payout \(payoutText)")
    }

    private func reservedPill(seconds: Int, isMine: Bool) -> some View {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        let text = String(format: "%02d:%02d", mins, secs)
        return HStack(spacing: 4) {
            Image(systemName: "clock.badge.checkmark")
            Text(text)
                .monospacedDigit()
        }
        .font(.caption2).fontWeight(.bold)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            Group {
                if isMine {
                    Capsule().fill(LinearGradient(colors: [BlueprintTheme.primary, BlueprintTheme.brandTeal], startPoint: .leading, endPoint: .trailing))
                } else {
                    Capsule().fill(Color.white.opacity(0.22))
                }
            }
        )
        .overlay(
            Group {
                if !isMine { Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1) }
            }
        )
        .foregroundStyle(isMine ? Color.white : Color.white.opacity(0.85))
    }

    private func onsitePill() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.walk.circle.fill")
            Text("Nearby")
        }
        .font(.caption2).fontWeight(.bold)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(
            Capsule().fill(
                LinearGradient(colors: [BlueprintTheme.successGreen, BlueprintTheme.successGreenDeep], startPoint: .leading, endPoint: .trailing)
            )
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
        .foregroundStyle(Color.white)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [BlueprintTheme.primary.opacity(0.2), BlueprintTheme.brandTeal.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "photo")
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }

    private func reservationOwnerBadge() -> some View {
        HStack(spacing: 6) {
            Image(systemName: reservedByMe ? "person.fill.checkmark" : "lock.fill")
            Text(reservedByMe ? "Yours" : "Held")
                .lineLimit(1)
        }
        .font(.caption2).fontWeight(.semibold)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            Capsule().fill(reservedByMe ? BlueprintTheme.successGreen.opacity(0.16) : Color(.systemFill))
        )
        .overlay(
            Capsule().stroke(reservedByMe ? BlueprintTheme.successGreen.opacity(0.45) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .foregroundStyle(reservedByMe ? BlueprintTheme.successGreen : .secondary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func formatCurrency(_ value: Int) -> String {
        let number = NSNumber(value: value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: number) ?? "\(value)"
    }
}


