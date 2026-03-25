export type DemandSourceKind =
  | "explicit_request"
  | "operator_offer"
  | "cited_web_signal"
  | "inferred_signal"
  | "internal_behavioral_signal";

export type DemandEvidenceStrength = "low" | "medium" | "high" | "critical";

export interface RobotTeamDemandRequestPayload {
  requester_name?: string;
  requester_email?: string;
  company_name: string;
  company_domain?: string;
  company_id?: string;
  target_geography?: string;
  target_metros?: string[];
  site_types: string[];
  workflows?: string[];
  constraints?: string[];
  target_kpis?: string[];
  urgency?: DemandEvidenceStrength;
  notes?: string;
  citations?: string[];
}

export interface SiteOperatorDemandSubmissionPayload {
  operator_name: string;
  operator_email?: string;
  company_name?: string;
  site_name: string;
  site_address: string;
  latitude?: number;
  longitude?: number;
  site_types: string[];
  workflows?: string[];
  access_readiness?: DemandEvidenceStrength;
  consent_readiness?: DemandEvidenceStrength;
  allowed_capture_windows?: string[];
  restrictions?: string[];
  notes?: string;
}

export interface DemandSignalDocument {
  id: string;
  source_type: string;
  source_ref?: string;
  site_type: string;
  workflow?: string;
  company_id?: string;
  geo_scope?: string;
  strength: DemandEvidenceStrength;
  confidence: number;
  freshness_expires_at?: string;
  citations: string[];
  demand_source_kinds: DemandSourceKind[];
  summary?: string;
}

export interface StrategicWeightConfig {
  generated_at?: string;
  source_run_id?: string;
  site_type_weights: Record<string, number>;
  workflow_weights?: Record<string, number>;
}

export interface OpportunityCandidatePlace {
  place_id: string;
  display_name: string;
  formatted_address?: string;
  lat: number;
  lng: number;
  place_types?: string[];
}

export interface DemandOpportunityFeedRequest {
  lat: number;
  lng: number;
  radius_m?: number;
  limit?: number;
  candidate_places?: OpportunityCandidatePlace[];
}

export interface RankedNearbyOpportunity {
  place_id: string;
  display_name: string;
  formatted_address?: string;
  lat: number;
  lng: number;
  place_types: string[];
  site_type?: string;
  site_type_confidence?: number;
  demand_score: number;
  opportunity_score: number;
  demand_summary: string;
  ranking_explanation: string;
  suggested_workflows: string[];
  demand_source_kinds: DemandSourceKind[];
  top_signal_ids: string[];
}

export interface CaptureJobApiRecord {
  id: string;
  title: string;
  address: string;
  lat: number;
  lng: number;
  payoutCents: number;
  estMinutes: number;
  active: boolean;
  updatedAt: string;
  thumbnailURL?: string | null;
  heroImageURL?: string | null;
  category?: string | null;
  instructions: string[];
  allowedAreas: string[];
  restrictedAreas: string[];
  permissionDocURL?: string | null;
  checkinRadiusM: number;
  alertRadiusM: number;
  priority: number;
  priorityWeight: number;
  regionId?: string | null;
  jobType: string;
  marketplaceState?: string | null;
  buyerRequestId?: string | null;
  siteSubmissionId?: string | null;
  quotedPayoutCents?: number | null;
  dueWindow?: string | null;
  approvalRequirements: string[];
  recaptureReason?: string | null;
  rightsChecklist: string[];
  rightsProfile?: string | null;
  requestedOutputs: string[];
  workflowName?: string | null;
  workflowSteps: string[];
  targetKPI?: string | null;
  zone?: string | null;
  shift?: string | null;
  owner?: string | null;
  facilityTemplate?: string | null;
  benchmarkStations: string[];
  lightingWindows: string[];
  movableObstacles: string[];
  floorConditionNotes: string[];
  reflectiveSurfaceNotes: string[];
  accessRules: string[];
  adjacentSystems: string[];
  privacyRestrictions: string[];
  securityRestrictions: string[];
  knownBlockers: string[];
  nonRoutineModes: string[];
  peopleTrafficNotes: string[];
  captureRestrictions: string[];
  siteType?: string | null;
  demandScore?: number | null;
  opportunityScore?: number | null;
  demandSummary?: string | null;
  rankingExplanation?: string | null;
  demandSourceKinds: string[];
  suggestedWorkflows: string[];
}

