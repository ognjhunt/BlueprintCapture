import SwiftUI

struct TargetRow: View {
    let item: NearbyTargetsViewModel.NearbyItem
    let reservationSecondsRemaining: Int?
    let isOnSite: Bool
    let reservedByMe: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isReserved = reservationSecondsRemaining != nil
        ZStack(alignment: .topLeading) {
            HStack(spacing: 12) {
                thumbnail
                    .frame(width: 96, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        BlueprintTheme.primary.opacity(colorScheme == .dark ? 0.5 : 0.25),
                                        BlueprintTheme.brandTeal.opacity(colorScheme == .dark ? 0.45 : 0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
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
                            .foregroundStyle(.primary)
                            .layoutPriority(1)

                        if reservationSecondsRemaining != nil {
                            // No inline badge when reserved (top-left ribbon already indicates state)
                        } else if isOnSite {
                            onsitePill()
                        }
                    }

                    Text(item.target.address ?? "Address pending…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                        .padding(.top, -2)
                        .padding(.trailing, -20)
                        .allowsHitTesting(false)
                }

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)

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
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.15 : 0.65),
                                    BlueprintTheme.primary.opacity(colorScheme == .dark ? 0.28 : 0.18)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                    .overlay(
                        Capsule().stroke(
                            LinearGradient(
                                colors: [
                                    BlueprintTheme.primary.opacity(colorScheme == .dark ? 0.4 : 0.2),
                                    BlueprintTheme.brandTeal.opacity(colorScheme == .dark ? 0.35 : 0.18)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                    )
                    .foregroundStyle(Color.white.opacity(0.9))
                    .offset(x: -4, y: -4)
                }
            }
        }
        .background(cardBackground(isReserved: isReserved, reservedByMe: reservedByMe))
        .overlay(cardBorder(isReserved: isReserved, reservedByMe: reservedByMe))
        .overlay(alignment: .leading) {
            if isOnSite && !isReserved {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(BlueprintTheme.successGreen)
                    .frame(width: 4)
                    .opacity(0.9)
            }
        }
        .shadow(color: BlueprintTheme.primary.opacity(colorScheme == .dark ? 0.38 : 0.12), radius: 22, x: 0, y: 14)
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
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(BlueprintTheme.successGreen.opacity(0.12)))
                .overlay(Capsule().stroke(BlueprintTheme.successGreen.opacity(0.45), lineWidth: 1))
                .foregroundStyle(BlueprintTheme.successGreen)
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
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [
                                BlueprintTheme.primary.opacity(colorScheme == .dark ? 0.5 : 0.18),
                                BlueprintTheme.brandTeal.opacity(colorScheme == .dark ? 0.45 : 0.24)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .overlay(
                    Capsule().stroke(
                        LinearGradient(
                            colors: [
                                BlueprintTheme.primary.opacity(colorScheme == .dark ? 0.6 : 0.3),
                                BlueprintTheme.brandTeal.opacity(colorScheme == .dark ? 0.55 : 0.35)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(Color.white.opacity(0.95))
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
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [
                        BlueprintTheme.brandTeal.opacity(colorScheme == .dark ? 0.5 : 0.2),
                        BlueprintTheme.primary.opacity(colorScheme == .dark ? 0.55 : 0.28)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        )
        .overlay(
            Capsule().stroke(
                LinearGradient(
                    colors: [
                        BlueprintTheme.brandTeal.opacity(colorScheme == .dark ? 0.6 : 0.35),
                        BlueprintTheme.primary.opacity(colorScheme == .dark ? 0.65 : 0.4)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 1
            )
        )
        .foregroundStyle(Color.white.opacity(0.95))
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
        .padding(.horizontal, 8).padding(.vertical, 5)
        // Opaque base so overlapping the title never shows through
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [
                        BlueprintTheme.successGreen.opacity(colorScheme == .dark ? 0.55 : 0.28),
                        BlueprintTheme.payoutTeal.opacity(colorScheme == .dark ? 0.55 : 0.32)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        )
        .overlay(
            Capsule().stroke(
                LinearGradient(
                    colors: [
                        BlueprintTheme.successGreen.opacity(colorScheme == .dark ? 0.7 : 0.45),
                        BlueprintTheme.payoutTeal.opacity(colorScheme == .dark ? 0.65 : 0.5)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 1
            )
        )
        .foregroundStyle(Color.white.opacity(0.96))
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
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(
            Group {
                if isMine {
                    Capsule().fill(BlueprintTheme.reservedGradient)
                } else {
                    Capsule().fill(Color(.systemFill))
                }
            }
        )
        .overlay(
            Group {
                if !isMine { Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1) }
            }
        )
        .foregroundStyle(isMine ? .white : .secondary)
    }

    private func onsitePill() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.walk.circle.fill")
            Text("Nearby")
        }
        .font(.caption2).fontWeight(.bold)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(BlueprintTheme.successGreen.opacity(0.18)))
        .overlay(Capsule().stroke(BlueprintTheme.successGreen.opacity(0.45), lineWidth: 1))
        .foregroundStyle(BlueprintTheme.successGreen)
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.1)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
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

    private func cardBackground(isReserved: Bool, reservedByMe: Bool) -> some View {
        let colors: [Color]
        if reservedByMe {
            colors = [
                BlueprintTheme.primary.opacity(colorScheme == .dark ? 0.42 : 0.22),
                BlueprintTheme.brandTeal.opacity(colorScheme == .dark ? 0.46 : 0.28)
            ]
        } else if isReserved {
            colors = [
                Color(.systemBackground).opacity(colorScheme == .dark ? 0.25 : 0.86),
                Color(.systemBackground).opacity(colorScheme == .dark ? 0.2 : 0.78)
            ]
        } else {
            colors = [
                Color(.systemBackground).opacity(colorScheme == .dark ? 0.32 : 0.96),
                BlueprintTheme.brandTeal.opacity(colorScheme == .dark ? 0.24 : 0.12)
            ]
        }
        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func cardBorder(isReserved: Bool, reservedByMe: Bool) -> some View {
        let gradient: LinearGradient
        let width: CGFloat
        if reservedByMe {
            gradient = LinearGradient(
                colors: [BlueprintTheme.brandTeal, BlueprintTheme.primary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            width = 1.4
        } else if isReserved {
            gradient = LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.35 : 0.2),
                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            width = 1
        } else {
            gradient = LinearGradient(
                colors: [
                    BlueprintTheme.primary.opacity(colorScheme == .dark ? 0.45 : 0.18),
                    BlueprintTheme.brandTeal.opacity(colorScheme == .dark ? 0.35 : 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            width = 1
        }

        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(gradient, lineWidth: width)
    }
}

