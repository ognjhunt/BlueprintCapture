import { createHash } from "node:crypto";

import {
  normalizeSiteType,
  type DemandEvidenceStrength,
  type DemandSignalDocument,
  type DemandSourceKind,
  type StrategicWeightConfig,
} from "./demand-opportunities.js";

export interface WebResearchArticle {
  title: string;
  link: string;
  sourceName?: string;
  sourceUrl?: string;
  publishedAt?: string;
  description?: string;
}

export interface WebResearchFinding {
  id: string;
  sector_id: string;
  company_name?: string;
  company_id?: string;
  site_type: string;
  workflow?: string;
  geo_scope?: string;
  maturity?: "pilot" | "deployment" | "expansion" | "funding" | "unknown";
  strength: DemandEvidenceStrength;
  confidence: number;
  citations: string[];
  summary: string;
  published_at?: string;
  source_url?: string;
  source_name?: string;
  title: string;
}

export interface DailyResearchRunResult {
  articles: WebResearchArticle[];
  findings: WebResearchFinding[];
}

type ResearchSector = {
  id: string;
  query: string;
  siteType: string;
  defaultWorkflows: string[];
};

const DAY_MS = 1000 * 60 * 60 * 24;

const DAILY_RESEARCH_SECTORS: ResearchSector[] = [
  {
    id: "warehouse_robotics",
    query: "\"warehouse robotics\" OR \"warehouse automation\" deployment OR rollout OR pilot",
    siteType: "warehouse",
    defaultWorkflows: ["dock_handoff", "aisle_navigation", "inventory_scan"],
  },
  {
    id: "dock_logistics_robotics",
    query: "\"dock robotics\" OR \"logistics robotics\" deployment OR trailer OR dock",
    siteType: "warehouse",
    defaultWorkflows: ["dock_handoff", "trailer_unload"],
  },
  {
    id: "manufacturing_robotics",
    query: "\"manufacturing robotics\" OR \"industrial robotics\" deployment OR plant OR factory",
    siteType: "manufacturing",
    defaultWorkflows: ["inspection", "material_handoff", "line_side_replenishment"],
  },
  {
    id: "retail_intelligence",
    query: "\"shelf intelligence\" OR \"retail robotics\" rollout OR store OR inventory",
    siteType: "retail",
    defaultWorkflows: ["inventory_scan", "shelf_intelligence", "replenishment"],
  },
  {
    id: "hospital_service_robotics",
    query: "\"hospital robotics\" OR \"service robot\" deployment OR hospital OR clinic",
    siteType: "hospital",
    defaultWorkflows: ["corridor_navigation", "supply_delivery", "inspection"],
  },
  {
    id: "hospitality_cleaning_robotics",
    query: "\"hospitality robotics\" OR \"cleaning robot\" rollout OR hotel OR hospitality",
    siteType: "hospitality",
    defaultWorkflows: ["cleaning", "inspection"],
  },
  {
    id: "convenience_retail_robotics",
    query: "\"convenience store\" robotics OR rollout OR pilot OR inventory",
    siteType: "convenience_store",
    defaultWorkflows: ["inventory_scan", "shelf_intelligence"],
  },
];

const SITE_TYPE_KEYWORDS: Array<{ siteType: string; terms: string[] }> = [
  { siteType: "warehouse", terms: ["warehouse", "distribution center", "dock", "logistics center", "fulfillment"] },
  { siteType: "manufacturing", terms: ["manufacturing", "factory", "plant", "industrial"] },
  { siteType: "grocery", terms: ["grocery", "supermarket"] },
  { siteType: "retail", terms: ["retail", "store", "shop", "shelf"] },
  { siteType: "hospital", terms: ["hospital", "clinic", "medical center", "health system"] },
  { siteType: "hospitality", terms: ["hotel", "hospitality", "resort"] },
  { siteType: "convenience_store", terms: ["convenience store", "c-store"] },
  { siteType: "pharmacy", terms: ["pharmacy", "drugstore"] },
];

