import Foundation

enum BuyerType: String, Codable, CaseIterable, Identifiable {
    case siteOperator = "site_operator"
    case robotTeam = "robot_team"
    case integrator = "integrator"
    case other = "other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .siteOperator:
            return "Site operator"
        case .robotTeam:
            return "Robot team"
        case .integrator:
            return "Integrator"
        case .other:
            return "Other"
        }
    }
}

enum CaptureMode: String, Codable, Equatable {
    case phone
}

enum RestrictionSeverity: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }
}

struct TaskZoneBoundary: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var boundaryNotes: String
    var adjacentWorkflow: String

    init(id: String = UUID().uuidString, name: String, boundaryNotes: String, adjacentWorkflow: String) {
        self.id = id
        self.name = name
        self.boundaryNotes = boundaryNotes
        self.adjacentWorkflow = adjacentWorkflow
    }
}

struct PrivacySecurityRestriction: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var details: String
    var severity: RestrictionSeverity

    init(id: String = UUID().uuidString, title: String, details: String, severity: RestrictionSeverity) {
        self.id = id
        self.title = title
        self.details = details
        self.severity = severity
    }
}

struct CaptureChecklistItem: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var details: String
    var isCompleted: Bool

    init(id: String = UUID().uuidString, title: String, details: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.details = details
        self.isCompleted = isCompleted
    }
}

struct EvidenceCoverageDeclaration: Identifiable, Codable, Equatable {
    let id: String
    var area: String
    var notes: String
    var isCovered: Bool

    init(id: String = UUID().uuidString, area: String, notes: String, isCovered: Bool = false) {
        self.id = id
        self.area = area
        self.notes = notes
        self.isCovered = isCovered
    }
}

struct EvidenceCoverageMetadata: Codable, Equatable {
    var totalDeclaredAreas: Int
    var coveredAreas: Int
    var coverageSummary: String
}

struct CapturePassContext: Codable, Equatable {
    let submissionId: String
    let siteId: String
    let taskId: String
    let capturePassId: String
    let captureMode: CaptureMode
    let createdAt: Date
}

struct TaskCaptureContext: Codable, Equatable {
    let submissionId: String
    let siteId: String
    let taskId: String
    let buyerType: BuyerType
    let siteName: String
    let siteLocation: String
    let taskStatement: String
    let workflowContext: String
    let operatingConstraints: String
    let knownBlockers: String
    let targetRobotTeam: String
    let workcellTaskZoneBoundaries: [TaskZoneBoundary]
    let privacySecurityRestrictions: [PrivacySecurityRestriction]
    let captureChecklist: [CaptureChecklistItem]
    let zoneCoverageDeclarations: [EvidenceCoverageDeclaration]
    let evidenceCoverageMetadata: EvidenceCoverageMetadata
    let privacyAnnotations: [String]
    let preferredGeometryBundleFiles: [String]
    let capturePass: CapturePassContext

    var isReadyForCapture: Bool {
        !siteName.trimmed().isEmpty &&
        !siteLocation.trimmed().isEmpty &&
        !taskStatement.trimmed().isEmpty &&
        captureChecklist.allSatisfy(\.isCompleted) &&
        zoneCoverageDeclarations.contains(where: \.isCovered)
    }

    static func defaultChecklist() -> [CaptureChecklistItem] {
        [
            CaptureChecklistItem(title: "Task-zone walkthrough", details: "Primary task zone and the exact area where the workflow happens."),
            CaptureChecklistItem(title: "Adjacent workflow context", details: "Nearby stations, handoff points, and process context around the zone."),
            CaptureChecklistItem(title: "Ingress and egress", details: "Entrances, exits, aisle widths, and clearance constraints."),
            CaptureChecklistItem(title: "Obstacles and hazards", details: "Clutter, floor transitions, reflective surfaces, and human traffic."),
            CaptureChecklistItem(title: "Restricted areas", details: "Any privacy-sensitive or security-sensitive areas that affect evidence collection.")
        ]
    }

    static func defaultCoverageDeclarations() -> [EvidenceCoverageDeclaration] {
        [
            EvidenceCoverageDeclaration(area: "Primary task zone", notes: "Camera can see the main workcell boundaries."),
            EvidenceCoverageDeclaration(area: "Ingress / egress path", notes: "Route into and out of the zone is visible."),
            EvidenceCoverageDeclaration(area: "Handoff points", notes: "Key transfer surfaces or bottlenecks are visible."),
            EvidenceCoverageDeclaration(area: "Constraints and restricted areas", notes: "Privacy masks, blocked aisles, or no-capture zones are documented.")
        ]
    }
}

