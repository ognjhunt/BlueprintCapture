import SwiftUI
import UniformTypeIdentifiers

// MARK: - Permission Data Model

/// The provenance of a `VenuePermission` record.
enum VenuePermissionSource: String, Codable, CaseIterable {
    /// Captured in-app by the operator via the authorization form.
    case capturedInApp = "captured_in_app"
    /// Imported from an existing signed-document reference.
    case importedDocument = "imported_document"
    /// Sample data for SwiftUI previews and tests only — never used for a real capture.
    case demo
}

/// Represents a signed venue capture permission/authorization.
///
/// `Codable` so a captured authorization can be persisted and threaded into the capture
/// bundle's rights metadata (`rights_consent.json`), which the pipeline reads to satisfy
/// the site-operator authorization rights gate.
struct VenuePermission: Identifiable, Codable, Equatable {
    let id: UUID
    let venueName: String
    let venueAddress: String
    let authorizedBy: String       // Authorizer name (site-operator representative)
    let authorizedTitle: String    // Their role (e.g., "Plant Manager", "Store Manager")
    let signedAt: Date             // Date the authorization was signed
    let validUntil: Date?          // Expiry; nil = no expiration
    let captureAreas: [String]     // Allowed areas (e.g., ["Receiving dock", "Pick module"])
    let restrictions: [String]     // Restrictions (e.g., ["PPE required", "LOTO zones off-limits"])
    let documentURL: URL?          // Attachment reference to the signed PDF/photo, if any
    let source: VenuePermissionSource

    var isValid: Bool {
        if let validUntil {
            return Date() < validUntil
        }
        return true
    }

    // Sample permission for SwiftUI previews and tests only — never defaulted into a real capture.
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
        documentURL: nil,
        source: .demo
    )
}

// MARK: - Permission Badge (The button you tap)

/// A simple badge that shows "Permission OK" - tap to see full details
/// Designed to be so simple a 5 year old could understand it
struct VenuePermissionBadge: View {
    let permission: VenuePermission?
    /// Called when the operator creates an authorization from the "Add authorization" flow.
    var onSave: ((VenuePermission) -> Void)? = nil
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
            VenuePermissionSheet(permission: permission, onSave: onSave)
        }
    }
}

// MARK: - Permission Sheet (What shows when you tap the badge)

/// Full-screen sheet showing the permission document
/// Big, clear, easy to show to anyone who asks
struct VenuePermissionSheet: View {
    let permission: VenuePermission?
    /// Called when the operator creates an authorization from the no-permission flow.
    var onSave: ((VenuePermission) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingForm = false

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
        .sheet(isPresented: $showingForm) {
            VenuePermissionFormView(
                venueName: permission?.venueName ?? "",
                venueAddress: permission?.venueAddress ?? ""
            ) { newPermission in
                onSave?(newPermission)
                dismiss()
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

            if onSave != nil {
                Button {
                    showingForm = true
                } label: {
                    Label("Add authorization", systemImage: "plus.circle.fill")
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())
                .padding(.horizontal, 40)
            }

            Spacer()
        }
    }
}

// MARK: - Add Authorization Form

/// Creation flow for a real, capturable site-operator authorization.
///
/// Collects the authorizer, dates, allowed areas, and restrictions — with an industrial
/// vocabulary preset — plus an optional signed-document attachment. The resulting
/// `VenuePermission` is handed back via `onSave` so it can be threaded into the capture
/// bundle's rights metadata.
struct VenuePermissionFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var venueName: String
    @State private var venueAddress: String
    @State private var authorizedBy = ""
    @State private var authorizedTitle = ""
    @State private var signedAt = Date()
    @State private var hasExpiry = false
    @State private var validUntil = Date().addingTimeInterval(86400 * 30)
    @State private var captureAreas: [String] = []
    @State private var restrictions: [String] = []
    @State private var documentURL: URL?
    @State private var documentName: String?
    @State private var isImportingDocument = false

    let onSave: (VenuePermission) -> Void

    /// Industrial-site allowed-area vocabulary presets.
    private let areaPresets = [
        "Receiving dock",
        "Pick module",
        "Staging",
        "Shipping dock",
        "Main aisle",
        "Cross-dock",
    ]

