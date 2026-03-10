import SwiftUI

struct QualificationIntakeView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create a site submission")
                        .font(.largeTitle.weight(.bold))
                        .blueprintGradientText()
                    Text("Capture operator-owned evidence for a real task zone, not a nearby listing.")
                        .font(.callout)
                        .blueprintSecondaryOnDark()
                }

                BlueprintGlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Site")
                            .font(.headline)
                        Picker("Buyer type", selection: draftBinding(\.buyerType)) {
                            ForEach(BuyerType.allCases) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        QualificationTextField(title: "Site name", text: draftBinding(\.siteName), prompt: "Example: Line 2 packaging cell")
                        QualificationTextField(title: "Target robot team (optional)", text: draftBinding(\.targetRobotTeam), prompt: "Example: Internal AMR team")
                        QualificationTextEditor(title: "Operating constraints", text: draftBinding(\.operatingConstraints), prompt: "Hours, safety rules, no-go periods, or facility access constraints.")
                        QualificationTextEditor(title: "Known blockers", text: draftBinding(\.knownBlockers), prompt: "Anything already visible that may block qualification.")
                    }
                }

                BlueprintGlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Task")
                            .font(.headline)
                        QualificationTextEditor(title: "Task statement", text: draftBinding(\.taskStatement), prompt: "Describe the exact workflow under evaluation.")
                        QualificationTextEditor(title: "Workflow context", text: draftBinding(\.workflowContext), prompt: "What happens before, during, and after this task?")
                    }
                }

                BlueprintGlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Task zone and restrictions")
                            .font(.headline)
                        QualificationTextField(title: "Task-zone label", text: draftBinding(\.taskZoneName), prompt: "Example: inbound pallet handoff")
                        QualificationTextEditor(title: "Workcell / task-zone boundaries", text: draftBinding(\.taskZoneBoundaryNotes), prompt: "Describe the physical edges and surfaces in scope.")
                        QualificationTextEditor(title: "Adjacent workflow", text: draftBinding(\.adjacentWorkflowNotes), prompt: "What neighboring motion, traffic, or handoffs matter?")
                        QualificationTextEditor(title: "Privacy / security restrictions", text: draftBinding(\.privacySecurityNotes), prompt: "Call out restricted areas, masked zones, or no-capture rules.")
                    }
                }

                Button {
                    viewModel.continueFromIntake()
                } label: {
                    Text("Continue to site location")
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())
                .disabled(!viewModel.canContinueFromIntake)
            }
            .padding()
        }
        .blueprintAppBackground()
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<SiteSubmissionDraft, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.submissionDraft[keyPath: keyPath] },
            set: { viewModel.submissionDraft[keyPath: keyPath] = $0 }
        )
    }
}

struct CaptureReviewView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review capture pass")
                        .font(.largeTitle.weight(.bold))
                        .blueprintGradientText()
                    Text("Confirm the checklist and coverage before recording the task zone.")
                        .font(.callout)
                        .blueprintSecondaryOnDark()
                }

                BlueprintGlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.submissionDraft.siteName)
                            .font(.headline)
                        Text(viewModel.submissionDraft.taskStatement)
                            .font(.subheadline)
                            .blueprintSecondaryOnDark()
                        Divider()
                        Label(viewModel.submissionDraft.siteLocation, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                        Text("Submission \(viewModel.submissionDraft.submissionId)")
                            .font(.caption)
                            .blueprintSecondaryOnDark()
                        Text("Site \(viewModel.submissionDraft.siteId) • Task \(viewModel.submissionDraft.taskId)")
                            .font(.caption)
                            .blueprintSecondaryOnDark()
                    }
                }

                BlueprintGlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Capture checklist")
                            .font(.headline)
                        ForEach(Array(viewModel.captureChecklist.indices), id: \.self) { index in
                            Toggle(isOn: checklistBinding(for: index)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.captureChecklist[index].title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(viewModel.captureChecklist[index].details)
                                        .font(.caption)
                                        .blueprintSecondaryOnDark()
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }
                }

                BlueprintGlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Evidence coverage")
                            .font(.headline)
                        ForEach(Array(viewModel.evidenceCoverageDeclarations.indices), id: \.self) { index in
                            Toggle(isOn: coverageBinding(for: index)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.evidenceCoverageDeclarations[index].area)
                                        .font(.subheadline.weight(.semibold))
                                    Text(viewModel.evidenceCoverageDeclarations[index].notes)
                                        .font(.caption)
                                        .blueprintSecondaryOnDark()
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }
                }

                Button {
                    viewModel.beginCapture()
                } label: {
                    Text("Start phone capture")
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())
                .disabled(!viewModel.canStartCapture)
            }
            .padding()
        }
        .blueprintAppBackground()
    }

    private func checklistBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { viewModel.captureChecklist[index].isCompleted },
            set: { viewModel.captureChecklist[index].isCompleted = $0 }
        )
    }

    private func coverageBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { viewModel.evidenceCoverageDeclarations[index].isCovered },
            set: { viewModel.evidenceCoverageDeclarations[index].isCovered = $0 }
        )
    }
}

struct CaptureSummaryView: View {
    @ObservedObject var viewModel: CaptureFlowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Capture submitted")
                        .font(.largeTitle.weight(.bold))
                        .blueprintGradientText()
                    Text("Review the upload state for this evidence pass or collect another pass for the same task.")
                        .font(.callout)
                        .blueprintSecondaryOnDark()
                }

                if let context = viewModel.latestCompletedCaptureContext {
                    BlueprintGlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(context.siteName)
                                .font(.headline)
                            Text(context.taskStatement)
                                .font(.subheadline)
                                .blueprintSecondaryOnDark()
                            Divider()
                            Text("Submission \(context.submissionId)")
                                .font(.caption)
                                .blueprintSecondaryOnDark()
                            Text("Site \(context.siteId) • Task \(context.taskId)")
                                .font(.caption)
                                .blueprintSecondaryOnDark()
                            Text("Capture pass \(context.capturePass.capturePassId)")
                                .font(.caption)
                                .blueprintSecondaryOnDark()
                        }
                    }
                }

                BlueprintGlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Upload status")
                            .font(.headline)
                        if viewModel.uploadStatuses.isEmpty {
                            Text("Your capture package is being prepared.")
                                .font(.subheadline)
                                .blueprintSecondaryOnDark()
                        } else {
                            ForEach(viewModel.uploadStatuses) { status in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(status.metadata.capturePassId)
                                        .font(.subheadline.weight(.semibold))
                                    switch status.state {
                                    case .queued:
                                        Text("Queued")
                                    case .uploading(let progress):
                                        Text("Uploading \(Int(progress * 100))%")
                                    case .completed:
                                        Text("Completed")
                                    case .failed(let message):
                                        Text(message)
                                    }
                                }
                                .font(.caption)
                                .blueprintSecondaryOnDark()
                            }
                        }
                    }
                }

                Button {
                    viewModel.prepareAnotherCapturePass()
                } label: {
                    Text("Collect another capture pass")
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())
            }
            .padding()
        }
        .blueprintAppBackground()
    }
}

private struct QualificationTextField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }
}

private struct QualificationTextEditor: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                }
            }
        }
    }
}
