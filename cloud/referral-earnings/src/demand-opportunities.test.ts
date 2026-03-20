import test from "node:test";
import assert from "node:assert/strict";

import {
  annotateCaptureJobs,
  buildDemandSignalsForRobotTeamRequest,
  buildDemandSignalsForSiteOperatorSubmission,
  normalizeSiteType,
  rankNearbyOpportunities,
  type DemandOpportunityFeedRequest,
} from "./demand-opportunities.js";

test("normalizeSiteType collapses aliases", () => {
  assert.equal(normalizeSiteType("distribution center"), "warehouse");
  assert.equal(normalizeSiteType("grocery_or_supermarket"), "grocery");
  assert.equal(normalizeSiteType("convenience_store"), "convenience_store");
});

test("robot team requests create explicit-request demand signals", () => {
  const signals = buildDemandSignalsForRobotTeamRequest("submission-1", {
    company_name: "Atlas Robotics",
    site_types: ["warehouse"],
    workflows: ["dock handoff"],
  });

  assert.equal(signals.length, 1);
  assert.equal(signals[0]?.site_type, "warehouse");
  assert.deepEqual(signals[0]?.demand_source_kinds, ["explicit_request"]);
});

test("site operator submissions create operator-offer demand signals", () => {
  const signals = buildDemandSignalsForSiteOperatorSubmission("submission-2", {
    operator_name: "Jordan",
    site_name: "North Dock",
    site_address: "1 Warehouse Way",
    site_types: ["warehouse"],
    workflows: ["dock handoff"],
    access_readiness: "high",
    consent_readiness: "high",
  });

  assert.equal(signals.length, 1);
  assert.equal(signals[0]?.site_type, "warehouse");
  assert.deepEqual(signals[0]?.demand_source_kinds, ["operator_offer"]);
});

test("rankNearbyOpportunities boosts categories with stronger demand", () => {
  const explicitSignals = buildDemandSignalsForRobotTeamRequest("submission-3", {
    company_name: "Atlas Robotics",
    site_types: ["warehouse"],
    workflows: ["dock handoff"],
  });

  const request: DemandOpportunityFeedRequest = {
    lat: 37.77,
    lng: -122.39,
    radius_m: 5000,
    limit: 5,
    candidate_places: [
      {
        place_id: "warehouse-1",
        display_name: "Dock Warehouse",
        lat: 37.771,
        lng: -122.391,
        place_types: ["warehouse"],
      },
      {
        place_id: "store-1",
        display_name: "Corner Shop",
        lat: 37.7712,
        lng: -122.3912,
        place_types: ["convenience_store"],
      },
    ],
  };

  const ranked = rankNearbyOpportunities(request, explicitSignals);

  assert.equal(ranked[0]?.place_id, "warehouse-1");
  assert.ok((ranked[0]?.opportunity_score ?? 0) > (ranked[1]?.opportunity_score ?? 0));
});

test("annotateCaptureJobs applies demand metadata to job payloads", () => {
  const signals = buildDemandSignalsForRobotTeamRequest("submission-4", {
    company_name: "Atlas Robotics",
    site_types: ["warehouse"],
    workflows: ["dock handoff"],
  });

  const jobs = annotateCaptureJobs(
    [
      {
        id: "job-1",
        data: {
          title: "Warehouse Dock A",
          address: "1 Warehouse Way",
          lat: 37.77,
          lng: -122.39,
          payout_cents: 4500,
          est_minutes: 25,
          active: true,
          updated_at: "2026-03-20T14:00:00.000Z",
          task_type: "buyer_requested_special_task",
          facility_template: "warehouse",
        },
      },
    ],
    signals,
    { lat: 37.77, lng: -122.39 },
    16093,
    10,
  );

  assert.equal(jobs.length, 1);
  assert.equal(jobs[0]?.siteType, "warehouse");
  assert.ok((jobs[0]?.demandScore ?? 0) > 0.8);
  assert.ok((jobs[0]?.opportunityScore ?? 0) > 0.7);
});