    /// Industrial-site restriction vocabulary presets.
    private let restrictionPresets = [
        "No production line access",
        "Escort required",
        "PPE required",
        "No employee break areas",
        "LOTO zones off-limits",
    ]

    init(
        venueName: String = "",
        venueAddress: String = "",
        onSave: @escaping (VenuePermission) -> Void
    ) {
        self._venueName = State(initialValue: venueName)
        self._venueAddress = State(initialValue: venueAddress)
        self.onSave = onSave
    }

    private var canSave: Bool {
        !authorizedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Authorized by") {
                    TextField("Name", text: $authorizedBy)
                        .textContentType(.name)
                    TextField("Title (e.g., Plant Manager)", text: $authorizedTitle)
                }

                Section("Venue") {
                    TextField("Venue name", text: $venueName)
                    TextField("Address", text: $venueAddress)
                }

                Section("Dates") {
                    DatePicker("Signed", selection: $signedAt, displayedComponents: .date)
                    Toggle("Has expiry date", isOn: $hasExpiry.animation())
                    if hasExpiry {
                        DatePicker("Valid until", selection: $validUntil, displayedComponents: .date)
                    }
                }

                Section("Allowed areas") {
                    VenuePermissionScopeEditor(
                        presets: areaPresets,
                        selected: $captureAreas,
                        addPlaceholder: "Add allowed area"
                    )
                }

                Section("Restrictions") {
                    VenuePermissionScopeEditor(
                        presets: restrictionPresets,
                        selected: $restrictions,
                        addPlaceholder: "Add restriction"
                    )
                }

                Section("Signed document (optional)") {
                    if let attachedName = documentName {
                        HStack {
                            Label(attachedName, systemImage: "doc.fill")
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                documentURL = nil
                                documentName = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Button {
                            isImportingDocument = true
                        } label: {
                            Label("Attach PDF or photo", systemImage: "paperclip")
                        }
                    }
                }
            }
            .navigationTitle("Add Authorization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(makePermission())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $isImportingDocument,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    documentURL = url
                    documentName = url.lastPathComponent
                }
            }
        }
    }

    private func makePermission() -> VenuePermission {
        VenuePermission(
            id: UUID(),
            venueName: venueName.trimmingCharacters(in: .whitespacesAndNewlines),
            venueAddress: venueAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            authorizedBy: authorizedBy.trimmingCharacters(in: .whitespacesAndNewlines),
            authorizedTitle: authorizedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            signedAt: signedAt,
            validUntil: hasExpiry ? validUntil : nil,
            captureAreas: captureAreas,
            restrictions: restrictions,
            documentURL: documentURL,
            source: .capturedInApp
        )
    }
}

/// Multi-select editor over a preset vocabulary plus free-form custom entries.
private struct VenuePermissionScopeEditor: View {
    let presets: [String]
    @Binding var selected: [String]
    let addPlaceholder: String

    @State private var customEntry = ""

    private var customSelections: [String] {
        selected.filter { !presets.contains($0) }
    }

    var body: some View {
        ForEach(presets, id: \.self) { preset in
            Button {
                toggle(preset)
            } label: {
                HStack {
                    Image(systemName: selected.contains(preset) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(preset) ? Color.green : Color.secondary)
                    Text(preset)
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }

        ForEach(customSelections, id: \.self) { entry in
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(entry)
                Spacer()
                Button(role: .destructive) {
                    remove(entry)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }

        HStack {
            TextField(addPlaceholder, text: $customEntry)
            Button {
                addCustom()
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(customEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func toggle(_ value: String) {
        if let index = selected.firstIndex(of: value) {
            selected.remove(at: index)
        } else {
            selected.append(value)
        }
    }

    private func remove(_ value: String) {
        selected.removeAll { $0 == value }
    }

    private func addCustom() {
        let trimmed = customEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selected.contains(trimmed) else {
            customEntry = ""
            return
        }
        selected.append(trimmed)
        customEntry = ""
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
    VenuePermissionSheet(permission: nil) { _ in }
}

#Preview("Add Authorization Form") {
    VenuePermissionFormView { _ in }
}