type NearbyRankingModelCandidate = {
  place_id: string;
  site_type?: string;
  site_type_confidence?: number;
  demand_score: number;
  opportunity_score: number;
  demand_summary: string;
  ranking_explanation: string;
  suggested_workflows: string[];
};

export interface NearbyOpportunityRankerOptions {
  apiKey?: string | null;
  model?: string | null;
  enabled?: boolean;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
}

const siteTypeAliases: Record<string, string> = {
  warehouse: "warehouse",
  distribution_center: "warehouse",
  storage: "warehouse",
  logistics: "warehouse",
  industrial: "manufacturing",
  factory: "manufacturing",
  manufacturing: "manufacturing",
  supermarket: "grocery",
  grocery_store: "grocery",
  grocery_or_supermarket: "grocery",
  grocery: "grocery",
  convenience_store: "convenience_store",
  pharmacy: "pharmacy",
  hospital: "hospital",
  medical: "hospital",
  office: "office",
  electronics_store: "retail",
  department_store: "retail",
  clothing_store: "retail",
  shopping_mall: "retail",
  retail: "retail",
  hotel: "hospitality",
  hospitality: "hospitality",
};

const baselineDemandBySiteType: Record<string, number> = {
  warehouse: 0.82,
  manufacturing: 0.8,
  grocery: 0.72,
  hospital: 0.58,
  retail: 0.5,
  pharmacy: 0.46,
  office: 0.42,
  hospitality: 0.38,
  convenience_store: 0.24,
};

const defaultWorkflowsBySiteType: Record<string, string[]> = {
  warehouse: ["dock_handoff", "trailer_unload", "aisle_navigation"],
  manufacturing: ["inspection", "material_handoff", "line_side_replenishment"],
  grocery: ["inventory_scan", "shelf_intelligence", "replenishment"],
  retail: ["inventory_scan", "shelf_intelligence"],
  hospital: ["corridor_navigation", "supply_delivery", "inspection"],
  office: ["cleaning", "inspection"],
  hospitality: ["cleaning", "inspection"],
  convenience_store: ["inventory_scan"],
  pharmacy: ["inventory_scan", "shelf_intelligence"],
};

function normalizeToken(value?: string | null): string {
  return (value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[\s\-]+/g, "_");
}

export function normalizeSiteType(value?: string | null): string | null {
  const token = normalizeToken(value);
  if (!token) return null;
  return siteTypeAliases[token] ?? token;
}

function normalizeWorkflow(value?: string | null): string | null {
  const token = normalizeToken(value);
  return token || null;
}

function strengthWeight(strength: DemandEvidenceStrength): number {
  switch (strength) {
    case "critical":
      return 1.0;
    case "high":
      return 0.85;
    case "medium":
      return 0.65;
    case "low":
    default:
      return 0.45;
  }
}

