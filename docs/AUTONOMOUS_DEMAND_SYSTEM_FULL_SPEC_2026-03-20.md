# Autonomous Demand System Full Spec

Date: 2026-03-20

Status: partial implementation exists in repo; autonomous research + production deployment are not complete

Last pushed commit: `1367a0b`

## Executive Summary

Yes, the goal should be for this system to operate mostly autonomously.

But "autonomous" should mean:

- demand collection can come in automatically and continuously
- web research can run on schedules without manual prompting
- scoring and ranking update automatically
- app worker surfaces and web intake/admin surfaces always read from the latest ranked outputs

It should **not** mean:

- no human controls at all
- no ability to override rankings
- no moderation for abusive submissions
- no auditability

The correct design is:

- autonomous ingestion
- autonomous research
- autonomous scoring
- human-overridable policy and strategy controls

## Product Rule

For MVP:

- no worker-facing web opportunity surface is required
- capturers interact with ranked opportunities primarily through iOS and Android
- web is required for external demand intake and internal admin / ops control surfaces

This system should be treated as:

- app-first for capturer opportunity discovery, acceptance, capture, and upload
- web-first for robot-team intake, site-operator intake, moderation, and ranking controls

## What Exists Right Now

Implemented now:

- shared demand/opportunity models on iOS in [DemandOpportunity.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Models/DemandOpportunity.swift)
- demand-aware `ScanJob` model in [ScanJob.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Models/ScanJob.swift)
- backend API client methods on iOS in [APIService.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/Services/APIService.swift)
- iOS nearby flow calling backend ranking in [NearbyTargetsViewModel.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/ViewModels/NearbyTargetsViewModel.swift)
- iOS home feed preferring backend opportunity feed in [ScanHomeViewModel.swift](/Users/nijelhunt_1/workspace/BlueprintCapture/BlueprintCapture/ViewModels/ScanHomeViewModel.swift)
- Android demand/opportunity models in [DemandOpportunityModels.kt](/Users/nijelhunt_1/workspace/BlueprintCapture/android/app/src/main/kotlin/app/blueprint/capture/data/model/DemandOpportunityModels.kt)
- Android backend API client in [DemandIntelligenceBackendApi.kt](/Users/nijelhunt_1/workspace/BlueprintCapture/android/app/src/main/kotlin/app/blueprint/capture/data/opportunities/DemandIntelligenceBackendApi.kt)
- Android Firestore home-feed demand metadata support in [ScanTargetsRepository.kt](/Users/nijelhunt_1/workspace/BlueprintCapture/android/app/src/main/kotlin/app/blueprint/capture/data/targets/ScanTargetsRepository.kt)
- Android nearby feed calling backend ranking in [ScanViewModel.kt](/Users/nijelhunt_1/workspace/BlueprintCapture/android/app/src/main/kotlin/app/blueprint/capture/ui/screens/ScanViewModel.kt)
- backend normalization and ranking logic in [demand-opportunities.ts](/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/referral-earnings/src/demand-opportunities.ts)
- backend HTTP endpoints in [index.ts](/Users/nijelhunt_1/workspace/BlueprintCapture/cloud/referral-earnings/src/index.ts)

Implemented endpoint contracts now:

- `POST /v1/demand/robot-team-requests`
- `POST /v1/demand/site-operator-submissions`
- `POST /v1/opportunities/feed`

Implemented backend behavior now:

- submissions generate `demand_signals`
- backend can rank nearby candidate places from `demand_signals`
- backend can annotate `capture_jobs` with demand metadata

Not implemented now:

- scheduled web research jobs
- scheduled deep-research jobs
- ingestion from public web signal into `demand_signals`
- event-driven marketplace behavioral signals into `demand_signals`
- moderation pipeline for external submissions
- ops/admin tooling for manual overrides
- production routing from the deployed backend/gateway to these new Firebase handlers

## Product Goal

We want a system that answers two questions automatically:

1. what site types and workflows are in demand right now?
2. which exact nearby locations should be shown to this contributor?

That means the system must continuously turn raw signals into:

- ranked job opportunities
- ranked nearby opportunities
- explanations for why a thing is being shown

## Desired Autonomous Behavior

### Inputs

The system should autonomously combine:

- robot-team requests
- site-operator submissions
- scheduled web-research outputs
- scheduled deep-research outputs
- internal marketplace behavioral events
- approved ops overrides

### Processing

The system should autonomously:

- normalize text into a stable ontology
- score site types and workflows
- decay stale demand
- boost exact operator-approved locations
- suppress low-conversion or stale categories
- republish ranked jobs and nearby opportunities

### Outputs

The system should autonomously update:

- `demand_signals`
- `capture_jobs` demand fields
- demand-ranked nearby feed responses
- optional metro-level opportunity clusters for ops dashboards

## Core Architecture

### 1. Signal Store

Authoritative collection:

- `demand_signals`

Required fields:

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
- `citations`
- `demand_source_kinds`
- `summary`
- `created_at`
- `updated_at`

### 2. Submission Stores

Separate raw-input collections:

- `robot_team_requests`
- `site_operator_submissions`

These keep the original submission payloads for auditability.

### 3. Ranked Jobs

Existing collection:

- `capture_jobs`

Demand metadata written onto each job:

- `site_type`
- `demand_score`
- `opportunity_score`
- `demand_summary`
- `ranking_explanation`
- `demand_source_kinds`
- `suggested_workflows`

### 4. Nearby Opportunity Feed

Request:

- user location
- radius
- limit
- candidate places

Response:

- ranked nearby opportunities
- optionally ranked jobs

## Full Data Flow

### A. Explicit Robot-Team Demand

1. robot team submits structured request
2. backend stores raw request in `robot_team_requests`
3. backend derives normalized `demand_signals`
4. backend refreshes `capture_jobs` demand snapshots
5. next app/web feed reads updated ranking

### B. Site Operator Submission

1. operator submits site details and willingness
2. backend stores raw submission in `site_operator_submissions`
3. backend derives operator-offer `demand_signals`
4. backend refreshes `capture_jobs`
5. feed starts boosting matching or exact sites

### C. Web Research

1. scheduler runs lightweight research job daily
2. job searches target robotics categories and companies
3. extraction pipeline turns results into normalized demand signals with citations
4. stale previous signals are decayed or expired
5. `capture_jobs` and nearby ranking refresh

### D. Internal Marketplace Feedback

1. product emits events such as claim, reserve, complete, buyer_follow_up
2. event consumer converts those into behavioral `demand_signals`
3. ranking adjusts based on actual conversion and buyer pull

## Research Automation Spec

### Daily Research Loop

Purpose:

- find new pilots, deployment announcements, funding, customer rollouts, geography clues

Cadence:

- once per day

Input categories:

- warehouse robotics
- logistics / dock robotics
- manufacturing / industrial robotics
- retail / shelf intelligence
- hospital / service robotics
- hospitality / cleaning
- niche categories such as convenience stores

Pipeline:

1. run web search queries per category
2. crawl official company sites / newsrooms / press releases
3. extract:
   - company
   - site type
   - workflow
   - geography
   - maturity
   - citations
4. score confidence
5. write `demand_signals`

Recommended model/services:

- OpenAI `gpt-5.4-mini` or `gpt-5.4`
- Firecrawl or Tavily for deterministic retrieval
- official source bias whenever possible

### Weekly Deep Research Loop

Purpose:

- rebuild category priors
- revisit strategic weighting
- detect categories with weak real deployment signal

Cadence:

- once per week

Pipeline:

1. run deep research across all target sectors
2. summarize deployment maturity by sector
3. generate category weights
4. write strategic weight config for ranking

Recommended model:

- OpenAI `o3-deep-research`

## Internal Behavioral Signal Spec

These events should become signals automatically:

- opportunity surfaced
- opportunity clicked
- reservation created
- claim/check-in created
- capture completed
- qualification approved
- recapture requested
- buyer follow-up
- repeat buyer request
- operator opt-in / operator decline

Suggested derived fields:

- `behavior_type`
- `site_type`
- `workflow`
- `geo_scope`
- `conversion_weight`
- `signal_confidence`

This can feed `internal_behavioral_signal` records in `demand_signals`.

## Ranking Formula

Current in-repo ranking is simple and real-time.

Target production formula:

`opportunity_score = demand_score * operator_readiness * capture_feasibility * geo_relevance * freshness * strategic_weight - suppression_penalties`

Recommended subcomponents:

- `demand_score`
  - explicit request weight
  - operator-offer weight
  - cited web-signal weight
  - internal behavioral weight
- `operator_readiness`
  - explicit operator opt-in
  - consent readiness
  - access readiness
- `capture_feasibility`
  - privacy risk
  - rights friction
  - likely accessibility
- `geo_relevance`
  - user proximity
  - target metro priority
- `freshness`
  - decays stale research
- `strategic_weight`
  - controlled by weekly research and ops overrides
- `suppression_penalties`
  - low conversion
  - blocked rights profile
  - oversupplied category

## Deployment Requirements

The code exists in this repo, but next session must make sure the production backend actually exposes these routes.

Required work:

1. confirm where `BLUEPRINT_BACKEND_BASE_URL` points in iOS and Android
2. ensure the deployed backend gateway forwards:
   - `/v1/demand/robot-team-requests`
   - `/v1/demand/site-operator-submissions`
   - `/v1/opportunities/feed`
3. if the production backend is not Firebase Functions directly:
   - either proxy these routes to Firebase
   - or port the TypeScript logic into the main backend service

If this routing is not finished, clients will compile but won’t hit a live production endpoint.

## Web Product Requirements

Worker-facing web opportunity browsing is not required for MVP.

Required web scope for MVP:

- robot-team intake
- site-operator intake
- ops / admin visibility and controls

The next session should assume this feature is incomplete without web intake and admin surfaces.

Required UI/forms:

### Robot Team Intake Form

Fields:

- company name
- requester name
- requester email
- target geography
- target metros
- site types
- workflows
- constraints
- target KPIs
- urgency
- notes
- optional citations/links

### Site Operator Intake Form

Fields:

- operator name
- operator email
- company name
- site name
- site address
- latitude / longitude if known
- site types
- workflows
- access readiness
- consent readiness
- capture windows
- restrictions
- notes

These forms should call the endpoints above directly or through the main backend.

## Ops / Admin Requirements

Needed for safe autonomy:

- view all active `demand_signals`
- filter by source, site type, company, geography
- resolve duplicates
- disable bad submissions
- manually boost or suppress categories
- inspect ranking explanations for a job or place

Without this, the system is autonomous but hard to control.

## iOS / Android Parity Rule

The parity rule for next session is:

- do not ship a ranking or intake contract on iOS only
- do not ship a ranking field on Android only
- any backend request/response field added must be mirrored in both platforms

Current parity status:

- both platforms have demand models
- both platforms can consume ranked nearby opportunities
- both platforms can consume demand-aware jobs
- Android home feed still depends more on Firestore job snapshots than iOS does

That is acceptable, but if new fields are added next session, both clients must be updated.

## Testing Requirements For Next Session

### Backend

Required:

- unit tests for signal normalization
- unit tests for ranking logic
- unit tests for stale-signal decay
- unit tests for operator-offer boosting

### iOS

Required:

- API decode tests for all new feed payloads
- ranking tests for `ScanHomeViewModel`
- nearby ranking tests if additional mapping logic is added

### Android

Required:

- Kotlin compile check
- serialization tests for feed payloads
- repository ranking tests for demand-aware home feed
- nearby transformation tests from ranked opportunities to `ScanTarget`

