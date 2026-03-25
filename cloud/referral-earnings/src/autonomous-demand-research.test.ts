import test from "node:test";
import assert from "node:assert/strict";

import {
  buildDemandSignalsForWebResearchFindings,
  buildStrategicWeightsFromSignals,
  fetchDailyResearchFindings,
} from "./autonomous-demand-research.js";
import { buildDemandSignalsForRobotTeamRequest } from "./demand-opportunities.js";

const sampleRss = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <item>
      <title><![CDATA[Symbotic expands warehouse robot rollout in Dallas]]></title>
      <link>https://news.google.com/rss/articles/test-1</link>
      <pubDate>Thu, 20 Mar 2026 12:00:00 GMT</pubDate>
      <description><![CDATA[New warehouse deployment supports dock automation.]]></description>
      <source url="https://www.symbotic.com">Symbotic</source>
    </item>
  </channel>
</rss>`;

test("fetchDailyResearchFindings parses RSS articles into findings", async () => {
  let callCount = 0;
  const fetchStub: typeof fetch = async () => {
    callCount += 1;
    return new Response(sampleRss, {
      status: 200,
      headers: {
        "Content-Type": "application/rss+xml",
      },
    });
  };

  const result = await fetchDailyResearchFindings(fetchStub, new Date("2026-03-20T15:00:00.000Z"));

  assert.ok(callCount >= 1);
  assert.ok(result.articles.length >= 1);
  assert.ok(result.findings.length >= 1);
  assert.equal(result.findings[0]?.site_type, "warehouse");
  assert.equal(result.findings[0]?.workflow, "dock_handoff");
  assert.equal(result.findings[0]?.geo_scope, "Dallas");
  assert.ok((result.findings[0]?.citations.length ?? 0) >= 2);
});

test("buildDemandSignalsForWebResearchFindings emits cited web signals", () => {
  const signals = buildDemandSignalsForWebResearchFindings("run-1", [
    {
      id: "finding-1",
      sector_id: "warehouse_robotics",
      company_name: "Symbotic",
      company_id: "symbotic",
      site_type: "warehouse",
      workflow: "dock_handoff",
      geo_scope: "Dallas",
      maturity: "deployment",
      strength: "high",
      confidence: 0.78,
      citations: ["https://example.com/article"],
      summary: "Symbotic expands warehouse robot rollout in Dallas",
      published_at: "2026-03-20T12:00:00.000Z",
      source_url: "https://www.symbotic.com",
      source_name: "Symbotic",
      title: "Symbotic expands warehouse robot rollout in Dallas",
    },
  ], new Date("2026-03-20T15:00:00.000Z"));

  assert.equal(signals.length, 1);
  assert.equal(signals[0]?.source_type, "web_research");
  assert.deepEqual(signals[0]?.demand_source_kinds, ["cited_web_signal"]);
  assert.equal(signals[0]?.site_type, "warehouse");
});

test("buildStrategicWeightsFromSignals biases stronger categories upward", () => {
  const warehouseSignals = buildDemandSignalsForRobotTeamRequest("submission-weights", {
    company_name: "Atlas Robotics",
    site_types: ["warehouse"],
    workflows: ["dock handoff"],
  });
  const retailSignals = buildDemandSignalsForRobotTeamRequest("submission-retail", {
    company_name: "Shelf Bot",
    site_types: ["retail"],
    workflows: ["inventory scan"],
  }).map((signal) => ({
    ...signal,
    confidence: 0.4,
    strength: "low" as const,
  }));

  const strategicWeights = buildStrategicWeightsFromSignals(
    [...warehouseSignals, ...warehouseSignals, ...retailSignals],
    new Date("2026-03-20T15:00:00.000Z"),
  );

  assert.ok((strategicWeights.site_type_weights.warehouse ?? 0) > 1);
  assert.ok((strategicWeights.site_type_weights.retail ?? 1) < (strategicWeights.site_type_weights.warehouse ?? 0));
});
