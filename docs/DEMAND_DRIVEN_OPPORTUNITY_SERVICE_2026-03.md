# Demand-Driven Opportunity Service

Date: 2026-03-20

## Purpose

Blueprint should rank nearby capture opportunities based on real demand, not just generic nearby places.

That means the system should continuously combine:

- direct demand from robot teams
- direct supply/consent from site operators
- external market signal from web research
- internal marketplace outcomes such as claims, captures, approvals, buyer follow-up, and recapture requests

The result should be a demand-weighted opportunity layer that changes what contributors see in the app.

## Why This Fits The Vision

This matches the platform doctrine in [PLATFORM_CONTEXT.md](/Users/nijelhunt_1/workspace/BlueprintCapture/PLATFORM_CONTEXT.md) and [WORLD_MODEL_STRATEGY_CONTEXT.md](/Users/nijelhunt_1/workspace/BlueprintCapture/WORLD_MODEL_STRATEGY_CONTEXT.md):

- Blueprint wins on data, qualification, rights, and workflow, not on one model.
- Demand should shape capture coverage.
- The product moat is the capture -> qualification -> preview/runtime -> buyer feedback -> more capture flywheel.

The demand service is therefore a marketplace/data service, not a mobile-only feature.

## Repo Boundary

This repo already has the mobile surfaces that consume opportunities:

- nearby place discovery in [TargetsAPI.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/TargetsAPI.swift)
- curated job ingestion in [JobsRepository.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/JobsRepository.swift)
- opportunity presentation in [NearbyTargetsViewModel.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/ViewModels/NearbyTargetsViewModel.swift)
- home-feed job ranking in [ScanHomeViewModel.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/ViewModels/ScanHomeViewModel.swift)

The actual demand-research system should live in backend / webapp infrastructure, then publish:

- ranked `capture_jobs`
- ranked nearby opportunity candidates
- demand metadata attached to each opportunity

The mobile app should consume the outputs, not run market research itself.

## Recommended Product Shape

Use three demand lanes, then merge them into one opportunity score.

### 1. Explicit Demand

This is the highest-signal lane.

- robot teams submit requested site types, workflows, constraints, urgency, geography, and target KPIs
- site operators submit exact locations, access/rights posture, and willingness to host capture
- internal ops can create or approve structured demand records

This data should be first-class product input, not buried in notes.

### 2. External Research Demand

This is the market-sensing lane.

Use scheduled research jobs to detect:

- which robotics startups and incumbents are actively deploying
- what environments they target
- what workflows they care about
- where pilot density is forming
- which verticals are scaling vs still mostly speculative

This lane should never directly create payout-ready jobs by itself. It should create weighted demand hypotheses with citations and freshness timestamps.

### 3. Internal Marketplace Feedback

This is the flywheel lane.

Capture:

- claim rate
- reservation rate
- completion rate
- buyer follow-up rate
- repeat requests for the same site type or workflow
- operator opt-in rate
- recapture frequency
- qualification pass rate
- downstream preview/runtime requests

This converts real product behavior into demand calibration.

## Recommended March 2026 Stack

### LLMs

Primary orchestration and synthesis:

- OpenAI `gpt-5.4` for ranking, taxonomy normalization, schema-constrained classification, and evidence synthesis
- OpenAI `gpt-5.4-mini` for high-volume enrichment and reclassification jobs

Deep scheduled research:

- OpenAI `o3-deep-research` for weekly or daily research sweeps over robotics verticals, companies, deployments, and site categories

Secondary verifier / alternative research engine:

- Anthropic Claude Opus 4.6 or Sonnet 4.6 with web search for cross-checking summaries and citation-backed analysis

Google option when Maps/Search grounding matters:

- Gemini on Vertex AI with Grounding with Google Search for search-grounded research and location-aware runs

### Search / Crawl / Extraction

Use two layers:

1. model-native web search for broad research and citation-backed reasoning
2. deterministic crawl/extract services for repeatable ingestion

Recommended services:

- Firecrawl for crawl, scrape, search, and structured extraction across company sites, docs, newsroom pages, and market pages
- Tavily for search-oriented agent retrieval and focused extract/crawl tasks