## Known Current Verification State

Already verified:

- `cloud/referral-earnings`: `npm test` passed
- Android: `./gradlew :app:compileDebugKotlin` passed

Partially verified:

- iOS targeted `xcodebuild test` was rerun against an available simulator after fixing Codable issues
- the run advanced past the earlier compile failures
- it did not complete to a final pass/fail within the available session time

Next session should rerun:

```bash
xcodebuild test -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' -only-testing:BlueprintCaptureTests/APIServiceTests -only-testing:BlueprintCaptureTests/ScanHomeAndUploadTests
```

## What Next Session Should Do, In Order

1. verify iOS targeted tests complete successfully
2. verify backend routes are reachable from the real deployed backend base URL
3. build the web intake forms for robot teams and site operators
4. deploy or wire the new endpoints into production
5. add scheduled daily web research job
6. add scheduled weekly deep research job
7. add event-driven internal behavioral signal writer
8. add admin visibility / moderation tools
9. add freshness decay / archival for stale demand signals
10. add analytics on feed quality and conversion

## Answer: Should This Work Without Human Intervention?

Yes, mostly.

Specifically:

- collection should be autonomous
- research should be autonomous
- scoring should be autonomous
- publishing should be autonomous

But there should still be human controls for:

- moderation
- legal/compliance exceptions
- strategic boosts/suppressions
- debugging

So the answer is:

- autonomous by default
- overridable by ops

## Answer: MapKit vs Google Places

Yes, you can use Apple MapKit search capabilities on iOS.

Current Apple docs show native MapKit supports:

- local search
- search completions
- points-of-interest search

Relevant Apple docs:

- [Searching, displaying, and navigating to places](https://developer.apple.com/documentation/mapkit/searching-displaying-and-navigating-to-places)
- [Apple Maps / MapKit overview](https://developer.apple.com/maps/)

Apple also positions MapKit JS as available "at no cost" on the web resources page:

- [Apple Maps resources](https://developer.apple.com/maps/resources/)

Google Places, by contrast, is explicitly pay-as-you-go and Places Nearby / Text Search / Details are billable SKUs:

- [Places API Usage and Billing](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing)
- [Google Maps Platform pricing overview](https://developers.google.com/maps/billing-and-pricing/overview)
- [March 2025 pricing changes](https://developers.google.com/maps/billing-and-pricing/march-2025)

### Recommendation

Use a hybrid strategy:

- iOS native app: prefer MapKit / `MKLocalSearch` / `MKLocalSearchCompleter` for first-party candidate discovery where quality is sufficient
- Android and cross-platform/backend candidate discovery: keep Google Places or another cross-platform POI source
- backend ranking layer stays provider-agnostic

Why:

- Apple search can reduce Google cost on iOS
- Google still gives stronger cross-platform consistency
- backend ranking should not care where candidates came from

### Practical Rule

Do not couple demand ranking to Google Places.

Treat place discovery as a swappable adapter:

- `AppleMapKitCandidateProvider` on iOS
- `GooglePlacesCandidateProvider` cross-platform
- `DemandRankingService` behind both

That lets you reduce Google cost later without rewriting the demand system.

### Important Apple Constraint

Apple’s license terms restrict scraping/caching/mining Apple map data beyond permitted uses, so do not design a research or bulk-indexing system around harvesting Apple Maps data.

Relevant policy source:

- [Apple Developer Program License Agreement page](https://developer.apple.com/fr/support/terms/apple-developer-program-license-agreement/)

That means Apple MapKit is good for user-facing place search in the app, but not as your bulk research dataset backbone.

## Final Recommendation

Build the autonomous system around:

- backend-owned demand signals
- backend-owned ranking
- scheduled web research
- event-driven feedback loops
- client-side place candidate providers that are swappable

And for place discovery specifically:

- use MapKit on iOS where it reduces cost
- keep Google Places where you need cross-platform consistency
- never let either provider define the business logic
