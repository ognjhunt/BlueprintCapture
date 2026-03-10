import SwiftUI
import UIKit

struct ShareSheetItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ManualIntakeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CaptureManualIntakeDraft
    let title: String
    let onSubmit: (CaptureManualIntakeDraft) -> Void

    init(title: String = "Complete Intake", draft: CaptureManualIntakeDraft, onSubmit: @escaping (CaptureManualIntakeDraft) -> Void) {
        self.title = title
        self._draft = State(initialValue: draft)
        self.onSubmit = onSubmit
    }

    private var isComplete: Bool {
        let packet = draft.makePacket()
        return packet.isComplete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Why this is needed") {
                    Text(draft.helperText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Workflow") {
                    TextField("Workflow name", text: $draft.workflowName)
                    TextEditor(text: $draft.taskStepsText)
                        .frame(minHeight: 120)
                }

                Section("Zone or Owner") {
                    TextField("Zone", text: $draft.zone)
                    TextField("Owner", text: $draft.owner)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continue") {
                        onSubmit(draft)
                        dismiss()
                    }
                    .disabled(!isComplete)
                }
            }
        }
    }
}