### Geospatial / Place Canonicalization

Keep Google Maps Platform as the place layer:

- Places Nearby Search
- Places Text Search
- Place Details
- Geocoding

This matches the app's current place-discovery path and is still the right backbone for mapping demand categories to real candidate locations.

### Company / Market Entity Feed

Use an entity source for company normalization and startup/funding tracking:

- Crunchbase API for organization search / lookup

If deeper commercial intelligence is needed later, add a paid company data layer, but do not block V1 on it.

## Architecture

### A. Ingestion

Create a backend service with these source connectors:

- `robot_team_requests`
- `site_operator_submissions`
- `web_research_runs`
- `market_entity_feed`
- `internal_marketplace_events`
- `place_catalog`

Do not merge these raw signals too early. Store provenance for each signal.

### B. Normalization

Normalize everything into a shared ontology:

- vertical: warehouse, manufacturing, grocery, pharmacy, hospital, office, hotel, convenience_store, etc.
- workflow: inventory_scan, dock_handoff, replenishment, aisle_navigation, trailer_unload, shelf_intelligence, cleaning, inspection
- deployment maturity: exploratory, pilot, active_rollout, scaled
- evidence strength: explicit_request, operator_offer, cited_web_signal, inferred_signal, internal_behavioral_signal
- geography: country, state, metro, place polygon, exact site

This is where LLMs help the most.

They should map messy text into stable enums plus confidence.

### C. Scoring

For each candidate place or exact site, compute:

`opportunity_score = demand_score * operator_readiness * capture_feasibility * geographic_relevance * freshness * strategic_weight - suppression_penalties`

Suggested components:

- `demand_score`: weighted aggregate of robot-team demand, research demand, and internal feedback
- `operator_readiness`: consent/access likelihood or confirmed operator opt-in
- `capture_feasibility`: public/private constraints, privacy risk, expected capture quality, travel friction
- `geographic_relevance`: near active demand clusters or target metros
- `freshness`: decays stale web/research signals
- `strategic_weight`: manual multiplier for strategic categories
- `suppression_penalties`: over-supplied areas, repeated failed captures, blocked rights profile, low buyer conversion

### D. Publishing

Publish two outputs:

1. exact jobs
2. demand-weighted nearby suggestions

Exact jobs:

- operator-approved or buyer-requested locations
- written into `capture_jobs`

Demand-weighted nearby suggestions:

- generated from place candidates around the user
- enriched with `demand_reasoning`, `demand_sources`, `site_type_confidence`, `suggested_workflows`, and `demand_freshness`

## Data Model

Minimum backend entities:

### `demand_signal`

- `id`
- `source_type`
- `source_ref`
- `site_type`
- `workflow`
- `company_id`
- `geo_scope`
- `strength`
- `confidence`
- `freshness_expires_at`
- `citations[]`
- `raw_payload`
- `normalized_payload`

### `opportunity_cluster`

- `id`
- `site_type`
- `workflow`
- `metro`
- `demand_score`
- `operator_supply_score`
- `capture_supply_score`
- `coverage_gap_score`
- `recommended_place_types[]`
- `top_companies[]`
- `top_citations[]`

### `site_opportunity`

- `id`
- `place_id`
- `site_submission_id`
- `capture_job_id`
- `site_type`
- `workflow`
- `demand_score`
- `opportunity_score`
- `demand_summary`
- `demand_sources[]`
- `ranking_explanation`
- `updated_at`

## Research Pipeline

Run two types of research.

### Fast loop: daily

Purpose:

- detect new deployments, funding, pilots, partnerships, and category shifts

Implementation:

- search robotics companies by sector
- extract cited mentions of environment, workflow, geography, and maturity
- update `demand_signal`

Use:

- `gpt-5.4-mini` or Sonnet 4.6
- Firecrawl/Tavily for extraction

### Deep loop: weekly

Purpose:

- rebuild category priors and strategic weights

Implementation:

- run deep research across industrial, logistics, manufacturing, retail, healthcare, hospitality, field robotics, and niche categories
- cluster company activity by site type and workflow
- produce a reviewed strategy summary and score adjustments

Use:

- `o3-deep-research`
- optionally cross-check with Claude Opus 4.6

## How This Should Affect The App

### In Nearby Discovery

Nearby discovery should stop treating all valid places as equally interesting.

Instead:

- search for candidate places around the user
- request backend ranking for those candidates
- return only demand-weighted locations

Examples:

- if warehouse / dock / manufacturing demand is high in a metro, rank those first
- if convenience store demand is weak and stale, suppress those results unless there is explicit operator or buyer demand

### In Home Feed

The home feed should separate:

- `Ready now`: exact approved jobs
- `High demand nearby`: ranked inferred opportunities
- `Emerging categories`: new areas where demand is rising but operator readiness is still thin

### In The Web App

Add forms and structured inputs for:

- robot teams: "what environments are you trying to deploy into?"
- site operators: "what type of site do you operate and are you open to scanning?"

That data is more valuable than generic contact forms because it becomes ranking input.

## Initial Build Plan

### Phase 1

- add structured robot-team demand intake in the web app
- add structured site-operator intake in the web app
- create backend `demand_signal` store
- add daily web research pipeline
- publish demand-weighted `capture_jobs`

### Phase 2

- rank Google Places candidates against demand clusters
- add app-visible demand explanations and badges
- add freshness decay and category suppression
- add internal feedback loops from claim / completion / buyer follow-up

### Phase 3

- build explicit metro-level coverage gap maps
- personalize by contributor quality, device capability, and travel radius
- learn payout recommendations from demand plus difficulty plus rights friction

## Evaluation

Do not ship this without evals.

Track:

- precision of top-ranked opportunities
- conversion from surfaced opportunity -> claim
- claim -> completed capture
- completed capture -> buyer follow-up
- false-positive site-type ranking rate
- stale-signal rate
- citation coverage rate

Use LLM evals to test:

- taxonomy mapping
- site-type classification
- workflow extraction
- evidence-strength assignment
- ranking explanation quality

## Current March 2026 Market Read

Inference from current public signal:

- strongest deployment and spending signal is still in warehouses, logistics, manufacturing, and adjacent industrial settings
- retail has real signal, especially grocery and shelf intelligence
- convenience-store-like environments appear more niche and uneven than industrial and grocery demand

So the product should not assume all nearby commercial sites deserve equal visibility.

It should bias toward categories with:

- more explicit buyer pull
- stronger operator willingness
- higher observed deployment maturity
- better internal conversion

## Decision

Yes, Blueprint should build this.

But it should be built as a backend demand-intelligence service that feeds marketplace ranking and mobile surfaces, not as ad hoc logic in the capture app.

## References

- OpenAI models: https://developers.openai.com/api/docs/models
- OpenAI web search: https://developers.openai.com/api/docs/guides/tools-web-search
- OpenAI deep research: https://developers.openai.com/api/docs/guides/deep-research
- OpenAI file search: https://developers.openai.com/api/docs/guides/tools-file-search
- OpenAI evals: https://developers.openai.com/api/docs/guides/evals
- Anthropic web search: https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool
- Google Vertex AI grounding with Google Search: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/grounding/grounding-with-google-search
- Google Places Nearby Search: https://developers.google.com/maps/documentation/places/web-service/nearby-search
- Google Places Text Search: https://developers.google.com/maps/documentation/places/web-service/text-search
- Google Geocoding overview: https://developers.google.com/maps/documentation/geocoding/overview
- Firecrawl docs: https://docs.firecrawl.dev/
- Tavily docs: https://docs.tavily.com/
- Crunchbase API docs: https://data.crunchbase.com/docs/crunchbase-basic-using-api
- BMW physical AI production deployment, Feb. 27, 2026: https://www.press.bmwgroup.com/global/article/detail/T0455864EN/bmw-group-to-deploy-humanoid-robots-in-production-in-germany-for-the-first-time
- Boston Dynamics Stretch logistics deployment: https://bostondynamics.com/case-studies/stretch-enhances-logistics-maintenance-at-otto-group/
- Simbe retail deployment signal: https://www.simberobotics.com/about/newsroom/simbe-marks-10-years-of-tally-the-robot