const WORKFLOW_KEYWORDS: Array<{ workflow: string; terms: string[] }> = [
  { workflow: "dock_handoff", terms: ["dock", "handoff", "loading dock"] },
  { workflow: "trailer_unload", terms: ["trailer", "unload", "container"] },
  { workflow: "aisle_navigation", terms: ["aisle", "navigation", "autonomous mobile robot"] },
  { workflow: "inspection", terms: ["inspection", "quality check", "audit"] },
  { workflow: "material_handoff", terms: ["material", "handoff", "transfer"] },
  { workflow: "line_side_replenishment", terms: ["line-side", "replenishment", "production line"] },
  { workflow: "inventory_scan", terms: ["inventory", "scan", "stock"] },
  { workflow: "shelf_intelligence", terms: ["shelf", "planogram", "merchandising"] },
  { workflow: "replenishment", terms: ["replenishment", "restock"] },
  { workflow: "corridor_navigation", terms: ["corridor", "hallway", "navigation"] },
  { workflow: "supply_delivery", terms: ["delivery", "supplies", "medication"] },
  { workflow: "cleaning", terms: ["cleaning", "scrubbing", "janitorial"] },
];

const METRO_KEYWORDS = [
  "Atlanta",
  "Austin",
  "Boston",
  "Chicago",
  "Columbus",
  "Dallas",
  "Denver",
  "Houston",
  "Las Vegas",
  "Los Angeles",
  "Louisville",
  "Miami",
  "Nashville",
  "New York",
  "Philadelphia",
  "Phoenix",
  "Reno",
  "San Diego",
  "San Francisco",
  "Seattle",
];

const HTML_ENTITY_MAP: Record<string, string> = {
  "&amp;": "&",
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": "\"",
  "&#39;": "'",
};

