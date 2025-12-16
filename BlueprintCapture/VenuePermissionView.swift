import SwiftUI

// MARK: - Permission Data Model

/// Represents a signed venue capture permission/authorization
struct VenuePermission: Identifiable {
    let id: UUID
    let venueName: String
    let venueAddress: String
    let authorizedBy: String       // Name of person who signed
    let authorizedTitle: String    // Their role (e.g., "Store Manager")
    let signedAt: Date
    let validUntil: Date?          // nil = no expiration
    let captureAreas: [String]     // e.g., ["Sales floor", "Aisles", "Entrance"]
    let restrictions: [String]     // e.g., ["No back office", "No registers"]
    let documentURL: URL?          // Link to actual signed PDF if available

    var isValid: Bool {
        if let validUntil {
            return Date() < validUntil
        }
        return true
    }

    // Demo permission for testing
    static let demo = VenuePermission(
        id: UUID(),
        venueName: "Fresh Market Grocery",
        venueAddress: "123 Main Street, San Francisco, CA",
        authorizedBy: "Sarah Johnson",
        authorizedTitle: "Store Manager",
        signedAt: Date().addingTimeInterval(-86400 * 3), // 3 days ago
        validUntil: Date().addingTimeInterval(86400 * 30), // 30 days from now
        captureAreas: ["Sales floor", "All aisles", "Entrance area"],
        restrictions: ["No employee areas", "No cash registers", "No restrooms"],
        documentURL: nil
    )
}

// MARK: - Permission Badge (The button you tap)

/// A simple badge that shows "Permission OK" - tap to see full details
/// Designed to be so simple a 5 year old could understand it
struct VenuePermissionBadge: View {
    let permission: VenuePermission?
    @State private var showingPermission = false

    var body: some View {
        Button {
            showingPermission = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: permission != nil ? "checkmark.shield.fill" : "shield.fill")
                    .font(.system(size: 16, weight: .semibold))

                Text(permission != nil ? "OK" : "Permission")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(permission != nil ? Color.green : Color.orange)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            )
        }
        .sheet(isPresented: $showingPermission) {
            VenuePermissionSheet(permission: permission)
        }
    }
}

// MARK: - Permission Sheet (What shows when you tap the badge)

/// Full-screen sheet showing the permission document
/// Big, clear, easy to show to anyone who asks
struct VenuePermissionSheet: View {
    let permission: VenuePermission?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()

                if let permission {
                    authorizedView(permission)
                } else {
                    noPermissionView
                }
            }
            .navigationTitle("Capture Permission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Authorized View (Permission exists)

    private func authorizedView(_ permission: VenuePermission) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Big green checkmark - unmistakably "OK"
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 120, height: 120)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.green)
                    }

                    Text("Authorized to Record")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.green)

                    Text("This capture has been approved")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Venue info card
                VStack(alignment: .leading, spacing: 16) {
                    // Venue name - BIG
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VENUE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(permission.venueName)
                            .font(.title2.weight(.bold))
                        Text(permission.venueAddress)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Who authorized
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AUTHORIZED BY")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(permission.authorizedBy)
                            .font(.headline)
                        Text(permission.authorizedTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // When signed
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DATE SIGNED")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(permission.signedAt, style: .date)
                            .font(.headline)
                    }

                    // Valid until (if applicable)
                    if let validUntil = permission.validUntil {
                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("VALID UNTIL")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(validUntil, style: .date)
                                    .font(.headline)
                                if permission.isValid {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal)

                // Allowed areas
                if !permission.captureAreas.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Allowed Areas", systemImage: "checkmark.circle")
                            .font(.headline)
                            .foregroundStyle(.green)

                        ForEach(permission.captureAreas, id: \.self) { area in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                                    .frame(width: 24)
                                Text(area)
                                    .font(.body)
                                Spacer()
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.green.opacity(0.1))
                    )
                    .padding(.horizontal)
                }

                // Restrictions
                if !permission.restrictions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Restricted Areas", systemImage: "xmark.circle")
                            .font(.headline)
                            .foregroundStyle(.red)

                        ForEach(permission.restrictions, id: \.self) { restriction in
                            HStack(spacing: 12) {
                                Image(systemName: "xmark")
                                    .foregroundStyle(.red)
                                    .frame(width: 24)
                                Text(restriction)
                                    .font(.body)
                                Spacer()
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.red.opacity(0.1))
                    )
                    .padding(.horizontal)
                }

                // View full document button (if available)
                if permission.documentURL != nil {
                    Button {
                        // Would open the PDF/document
                    } label: {
                        Label("View Full Agreement", systemImage: "doc.text")
                    }
                    .buttonStyle(BlueprintSecondaryButtonStyle())
                    .padding(.horizontal)
                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - No Permission View

    private var noPermissionView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
            }

            Text("No Permission on File")
                .font(.title2.weight(.bold))

            Text("This capture does not have a recorded venue permission. Please ensure you have authorization before recording.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Badge - Has Permission") {
    ZStack {
        Color.black.ignoresSafeArea()
        VenuePermissionBadge(permission: .demo)
    }
}

#Preview("Badge - No Permission") {
    ZStack {
        Color.black.ignoresSafeArea()
        VenuePermissionBadge(permission: nil)
    }
}

#Preview("Sheet - Has Permission") {
    VenuePermissionSheet(permission: .demo)
}

#Preview("Sheet - No Permission") {
    VenuePermissionSheet(permission: nil)
}