function sourceWeight(sourceKinds: DemandSourceKind[]): number {
  if (sourceKinds.includes("explicit_request")) return 1.0;
  if (sourceKinds.includes("operator_offer")) return 0.85;
  if (sourceKinds.includes("internal_behavioral_signal")) return 0.8;
  if (sourceKinds.includes("cited_web_signal")) return 0.65;
  return 0.45;
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function parseBoolean(value: string | undefined, defaultValue: boolean): boolean {
  if (value == null) return defaultValue;
  const normalized = value.trim().toLowerCase();
  if (!normalized) return defaultValue;
  return ["1", "true", "yes", "on"].includes(normalized);
}

function isFresh(signal: DemandSignalDocument, now: Date): boolean {
  if (!signal.freshness_expires_at) return true;
  const expires = Date.parse(signal.freshness_expires_at);
  return Number.isFinite(expires) ? expires >= now.getTime() : true;
}

function dedupe<T>(values: T[]): T[] {
  return Array.from(new Set(values));
}

export function inferSiteTypeFromPlaceTypes(placeTypes: string[] = []): { siteType: string | null; confidence: number } {
  for (const placeType of placeTypes) {
    const normalized = normalizeSiteType(placeType);
    if (normalized) {
      return { siteType: normalized, confidence: 0.9 };
    }
  }
  return { siteType: null, confidence: 0.35 };
}

export function buildDemandSignalsForRobotTeamRequest(
  submissionId: string,
  payload: RobotTeamDemandRequestPayload,
  now: Date = new Date(),
): DemandSignalDocument[] {
  const siteTypes = dedupe(payload.site_types.map((siteType) => normalizeSiteType(siteType)).filter(Boolean) as string[]);
  const workflows = dedupe((payload.workflows ?? []).map(normalizeWorkflow).filter(Boolean) as string[]);
  const expiry = new Date(now.getTime() + 1000 * 60 * 60 * 24 * 45).toISOString();

  return siteTypes.flatMap((siteType, siteIndex) => {
    const workflowList = workflows.length > 0 ? workflows : [undefined];
    return workflowList.map((workflow, workflowIndex) => ({
      id: `${submissionId}-${siteIndex}-${workflowIndex}`,
      source_type: "robot_team_request",
      source_ref: submissionId,
      site_type: siteType,
      workflow,
      company_id: payload.company_id ?? normalizeToken(payload.company_name),
      geo_scope: payload.target_geography ?? payload.target_metros?.[0],
      strength: payload.urgency ?? "high",
      confidence: 0.94,
      freshness_expires_at: expiry,
      citations: payload.citations ?? [],
      demand_source_kinds: ["explicit_request"],
      summary:
        payload.notes ??
        `${payload.company_name} is requesting ${siteType}${workflow ? ` for ${workflow}` : ""}.`,
    }));
  });
}

export function buildDemandSignalsForSiteOperatorSubmission(
  submissionId: string,
  payload: SiteOperatorDemandSubmissionPayload,
  now: Date = new Date(),
): DemandSignalDocument[] {
  const siteTypes = dedupe(payload.site_types.map((siteType) => normalizeSiteType(siteType)).filter(Boolean) as string[]);
  const workflows = dedupe((payload.workflows ?? []).map(normalizeWorkflow).filter(Boolean) as string[]);
  const strength = payload.consent_readiness === "critical" || payload.access_readiness === "critical"
    ? "critical"
    : payload.consent_readiness === "high" || payload.access_readiness === "high"
      ? "high"
      : "medium";
  const expiry = new Date(now.getTime() + 1000 * 60 * 60 * 24 * 30).toISOString();

  return siteTypes.flatMap((siteType, siteIndex) => {
    const workflowList = workflows.length > 0 ? workflows : [undefined];
    return workflowList.map((workflow, workflowIndex) => ({
      id: `${submissionId}-${siteIndex}-${workflowIndex}`,
      source_type: "site_operator_submission",
      source_ref: submissionId,
      site_type: siteType,
      workflow,
      geo_scope: payload.site_address,
      strength,
      confidence: 0.9,
      freshness_expires_at: expiry,
      citations: [],
      demand_source_kinds: ["operator_offer"],
      summary:
        payload.notes ??
        `${payload.site_name} is available for ${siteType}${workflow ? ` and ${workflow}` : ""}.`,
    }));
  });
}

type AggregatedSignalSummary = {
  demandScore: number;
  strategicWeight: number;
  sourceKinds: DemandSourceKind[];
  workflows: string[];
  signalIds: string[];
  summary: string;
  rankingExplanation: string;
};

function aggregateSignalsForSiteType(
  signals: DemandSignalDocument[],
  siteType: string | null,
  strategicWeights?: StrategicWeightConfig,
  now: Date = new Date(),
): AggregatedSignalSummary {
  const normalizedSiteType = normalizeSiteType(siteType);
  const matching = signals.filter((signal) => {
    if (!isFresh(signal, now)) return false;
    return normalizeSiteType(signal.site_type) === normalizedSiteType;
  });

  const weightedSignalSum = matching.reduce((sum, signal) => {
    return sum + strengthWeight(signal.strength) * sourceWeight(signal.demand_source_kinds) * clamp01(signal.confidence);
  }, 0);

  const baseline = baselineDemandBySiteType[normalizedSiteType ?? ""] ?? 0.35;
  const demandScore = clamp01(baseline + Math.min(0.45, weightedSignalSum * 0.12));
  const sourceKinds = dedupe(matching.flatMap((signal) => signal.demand_source_kinds));
  const workflows = dedupe(
    matching
      .map((signal) => normalizeWorkflow(signal.workflow))
      .filter(Boolean) as string[],
  );
  const summaries = matching.map((signal) => signal.summary).filter(Boolean) as string[];
  const topSignals = matching.slice(0, 5).map((signal) => signal.id);
  const strategicWeight = clamp(
    strategicWeights?.site_type_weights?.[normalizedSiteType ?? ""] ?? 1,
    0.6,
    1.5,
  );
  const summary = summaries[0]
    ?? (normalizedSiteType
      ? `Demand weighted toward ${normalizedSiteType.replace(/_/g, " ")} sites.`
      : "Demand inferred from market priors.");
  const rankingExplanation = matching.length > 0
    ? `Matched ${matching.length} active demand signal${matching.length == 1 ? "" : "s"} for ${normalizedSiteType ?? "this site type"}${strategicWeight !== 1 ? ` with weekly strategic weight ${strategicWeight.toFixed(2)}x.` : "."}`
    : `No explicit active signal found; using baseline demand for ${normalizedSiteType ?? "general commercial"} sites.`;

  return {
    demandScore,
    strategicWeight,
    sourceKinds,
    workflows: workflows.length > 0 ? workflows : (defaultWorkflowsBySiteType[normalizedSiteType ?? ""] ?? []),
    signalIds: topSignals,
    summary,
    rankingExplanation,
  };
}

function haversineMeters(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const earthRadiusMeters = 6371000;
  const toRadians = (degrees: number): number => (degrees * Math.PI) / 180;
  const dLat = toRadians(bLat - aLat);
  const dLng = toRadians(bLng - aLng);
  const startLat = toRadians(aLat);
  const endLat = toRadians(bLat);

  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.sin(dLng / 2) ** 2 * Math.cos(startLat) * Math.cos(endLat);
  return 2 * earthRadiusMeters * Math.asin(Math.sqrt(h));
}

export function rankNearbyOpportunities(
  request: DemandOpportunityFeedRequest,
  signals: DemandSignalDocument[],
  strategicWeights?: StrategicWeightConfig,
  now: Date = new Date(),
): RankedNearbyOpportunity[] {
  const limit = Math.max(1, Math.min(request.limit ?? 25, 100));
  const radiusMeters = Math.max(100, request.radius_m ?? 1609);

  return (request.candidate_places ?? [])
    .map((candidate) => {
      const siteTypeGuess = inferSiteTypeFromPlaceTypes(candidate.place_types ?? []);
      const aggregate = aggregateSignalsForSiteType(signals, siteTypeGuess.siteType, strategicWeights, now);
      const distanceMeters = haversineMeters(request.lat, request.lng, candidate.lat, candidate.lng);
      const distanceWeight = clamp01(1 - Math.min(1, distanceMeters / radiusMeters));
      const sourceDiversityWeight = clamp01(aggregate.sourceKinds.length / 3);
      const baseOpportunityScore = clamp01(
        aggregate.demandScore * 0.7 +
        distanceWeight * 0.2 +
        sourceDiversityWeight * 0.1,
      );
      const opportunityScore = clamp01(baseOpportunityScore * aggregate.strategicWeight);

      return {
        place_id: candidate.place_id,
        display_name: candidate.display_name,
        formatted_address: candidate.formatted_address,
        lat: candidate.lat,
        lng: candidate.lng,
        place_types: candidate.place_types ?? [],
        site_type: siteTypeGuess.siteType ?? undefined,
        site_type_confidence: siteTypeGuess.confidence,
        demand_score: aggregate.demandScore,
        opportunity_score: opportunityScore,
        demand_summary: aggregate.summary,
        ranking_explanation: aggregate.rankingExplanation,
        suggested_workflows: aggregate.workflows,
        demand_source_kinds: aggregate.sourceKinds,
        top_signal_ids: aggregate.signalIds,
      } satisfies RankedNearbyOpportunity;
    })
    .sort((lhs, rhs) => rhs.opportunity_score - lhs.opportunity_score)
    .slice(0, limit);
}

function nearbyRankerApiKey(): string {
  const candidates = [
    process.env.GEMINI_API_KEY,
    process.env.GOOGLE_AI_API_KEY,
  ];
  for (const candidate of candidates) {
    const normalized = candidate?.trim();
    if (normalized) return normalized;
  }
  return "";
}

function nearbyRankerModel(): string {
  return process.env.BLUEPRINT_NEARBY_RANKER_MODEL?.trim() || "gemini-3.1-flash-lite-preview";
}

function nearbyRankerEnabled(): boolean {
  return parseBoolean(process.env.BLUEPRINT_ENABLE_NEARBY_LLM_RANKER, true);
}

function nearbyRankerTimeoutMs(): number {
  const raw = Number(process.env.BLUEPRINT_NEARBY_LLM_TIMEOUT_MS || 5000);
  if (!Number.isFinite(raw) || raw <= 0) return 5000;
  return Math.trunc(raw);
}

function extractCandidateText(payload: unknown): string {
  if (!payload || typeof payload !== "object") return "";
  const candidates = (payload as { candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }> }).candidates;
  const first = candidates?.[0];
  const parts = first?.content?.parts ?? [];
  return parts
    .map((part) => (typeof part?.text === "string" ? part.text : ""))
    .join("")
    .trim();
}

