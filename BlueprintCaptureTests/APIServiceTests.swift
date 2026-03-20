import Foundation
import Testing
@testable import BlueprintCapture

struct APIServiceTests {

    @Test
    func apiErrorLocalizedDescriptionsAreActionable() {
        #expect(APIService.APIError.missingBaseURL.errorDescription == "BLUEPRINT_BACKEND_BASE_URL is not configured for this build.")
        #expect(APIService.APIError.invalidResponse(statusCode: 503).errorDescription == "The backend returned HTTP 503.")
        #expect(APIService.APIError.invalidResponse(statusCode: -1).errorDescription == "The backend returned an invalid non-HTTP response.")
    }

    @Test
    func demandOpportunityFeedContractsDecodeSnakeCasePayloads() throws {
        let json = """
        {
          "generated_at": "2026-03-20T14:00:00Z",
          "nearby_opportunities": [
            {
              "place_id": "place-1",
              "display_name": "Dock Warehouse",
              "formatted_address": "1 Warehouse Way",
              "lat": 37.77,
              "lng": -122.39,
              "place_types": ["warehouse"],
              "site_type": "warehouse",
              "site_type_confidence": 0.92,
              "demand_score": 0.88,
              "opportunity_score": 0.91,
              "demand_summary": "Strong warehouse demand",
              "ranking_explanation": "Matched robot-team requests",
              "suggested_workflows": ["dock_handoff"],
              "demand_source_kinds": ["explicit_request"],
              "top_signal_ids": ["sig-1"]
            }
          ],
          "capture_jobs": [
            {
              "id": "job-1",
              "title": "Warehouse Dock A",
              "address": "1 Warehouse Way",
              "lat": 37.77,
              "lng": -122.39,
              "payoutCents": 4500,
              "estMinutes": 25,
              "active": true,
              "updatedAt": "2026-03-20T14:00:00Z",
              "thumbnailURL": "https://example.com/thumb.png",
              "heroImageURL": "https://example.com/hero.png",
              "category": "Warehouse",
              "instructions": [],
              "allowedAreas": [],
              "restrictedAreas": [],
              "permissionDocURL": null,
              "checkinRadiusM": 150,
              "alertRadiusM": 200,
              "priority": 1,
              "priorityWeight": 1.0,
              "regionId": "bay-area",
              "jobType": "buyer_requested_special_task",
              "marketplaceState": "claimable",
              "buyerRequestId": "buyer-1",
              "siteSubmissionId": null,
              "quotedPayoutCents": 4500,
              "dueWindow": "managed",
              "approvalRequirements": [],
              "recaptureReason": null,
              "rightsChecklist": [],
              "rightsProfile": "documented_permission",
              "requestedOutputs": ["qualification"],
              "workflowName": "Dock walkthrough",
              "workflowSteps": [],
              "targetKPI": null,
              "zone": null,
              "shift": null,
              "owner": null,
              "facilityTemplate": "warehouse_dock_handoff",
              "benchmarkStations": [],
              "lightingWindows": [],
              "movableObstacles": [],
              "floorConditionNotes": [],
              "reflectiveSurfaceNotes": [],
              "accessRules": [],
              "adjacentSystems": [],
              "privacyRestrictions": [],
              "securityRestrictions": [],
              "knownBlockers": [],
              "nonRoutineModes": [],
              "peopleTrafficNotes": [],
              "captureRestrictions": [],
              "siteType": "warehouse",
              "demandScore": 0.88,
              "opportunityScore": 0.93,
              "demandSummary": "Strong warehouse demand",
              "rankingExplanation": "Matched explicit requests",
              "demandSourceKinds": ["explicit_request"],
              "suggestedWorkflows": ["dock_handoff"]
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(DemandOpportunityFeedResponse.self, from: Data(json.utf8))

        #expect(response.nearbyOpportunities.count == 1)
        #expect(response.nearbyOpportunities.first?.demandScore == 0.88)
        #expect(response.captureJobs.first?.opportunityScore == 0.93)
        #expect(response.captureJobs.first?.siteType == "warehouse")
    }
}