function normalizeToken(value?: string | null): string {
  return (value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[\s\-]+/g, "_");
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function decodeHtml(value: string): string {
  let decoded = value;
  for (const [entity, replacement] of Object.entries(HTML_ENTITY_MAP)) {
    decoded = decoded.replaceAll(entity, replacement);
  }
  return decoded.replace(/&#(\d+);/g, (_, code: string) => String.fromCharCode(Number(code)));
}

function stripTags(value: string): string {
  return decodeHtml(value.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim());
}

function readXmlTag(block: string, tagName: string): string | undefined {
  const cdataMatch = block.match(new RegExp(`<${tagName}[^>]*><!\\[CDATA\\[([\\s\\S]*?)\\]\\]><\\/${tagName}>`, "i"));
  if (cdataMatch?.[1]) return stripTags(cdataMatch[1]);
  const match = block.match(new RegExp(`<${tagName}[^>]*>([\\s\\S]*?)<\\/${tagName}>`, "i"));
  return match?.[1] ? stripTags(match[1]) : undefined;
}

function readSourceMeta(block: string): { sourceName?: string; sourceUrl?: string } {
  const match = block.match(/<source[^>]*url="([^"]+)"[^>]*>([\s\S]*?)<\/source>/i);
  return {
    sourceUrl: match?.[1] ? decodeHtml(match[1]) : undefined,
    sourceName: match?.[2] ? stripTags(match[2]) : undefined,
  };
}

function parseGoogleNewsRss(xml: string): WebResearchArticle[] {
  const items = Array.from(xml.matchAll(/<item>([\s\S]*?)<\/item>/gi));
  return items.map((match) => {
    const block = match[1] ?? "";
    const { sourceName, sourceUrl } = readSourceMeta(block);
    return {
      title: readXmlTag(block, "title") ?? "Untitled",
      link: readXmlTag(block, "link") ?? "",
      sourceName,
      sourceUrl,
      publishedAt: readXmlTag(block, "pubDate"),
      description: readXmlTag(block, "description"),
    } satisfies WebResearchArticle;
  }).filter((item) => item.link.length > 0);
}

function includesAny(text: string, terms: string[]): boolean {
  return terms.some((term) => text.includes(term));
}

function inferSiteType(text: string, fallbackSiteType: string): string {
  for (const candidate of SITE_TYPE_KEYWORDS) {
    if (includesAny(text, candidate.terms)) {
      return normalizeSiteType(candidate.siteType) ?? fallbackSiteType;
    }
  }
  return normalizeSiteType(fallbackSiteType) ?? fallbackSiteType;
}

function inferWorkflow(text: string, sector: ResearchSector): string | undefined {
  for (const candidate of WORKFLOW_KEYWORDS) {
    if (includesAny(text, candidate.terms)) {
      return candidate.workflow;
    }
  }
  return sector.defaultWorkflows[0];
}

function inferStrength(text: string): DemandEvidenceStrength {
  if (includesAny(text, ["launched", "deployed", "rollout", "rolled out", "production deployment", "go-live"])) {
    return "high";
  }
  if (includesAny(text, ["expanded", "scaling", "fleet", "multi-site"])) {
    return "high";
  }
  if (includesAny(text, ["pilot", "trial", "proof of concept"])) {
    return "medium";
  }
  if (includesAny(text, ["funding", "raised", "investment"])) {
    return "medium";
  }
  return "low";
}

function inferMaturity(text: string): WebResearchFinding["maturity"] {
  if (includesAny(text, ["expanded", "scaling", "fleet", "multi-site"])) return "expansion";
  if (includesAny(text, ["launched", "deployed", "rollout", "rolled out", "production"])) return "deployment";
  if (includesAny(text, ["pilot", "trial", "proof of concept"])) return "pilot";
  if (includesAny(text, ["funding", "raised", "investment"])) return "funding";
  return "unknown";
}

function inferGeoScope(text: string): string | undefined {
  for (const metro of METRO_KEYWORDS) {
    if (text.includes(metro.toLowerCase())) return metro;
  }
  const stateMatch = text.match(/\b(arizona|california|florida|georgia|illinois|kentucky|massachusetts|nevada|new york|ohio|pennsylvania|tennessee|texas|washington)\b/i);
  return stateMatch?.[1];
}

function inferCompanyName(article: WebResearchArticle): string | undefined {
  const title = article.title.replace(/\s*[-|].*$/, "").trim();
  if (title.length > 0 && title.length < 80) return title;
  return article.sourceName;
}

function buildFindingId(sectorId: string, article: WebResearchArticle, siteType: string, workflow?: string): string {
  return createHash("sha256")
    .update([sectorId, article.link, siteType, workflow ?? ""].join("|"))
    .digest("hex")
    .slice(0, 24);
}

function dedupeFindings(findings: WebResearchFinding[]): WebResearchFinding[] {
  const seen = new Set<string>();
  return findings.filter((finding) => {
    const key = `${finding.id}:${finding.site_type}:${finding.workflow ?? ""}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export async function fetchDailyResearchFindings(
  fetchImpl: typeof fetch = fetch,
  now: Date = new Date(),
): Promise<DailyResearchRunResult> {
  const maxItemsPerSector = clamp(Number(process.env.DEMAND_RESEARCH_MAX_ITEMS_PER_QUERY ?? 6), 1, 15);
  const allArticles: WebResearchArticle[] = [];
  const findings: WebResearchFinding[] = [];

  for (const sector of DAILY_RESEARCH_SECTORS) {
    const url = new URL("https://news.google.com/rss/search");
    url.searchParams.set("q", `${sector.query} when:7d`);
    url.searchParams.set("hl", "en-US");
    url.searchParams.set("gl", "US");
    url.searchParams.set("ceid", "US:en");

    const response = await fetchImpl(url, {
      headers: {
        "User-Agent": "BlueprintCaptureDemandResearch/1.0",
        "Accept": "application/rss+xml, application/xml, text/xml",
      },
    });
    if (!response.ok) {
      throw new Error(`Daily research feed request failed for ${sector.id} with HTTP ${response.status}`);
    }

    const xml = await response.text();
    const articles = parseGoogleNewsRss(xml).slice(0, maxItemsPerSector);
    allArticles.push(...articles);

    for (const article of articles) {
      const combinedText = `${article.title} ${article.description ?? ""} ${article.sourceName ?? ""}`.toLowerCase();
      const siteType = inferSiteType(combinedText, sector.siteType);
      const workflow = inferWorkflow(combinedText, sector);
      const maturity = inferMaturity(combinedText);
      const strength = inferStrength(combinedText);
      const citations = [article.link, article.sourceUrl].filter((value): value is string => Boolean(value));
      const confidence = clamp(
        0.48 +
          (article.sourceUrl ? 0.12 : 0) +
          (maturity === "deployment" || maturity === "expansion" ? 0.14 : 0) +
          (workflow ? 0.05 : 0),
        0.45,
        0.92,
      );
      const companyName = inferCompanyName(article);
      const geoScope = inferGeoScope(combinedText);
      findings.push({
        id: buildFindingId(sector.id, article, siteType, workflow),
        sector_id: sector.id,
        company_name: companyName,
        company_id: companyName ? normalizeToken(companyName) : undefined,
        site_type: siteType,
        workflow,
        geo_scope: geoScope,
        maturity,
        strength,
        confidence,
        citations,
        summary: `${article.title}${geoScope ? ` (${geoScope})` : ""}`,
        published_at: article.publishedAt ? new Date(article.publishedAt).toISOString() : now.toISOString(),
        source_url: article.sourceUrl ?? article.link,
        source_name: article.sourceName,
        title: article.title,
      });
    }
  }

  return {
    articles: allArticles,
    findings: dedupeFindings(findings),
  };
}

export function buildDemandSignalsForWebResearchFindings(
  runId: string,
  findings: WebResearchFinding[],
  now: Date = new Date(),
): DemandSignalDocument[] {
  const expiry = new Date(now.getTime() + DAY_MS * 14).toISOString();

  return findings.map((finding) => ({
    id: `web-${finding.id}`,
    source_type: "web_research",
    source_ref: `${runId}:${finding.id}`,
    site_type: finding.site_type,
    workflow: finding.workflow,
    company_id: finding.company_id,
    geo_scope: finding.geo_scope,
    strength: finding.strength,
    confidence: finding.confidence,
    freshness_expires_at: expiry,
    citations: finding.citations,
    demand_source_kinds: ["cited_web_signal"],
    summary: finding.summary,
  }));
}

function sourceKindWeight(sourceKinds: DemandSourceKind[]): number {
  if (sourceKinds.includes("explicit_request")) return 1;
  if (sourceKinds.includes("operator_offer")) return 0.92;
  if (sourceKinds.includes("internal_behavioral_signal")) return 0.86;
  if (sourceKinds.includes("cited_web_signal")) return 0.7;
  return 0.5;
}

function strengthWeight(strength: DemandEvidenceStrength): number {
  switch (strength) {
    case "critical":
      return 1;
    case "high":
      return 0.84;
    case "medium":
      return 0.64;
    case "low":
    default:
      return 0.42;
  }
}

function isRecentSignal(signal: DemandSignalDocument, now: Date, lookbackDays: number): boolean {
  const expiresAt = signal.freshness_expires_at ? Date.parse(signal.freshness_expires_at) : Number.NaN;
  if (Number.isFinite(expiresAt) && expiresAt < now.getTime()) return false;
  const createdCutoff = now.getTime() - (lookbackDays * DAY_MS);
  return !Number.isFinite(expiresAt) || expiresAt >= createdCutoff;
}

export function buildStrategicWeightsFromSignals(
  signals: DemandSignalDocument[],
  now: Date = new Date(),
  lookbackDays = 45,
): StrategicWeightConfig {
  const recentSignals = signals.filter((signal) => isRecentSignal(signal, now, lookbackDays));
  const rawSiteTypeWeights = new Map<string, number>();
  const rawWorkflowWeights = new Map<string, number>();

  for (const signal of recentSignals) {
    const siteType = normalizeSiteType(signal.site_type);
    if (!siteType) continue;

    const weight =
      strengthWeight(signal.strength) *
      clamp(signal.confidence, 0.2, 1) *
      sourceKindWeight(signal.demand_source_kinds);

    rawSiteTypeWeights.set(siteType, (rawSiteTypeWeights.get(siteType) ?? 0) + weight);
    if (signal.workflow) {
      rawWorkflowWeights.set(signal.workflow, (rawWorkflowWeights.get(signal.workflow) ?? 0) + weight);
    }
  }

  const values = Array.from(rawSiteTypeWeights.values());
  const average = values.length > 0
    ? values.reduce((sum, value) => sum + value, 0) / values.length
    : 1;

  const site_type_weights = Object.fromEntries(
    Array.from(rawSiteTypeWeights.entries()).map(([siteType, weight]) => [
      siteType,
      clamp(0.85 + ((weight / average) - 1) * 0.3, 0.7, 1.35),
    ]),
  );

  const workflow_values = Array.from(rawWorkflowWeights.values());
  const workflowAverage = workflow_values.length > 0
    ? workflow_values.reduce((sum, value) => sum + value, 0) / workflow_values.length
    : 1;

  const workflow_weights = Object.fromEntries(
    Array.from(rawWorkflowWeights.entries()).map(([workflow, weight]) => [
      workflow,
      clamp(0.85 + ((weight / workflowAverage) - 1) * 0.25, 0.7, 1.3),
    ]),
  );

  return {
    generated_at: now.toISOString(),
    site_type_weights,
    workflow_weights,
  };
}
