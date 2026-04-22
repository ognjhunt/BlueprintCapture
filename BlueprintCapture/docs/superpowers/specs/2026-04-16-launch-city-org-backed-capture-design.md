# Launch City Org-Backed Capture Design

**Date:** 2026-04-16

**Goal**

Make BlueprintCapture's public-facing capture cards and geo-lock behavior derive from the same launch truth used by Blueprint's autonomous city-launch organization, while adding a nearby-candidate scan loop that feeds agents new places to research and qualify without exposing unapproved places as capture opportunities.

**Problem**

The current system has two different truths:

- The iOS app hardcodes supported launch cities in `LaunchCityGateService.swift`.
- The web app and autonomous org already maintain city-launch activations, founder approvals, launch ledgers, and org-backed capture targets.

The app also mixes approved and unapproved opportunity sources:

- It can merge org-backed launch targets into the nearby feed.
- It still falls back to generic nearby discovery and inferred opportunities, which means users can see cards that do not correlate to org research, qualification, or outbound launch work.

This creates drift in three places:

1. geo-lock status
2. public capture cards
3. the handoff between app-discovered nearby spaces and the autonomous org

**Desired Product Behavior**

1. Public capture cards are strictly limited to:
- org-backed launch targets that have been qualified and promoted into the city-launch ledger
- approved jobs that are already valid capture opportunities

2. On signup and each app open:
- the app scans nearby locations using the existing discovery stack, with MapKit fallback
- the scan does not create public cards directly
- the scan sends nearby candidate places to the backend as raw signals for org review

3. The autonomous org can then:
- research those signals
- qualify or reject them
- promote qualified signals into launch prospects / launch targets
- eventually make them visible as real capture cards after approval

4. The UI should clearly show two different states:
- places that are open to capture now
- nearby places that are being reviewed for launch fit and are not yet actionable

5. When a reviewed place is approved and becomes public:
- notify the user who surfaced it
- optionally notify nearby eligible users in that launch market

## Non-Goals

- Do not make app-side discovery itself authoritative for launch approval.
- Do not let inferred nearby places become capture cards before org review.
- Do not fabricate launch readiness, city-live claims, or capture approval from soft signals alone.
- Do not bypass rights, privacy, founder approval, or launch activation state.

## Context And Existing Surfaces

### iOS app

- `BlueprintCaptureApp.swift` wraps the app with `LaunchCityGateRootView`, which currently depends on a hardcoded city list.
- `Services/LaunchCityGateService.swift` hardcodes supported cities as Austin, Durham, and San Francisco.
- `ViewModels/NearbyTargetsViewModel.swift` fetches generic nearby targets, then merges in org-backed launch targets from `v1/creator/city-launch/targets`.
- `ViewModels/ScanHomeViewModel.swift` also mixes approved and inferred nearby opportunities for the "Captures" home surface.

### Web app / backend

- `server/routes/creator.ts` already exposes `GET /v1/creator/city-launch/targets`.
- `server/utils/cityLaunchCaptureTargets.ts` builds org-backed targets from launch activations and launch prospects.
- `server/utils/cityLaunchLedgers.ts` defines activation and prospect records tied to launch operations.
- `server/utils/cityLaunchProfiles.ts`, `cityLaunchPolicy.ts`, and related files hold launch doctrine and focus-city behavior.

### Autonomous organization

- `AUTONOMOUS_ORG.md` defines `city-launch-agent` and `city-demand-agent`.
- Org outputs are written to `ops/paperclip/reports/city-launch-execution/...`.
- Those outputs include city launch plans, target ledgers, demand artifacts, issue bundles, and founder approvals.

## Product Requirements

### 1. Single Source Of Truth For Launch Availability

The backend must become the source of truth for:

- which cities are launch-supported for the capture app
- whether a user's current city is allowed to unlock the app
- which places in that city are open to capture now

The iOS app must stop hardcoding the supported city list.

### 2. Strict Public Card Filtering

Public-facing capture cards shown to users must only come from:

- org-backed launch targets that satisfy the backend's launch-feed eligibility rules
- existing approved jobs

Generic inferred nearby places must not appear as actionable capture cards.

### 3. Nearby Candidate Intake

On:

- first signup completion
- app open
- manual refresh when useful

the app must perform a nearby place scan and submit candidate signals to the backend.

Recommended defaults:

- radius: 10 miles
- maximum results per scan: 25
- cooldown: once every 12 hours per user per coarse area, unless manually refreshed

Each candidate signal should carry:

- user id
- discovery timestamp
- lat/lng
- place name
- formatted address if available
- provider place id if available
- place types / categories
- city / state guess if available
- discovery provider
- client app version

These signals are inputs to org review, not approvals.

### 4. Separate Candidate Signal Queue From Approved Launch Prospects

Raw app-discovered places must not be written directly into the approved launch prospect ledger.

Instead, they should land in a separate store, for example:

- `cityLaunchCandidateSignals`

This queue exists to preserve provenance and avoid conflating:

- "a user saw a nearby place"
- "Blueprint approved this place as a launch target"

The org can later promote qualified signals into proper launch prospects or targets.

### 5. Under-Review User Surface

The app should show a non-actionable section for nearby places that have entered review.

Recommended wording:

- section title: `Under Review Near You`
- supporting text: `We’re checking nearby spaces against launch criteria. If one is approved, we’ll notify you.`

These cards must be visually distinct from open capture cards:

- muted appearance
- no reserve / start capture actions
- clear status labeling that they are not open yet

### 6. Notifications For Newly Opened Nearby Captures

When a candidate progresses from under review to approved and becomes part of the public feed:

- notify the user who surfaced the place
- optionally notify other eligible nearby users if product rules allow it

Notification copy should be factual:

- title: `New Capture Opened Nearby`
- body: `A nearby space was approved for capture.`

No notifications should fire at the moment a place enters review.

## Architecture

### Backend surfaces

Add backend endpoints for three concerns:

1. `launch status`
- return whether the user's city is launch-supported
- return the authoritative list of supported cities for UI copy

2. `candidate intake`
- accept nearby place signals from the app
- dedupe repeated signals
- persist raw review candidates with provenance

3. `under-review feed`
- return nearby candidate signals that are currently in the review pipeline
- filtered to the user's current location / city
- include non-actionable display fields only

Existing launch target feed stays as the approved public feed, but the app should treat it as authoritative rather than additive.

### iOS surfaces

Split the user-facing feed into two layers:

1. `Open to Capture`
- approved jobs
- org-backed launch targets

2. `Under Review Near You`
- review candidates submitted from app discovery and currently being evaluated

The geo-lock view should be driven by backend launch status, not a local hardcoded city matcher.

## Data Model

### New backend record: CityLaunchCandidateSignal

Suggested fields:

- `id`
- `dedupeKey`
- `creatorId`
- `city`
- `citySlug`
- `name`
- `address`
- `lat`
- `lng`
- `provider`
- `providerPlaceId`
- `types`
- `status`
- `reviewState`
- `submittedAtIso`
- `lastSeenAtIso`
- `seenCount`
- `sourceContext`

Suggested status values:

- `queued`
- `in_review`
- `promoted`
- `rejected`

Suggested source context values:

- `app_open_scan`
- `signup_scan`
- `manual_refresh`

### Approved launch targets remain separate

Approved public targets continue to derive from:

- city launch activations
- approved / onboarded / capturing launch prospects

That keeps the public feed tied to org decisions rather than raw app signals.

## UX Specification

### Geo-lock

If backend says the current city is supported:

- unlock the app
- show the city as live

If backend says unsupported:

- show not live yet state
- show the authoritative supported city list returned by backend
- offer request-launch-access CTA

### Approved capture feed

Section title:

- `Open to Capture`

Behavior:

- cards are actionable
- eligible for reserve / start capture flows
- sourced only from approved jobs and org-backed targets

### Under review feed

Section title:

- `Under Review Near You`

Behavior:

- cards are non-actionable
- explain that Blueprint is evaluating them against launch criteria
- show simple metadata only: name, approximate area, review status note

### Empty states

If no approved cards but under-review cards exist:

- headline: `Nothing Open Yet`
- subtext: `We’re reviewing nearby spaces for launch fit. If one is approved, we’ll notify you.`

If neither approved nor under-review cards exist:

- headline: `We’re Not Live Nearby Yet`
- subtext: `Blueprint is still scanning and qualifying spaces in this area.`

## Operational Flow

1. User signs up or opens the app.
2. App determines current location.
3. App fetches launch status from backend.
4. If city is supported, app loads approved public feed.
5. App runs nearby scan in the background.
6. App submits nearby candidate signals to backend.
7. Backend dedupes and stores candidate signals.
8. Candidate signals become visible in the under-review feed.
9. Org agents review and qualify candidates.
10. If a candidate is promoted into launch prospects / approved targets, it begins appearing in the approved public feed.
11. Notification fires to relevant users only after approval.

## Testing Requirements

### Backend

- launch status endpoint returns only supported launch cities from authoritative activation state
- candidate intake dedupes repeated submissions
- under-review feed excludes promoted / rejected candidates
- approved launch feed excludes raw candidate signals
- approved launch feed still includes qualified launch prospects

### iOS

- launch gate no longer relies on hardcoded cities
- unsupported city shows backend city list
- approved feed excludes inferred nearby discovery cards
- under-review section renders when candidate signals exist
- nearby scan submits candidates on app open / signup with cooldown behavior

## Risks And Guards

### Risk: launch drift between iOS and backend

Guard:

- remove hardcoded city truth from the app
- route city support through backend launch status

### Risk: candidate spam or duplicates

Guard:

- coarse geospatial and provider-place dedupe
- cooldown on submission
- track `seenCount` and `lastSeenAtIso` rather than writing a fresh record every time

### Risk: exposing unapproved places as open cards

Guard:

- keep raw candidate signals in a separate collection
- make approved feed query only approved jobs and org-qualified launch targets

### Risk: misleading users about review state

Guard:

- use explicit, non-actionable under-review UI
- avoid copy that implies approval or imminent payout

## Rollout

1. Add backend launch status, candidate intake, and under-review feed.
2. Add backend tests for new launch and candidate behavior.
3. Switch iOS geo-lock to backend launch status.
4. Switch iOS approved feed to approved-only sources.
5. Add iOS nearby candidate submission loop.
6. Add iOS under-review UI section and notifications wiring.

## Open Decisions Locked For This Spec

- Public capture cards are strictly limited to org-backed launch targets and approved jobs.
- Nearby app discovery is still valuable, but only as candidate intake into agent review.
- Default scan radius is 10 miles.
- Nearby review section wording is `Under Review Near You`.
- Notification happens only after approval, not at review intake.