function sanitizeRankedCandidate(
  raw: NearbyRankingModelCandidate,
  baseline: RankedNearbyOpportunity,
): RankedNearbyOpportunity {
  const normalizedSiteType = normalizeSiteType(raw.site_type) ?? baseline.site_type;
  const siteTypeConfidence = clamp(
    typeof raw.site_type_confidence === "number" ? raw.site_type_confidence : (baseline.site_type_confidence ?? 0.35),
    0,
    1,
  );
  return {
    ...baseline,
    site_type: normalizedSiteType ?? undefined,
    site_type_confidence: siteTypeConfidence,
    demand_score: clamp01(raw.demand_score),
    opportunity_score: clamp01(raw.opportunity_score),
    demand_summary: String(raw.demand_summary || baseline.demand_summary || "").trim() || baseline.demand_summary,
    ranking_explanation: String(raw.ranking_explanation || baseline.ranking_explanation || "").trim() || baseline.ranking_explanation,
    suggested_workflows: Array.isArray(raw.suggested_workflows)
      ? dedupe(raw.suggested_workflows.filter((value): value is string => typeof value === "string" && value.trim().length > 0))
      : baseline.suggested_workflows,
  };
}

function buildNearbyRankingPrompt(
  request: DemandOpportunityFeedRequest,
  heuristic: RankedNearbyOpportunity[],
): string {
  return [
    "You are ranking real nearby place candidates for Blueprint capture qualification.",
    "Use only the candidate list provided below. Do not invent places, addresses, coordinates, or workflows.",
    "Prioritize likely warehouses, factories, industrial retail, department stores, supermarkets, and other commercially relevant environments.",
    "Lower candidates that look consumer-only, low-signal, or weakly aligned.",
    "Return concise structured rankings for every candidate.",
    "",
    "Scoring rules:",
    "- demand_score: 0.0 to 1.0 estimate of how strategically interesting this site type is.",
    "- opportunity_score: 0.0 to 1.0 overall priority, factoring site type relevance, distance, and baseline signal hints.",
    "- site_type: short normalized label like warehouse, manufacturing, grocery, retail, hospitality, office, pharmacy, convenience_store.",
    "- suggested_workflows: short snake_case workflows, max 3.",
    "",
    `Origin lat/lng: ${request.lat}, ${request.lng}`,
    `Radius meters: ${request.radius_m ?? 1609}`,
    `Limit: ${request.limit ?? heuristic.length}`,
    "",
    "Candidate list:",
    JSON.stringify(heuristic.map((candidate) => ({
      place_id: candidate.place_id,
      display_name: candidate.display_name,
      formatted_address: candidate.formatted_address,
      lat: candidate.lat,
      lng: candidate.lng,
      place_types: candidate.place_types,
      baseline_site_type: candidate.site_type,
      baseline_site_type_confidence: candidate.site_type_confidence,
      baseline_demand_score: candidate.demand_score,
      baseline_opportunity_score: candidate.opportunity_score,
      baseline_demand_summary: candidate.demand_summary,
      baseline_ranking_explanation: candidate.ranking_explanation,
      baseline_suggested_workflows: candidate.suggested_workflows,
      baseline_demand_source_kinds: candidate.demand_source_kinds,
    }))),
  ].join("\n");
}