struct SiteSubmissionDraft: Equatable {
    var submissionId: String
    var siteId: String
    var taskId: String
    var createdAt: Date
    var buyerType: BuyerType
    var siteName: String
    var siteLocation: String
    var taskStatement: String
    var workflowContext: String
    var operatingConstraints: String
    var privacySecurityNotes: String
    var knownBlockers: String
    var targetRobotTeam: String
    var taskZoneName: String
    var taskZoneBoundaryNotes: String
    var adjacentWorkflowNotes: String

    init(
        submissionId: String = QualificationID.make(prefix: "submission"),
        siteId: String = QualificationID.make(prefix: "site"),
        taskId: String = QualificationID.make(prefix: "task"),
        createdAt: Date = Date(),
        buyerType: BuyerType = .siteOperator,
        siteName: String = "",
        siteLocation: String = "",
        taskStatement: String = "",
        workflowContext: String = "",
        operatingConstraints: String = "",
        privacySecurityNotes: String = "",
        knownBlockers: String = "",
        targetRobotTeam: String = "",
        taskZoneName: String = "Primary task zone",
        taskZoneBoundaryNotes: String = "",
        adjacentWorkflowNotes: String = ""
    ) {
        self.submissionId = submissionId
        self.siteId = siteId
        self.taskId = taskId
        self.createdAt = createdAt
        self.buyerType = buyerType
        self.siteName = siteName
        self.siteLocation = siteLocation
        self.taskStatement = taskStatement
        self.workflowContext = workflowContext
        self.operatingConstraints = operatingConstraints
        self.privacySecurityNotes = privacySecurityNotes
        self.knownBlockers = knownBlockers
        self.targetRobotTeam = targetRobotTeam
        self.taskZoneName = taskZoneName
        self.taskZoneBoundaryNotes = taskZoneBoundaryNotes
        self.adjacentWorkflowNotes = adjacentWorkflowNotes
    }

    var canCreateSubmission: Bool {
        !siteName.trimmed().isEmpty &&
        !taskStatement.trimmed().isEmpty &&
        !workflowContext.trimmed().isEmpty &&
        !taskZoneBoundaryNotes.trimmed().isEmpty
    }

    mutating func syncSiteLocation(_ location: String?) {
        guard let location, !location.trimmed().isEmpty else { return }
        siteLocation = location
    }

    func makeTaskCaptureContext(
        checklist: [CaptureChecklistItem],
        coverage: [EvidenceCoverageDeclaration],
        capturePassId: String = QualificationID.make(prefix: "capture_pass")
    ) -> TaskCaptureContext {
        let restrictions: [PrivacySecurityRestriction]
        if privacySecurityNotes.trimmed().isEmpty {
            restrictions = [
                PrivacySecurityRestriction(
                    title: "Declared restrictions",
                    details: "No additional privacy or security restrictions were declared during intake.",
                    severity: .low
                )
            ]
        } else {
            restrictions = [
                PrivacySecurityRestriction(
                    title: "Privacy / security restriction",
                    details: privacySecurityNotes,
                    severity: .medium
                )
            ]
        }

        let boundaries = [
            TaskZoneBoundary(
                name: taskZoneName.trimmed().isEmpty ? "Primary task zone" : taskZoneName,
                boundaryNotes: taskZoneBoundaryNotes,
                adjacentWorkflow: adjacentWorkflowNotes
            )
        ]

        let coverageMetadata = EvidenceCoverageMetadata(
            totalDeclaredAreas: coverage.count,
            coveredAreas: coverage.filter(\.isCovered).count,
            coverageSummary: coverage
                .filter(\.isCovered)
                .map(\.area)
                .joined(separator: ", ")
        )

        return TaskCaptureContext(
            submissionId: submissionId,
            siteId: siteId,
            taskId: taskId,
            buyerType: buyerType,
            siteName: siteName,
            siteLocation: siteLocation,
            taskStatement: taskStatement,
            workflowContext: workflowContext,
            operatingConstraints: operatingConstraints,
            knownBlockers: knownBlockers,
            targetRobotTeam: targetRobotTeam,
            workcellTaskZoneBoundaries: boundaries,
            privacySecurityRestrictions: restrictions,
            captureChecklist: checklist,
            zoneCoverageDeclarations: coverage,
            evidenceCoverageMetadata: coverageMetadata,
            privacyAnnotations: restrictions.map { "\($0.title): \($0.details)" },
            preferredGeometryBundleFiles: [
                "3dgs_compressed.ply",
                "labels.json",
                "structure.json",
                "task_targets.synthetic.json"
            ],
            capturePass: CapturePassContext(
                submissionId: submissionId,
                siteId: siteId,
                taskId: taskId,
                capturePassId: capturePassId,
                captureMode: .phone,
                createdAt: Date()
            )
        )
    }
}

enum QualificationID {
    static func make(prefix: String) -> String {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "\(prefix)_\(suffix)"
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