export async function rankNearbyOpportunitiesForFeed(
  request: DemandOpportunityFeedRequest,
  signals: DemandSignalDocument[],
  strategicWeights?: StrategicWeightConfig,
  now: Date = new Date(),
  options: NearbyOpportunityRankerOptions = {},
): Promise<RankedNearbyOpportunity[]> {
  const heuristic = rankNearbyOpportunities(request, signals, strategicWeights, now);
  if (!heuristic.length) return heuristic;

  const enabled = options.enabled ?? nearbyRankerEnabled();
  const apiKey = options.apiKey?.trim() || nearbyRankerApiKey();
  const model = options.model?.trim() || nearbyRankerModel();
  const timeoutMs = options.timeoutMs ?? nearbyRankerTimeoutMs();
  const fetchImpl = options.fetchImpl ?? globalThis.fetch;

  if (!enabled || !apiKey || !model || typeof fetchImpl !== "function") {
    return heuristic;
  }

  const schema = {
    type: "array",
    items: {
      type: "object",
      properties: {
        place_id: { type: "string" },
        site_type: { type: "string" },
        site_type_confidence: { type: "number" },
        demand_score: { type: "number" },
        opportunity_score: { type: "number" },
        demand_summary: { type: "string" },
        ranking_explanation: { type: "string" },
        suggested_workflows: {
          type: "array",
          items: { type: "string" },
        },
      },
      required: [
        "place_id",
        "demand_score",
        "opportunity_score",
        "demand_summary",
        "ranking_explanation",
        "suggested_workflows",
      ],
    },
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify({
          contents: [
            {
              role: "user",
              parts: [{ text: buildNearbyRankingPrompt(request, heuristic) }],
            },
          ],
          generationConfig: {
            responseMimeType: "application/json",
            responseJsonSchema: schema,
            temperature: 0.2,
            topP: 0.9,
          },
        }),
        signal: controller.signal,
      },
    );
    if (!response.ok) {
      return heuristic;
    }

    const payload = await response.json();
    const text = extractCandidateText(payload);
    if (!text) {
      return heuristic;
    }

    const parsed = JSON.parse(text);
    if (!Array.isArray(parsed)) {
      return heuristic;
    }

    const heuristicById = new Map(heuristic.map((candidate) => [candidate.place_id, candidate]));
    const merged = parsed
      .filter((item): item is NearbyRankingModelCandidate => Boolean(item && typeof item === "object" && typeof item.place_id === "string"))
      .map((item) => {
        const baseline = heuristicById.get(item.place_id);
        return baseline ? sanitizeRankedCandidate(item, baseline) : null;
      })
      .filter((item): item is RankedNearbyOpportunity => item !== null);

    if (!merged.length) {
      return heuristic;
    }

    const missing = heuristic.filter((candidate) => !merged.some((item) => item.place_id === candidate.place_id));
    return [...merged, ...missing]
      .sort((lhs, rhs) => rhs.opportunity_score - lhs.opportunity_score)
      .slice(0, Math.max(1, Math.min(request.limit ?? 25, 100)));
  } catch {
    return heuristic;
  } finally {
    clearTimeout(timeout);
  }
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function asNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function asNullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function asOptionalInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.trunc(parsed);
  }
  return null;
}

function coerceUpdatedAt(value: unknown): string {
  if (typeof value === "string" && value.length > 0) return value;
  if (value && typeof value === "object" && "toDate" in value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate().toISOString();
  }
  return new Date().toISOString();
}

export function annotateCaptureJobs(
  rawJobs: Array<{ id: string; data: Record<string, unknown> }>,
  signals: DemandSignalDocument[],
  origin: { lat: number; lng: number },
  radiusMeters: number,
  limit: number,
  strategicWeights?: StrategicWeightConfig,
  now: Date = new Date(),
): CaptureJobApiRecord[] {
  return rawJobs
    .map(({ id, data }) => {
      const jobLat = asNumber(data["lat"]);
      const jobLng = asNumber(data["lng"]);
      const siteType =
        normalizeSiteType(asNullableString(data["site_type"]))
        ?? normalizeSiteType(asNullableString(data["facility_template"]))
        ?? normalizeSiteType(asNullableString(data["category"]));
      const aggregate = aggregateSignalsForSiteType(signals, siteType, strategicWeights, now);
      const distanceMeters = haversineMeters(origin.lat, origin.lng, jobLat, jobLng);
      const distanceWeight = clamp01(1 - Math.min(1, distanceMeters / radiusMeters));
      const priorityWeight = clamp01(asNumber(data["priority_weight"], 1) / 2);
      const payoutWeight = clamp01(asNumber(data["quoted_payout_cents"] ?? data["payout_cents"], 0) / 10000);
      const baseOpportunityScore = clamp01(
        aggregate.demandScore * 0.55 +
        distanceWeight * 0.2 +
        priorityWeight * 0.15 +
        payoutWeight * 0.1,
      );
      const opportunityScore = clamp01(baseOpportunityScore * aggregate.strategicWeight);

      return {
        id,
        title: String(data["title"] ?? "Untitled"),
        address: String(data["address"] ?? ""),
        lat: jobLat,
        lng: jobLng,
        payoutCents: Math.trunc(asNumber(data["payout_cents"])),
        estMinutes: Math.trunc(asNumber(data["est_minutes"], 10)),
        active: data["active"] !== false,
        updatedAt: coerceUpdatedAt(data["updated_at"] ?? data["updatedAt"]),
        thumbnailURL: asNullableString(data["thumbnail_url"] ?? data["thumbnailURL"] ?? data["image_url"]),
        heroImageURL: asNullableString(data["hero_image_url"] ?? data["heroImageURL"]),
        category: asNullableString(data["category"]),
        instructions: asStringArray(data["instructions"]),
        allowedAreas: asStringArray(data["allowed_areas"]),
        restrictedAreas: asStringArray(data["restricted_areas"]),
        permissionDocURL: asNullableString(data["permission_doc_url"]),
        checkinRadiusM: Math.trunc(asNumber(data["checkin_radius_m"], 150)),
        alertRadiusM: Math.trunc(asNumber(data["alert_radius_m"], 200)),
        priority: Math.trunc(asNumber(data["priority"], 0)),
        priorityWeight: asNumber(data["priority_weight"], 1),
        regionId: asNullableString(data["region_id"]),
        jobType: String(data["task_type"] ?? "curated_nearby"),
        marketplaceState: asNullableString(data["marketplace_state"] ?? data["capture_job_state"]),
        buyerRequestId: asNullableString(data["buyer_request_id"]),
        siteSubmissionId: asNullableString(data["site_submission_id"]),
        quotedPayoutCents: asOptionalInt(data["quoted_payout_cents"]),
        dueWindow: asNullableString(data["due_window"]),
        approvalRequirements: asStringArray(data["approval_requirements"]),
        recaptureReason: asNullableString(data["recapture_reason"]),
        rightsChecklist: asStringArray(data["rights_checklist"]),
        rightsProfile: asNullableString(data["rights_profile"]),
        requestedOutputs: asStringArray(data["requested_outputs"]),
        workflowName: asNullableString(data["workflow_name"]),
        workflowSteps: asStringArray(data["workflow_steps"]),
        targetKPI: asNullableString(data["target_kpi"]),
        zone: asNullableString(data["zone"]),
        shift: asNullableString(data["shift"]),
        owner: asNullableString(data["owner"]),
        facilityTemplate: asNullableString(data["facility_template"]),
        benchmarkStations: asStringArray(data["benchmark_stations"]),
        lightingWindows: asStringArray(data["lighting_windows"]),
        movableObstacles: asStringArray(data["movable_obstacles"]),
        floorConditionNotes: asStringArray(data["floor_condition_notes"]),
        reflectiveSurfaceNotes: asStringArray(data["reflective_surface_notes"]),
        accessRules: asStringArray(data["access_rules"]),
        adjacentSystems: asStringArray(data["adjacent_systems"]),
        privacyRestrictions: asStringArray(data["privacy_restrictions"]),
        securityRestrictions: asStringArray(data["security_restrictions"]),
        knownBlockers: asStringArray(data["known_blockers"]),
        nonRoutineModes: asStringArray(data["non_routine_modes"]),
        peopleTrafficNotes: asStringArray(data["people_traffic_notes"]),
        captureRestrictions: asStringArray(data["capture_restrictions"]),
        siteType,
        demandScore: aggregate.demandScore,
        opportunityScore,
        demandSummary: aggregate.summary,
        rankingExplanation: aggregate.rankingExplanation,
        demandSourceKinds: aggregate.sourceKinds,
        suggestedWorkflows: aggregate.workflows,
      } satisfies CaptureJobApiRecord;
    })
    .filter((job) => job.active)
    .filter((job) => haversineMeters(origin.lat, origin.lng, job.lat, job.lng) <= radiusMeters)
    .sort((lhs, rhs) => {
      const lhsOpportunity = lhs.opportunityScore ?? lhs.demandScore ?? 0;
      const rhsOpportunity = rhs.opportunityScore ?? rhs.demandScore ?? 0;
      if (lhsOpportunity !== rhsOpportunity) return rhsOpportunity - lhsOpportunity;
      if (lhs.priority !== rhs.priority) return rhs.priority - lhs.priority;
      return (rhs.quotedPayoutCents ?? rhs.payoutCents) - (lhs.quotedPayoutCents ?? lhs.payoutCents);
    })
    .slice(0, Math.max(1, Math.min(limit, 200)));
}
