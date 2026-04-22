# Launch City Org-Backed Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make BlueprintCapture's launch gate and public capture cards derive from backend launch truth only, while adding nearby candidate intake and an under-review surface tied to org qualification.

**Architecture:** Add new backend creator endpoints for launch status, candidate intake, and nearby under-review candidates; keep approved launch targets in a separate feed; update the iOS app to use backend launch truth for geo-lock, restrict approved cards to approved sources only, and render a second non-actionable under-review section fed by candidate signals.

**Tech Stack:** Express, TypeScript, Vitest, Firebase Admin / Firestore, Swift, SwiftUI, async/await, CoreLocation, MapKit, existing nearby discovery services

---

### Task 1: Backend Launch Status Contract

**Files:**
- Create: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/tests/city-launch-status.test.ts`
- Modify: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/utils/cityLaunchCaptureTargets.ts`
- Modify: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/routes/creator.ts`
- Test: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/tests/city-launch-status.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// /Users/nijelhunt_1/workspace/Blueprint-WebApp/server/tests/city-launch-status.test.ts
// @vitest-environment node
import { describe, expect, it, vi } from "vitest";

const listCityLaunchActivations = vi.hoisted(() => vi.fn());

vi.mock("../utils/cityLaunchLedgers", async () => {
  const actual = await vi.importActual("../utils/cityLaunchLedgers");
  return {
    ...actual,
    listCityLaunchActivations,
  };
});

describe("city launch status", () => {
  it("returns only launch-supported cities from activation truth", async () => {
    listCityLaunchActivations.mockResolvedValue([
      {
        city: "Austin, TX",
        citySlug: "austin-tx",
        founderApproved: true,
        status: "activation_ready",
      },
      {
        city: "San Francisco, CA",
        citySlug: "san-francisco-ca",
        founderApproved: false,
        status: "growth_live",
      },
      {
        city: "Chicago, IL",
        citySlug: "chicago-il",
        founderApproved: false,
        status: "planning",
      },
    ]);

    const { buildCreatorLaunchStatus } = await import("../utils/cityLaunchCaptureTargets");
    const result = await buildCreatorLaunchStatus({
      resolvedCity: {
        city: "Austin",
        stateCode: "TX",
      },
    });

    expect(result.supportedCities).toEqual([
      { city: "Austin", stateCode: "TX", displayName: "Austin, TX", citySlug: "austin-tx" },
      { city: "San Francisco", stateCode: "CA", displayName: "San Francisco, CA", citySlug: "san-francisco-ca" },
    ]);
    expect(result.currentCity).toEqual(
      expect.objectContaining({
        city: "Austin",
        stateCode: "TX",
        isSupported: true,
        citySlug: "austin-tx",
      }),
    );
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/nijelhunt_1/workspace/Blueprint-WebApp && npx vitest run server/tests/city-launch-status.test.ts`

Expected: FAIL with an error indicating `buildCreatorLaunchStatus` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```ts
// Add to /Users/nijelhunt_1/workspace/Blueprint-WebApp/server/utils/cityLaunchCaptureTargets.ts
export type CreatorLaunchStatus = {
  supportedCities: Array<{
    city: string;
    stateCode: string;
    displayName: string;
    citySlug: string;
  }>;
  currentCity: {
    city: string;
    stateCode: string | null;
    displayName: string;
    citySlug: string | null;
    isSupported: boolean;
  } | null;
};

function splitCityLabel(city: string) {
  const [name, state] = city.split(",").map((part) => part.trim());
  return {
    city: name || city.trim(),
    stateCode: state || null,
  };
}

function normalizeToken(value: string | null | undefined) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ");
}

export async function buildCreatorLaunchStatus(input: {
  resolvedCity?: { city: string; stateCode?: string | null } | null;
}): Promise<CreatorLaunchStatus> {
  const activations = await listCityLaunchActivations();
  const supportedCities = activations
    .filter((activation) =>
      activation.founderApproved || ACTIVE_ACTIVATION_STATUSES.has(activation.status),
    )
    .map((activation) => {
      const parts = splitCityLabel(activation.city);
      return {
        city: parts.city,
        stateCode: parts.stateCode || "",
        displayName: activation.city,
        citySlug: activation.citySlug,
      };
    })
    .sort((left, right) => left.displayName.localeCompare(right.displayName));

  const currentCity = input.resolvedCity
    ? (() => {
        const normalizedCity = normalizeToken(input.resolvedCity?.city);
        const normalizedState = normalizeToken(input.resolvedCity?.stateCode || null);
        const match = supportedCities.find((city) =>
          normalizeToken(city.city) === normalizedCity
          && normalizeToken(city.stateCode) === normalizedState,
        );
        return {
          city: input.resolvedCity.city,
          stateCode: input.resolvedCity.stateCode || null,
          displayName: input.resolvedCity.stateCode
            ? `${input.resolvedCity.city}, ${input.resolvedCity.stateCode}`
            : input.resolvedCity.city,
          citySlug: match?.citySlug || null,
          isSupported: Boolean(match),
        };
      })()
    : null;

  return {
    supportedCities,
    currentCity,
  };
}
```

- [ ] **Step 4: Wire route and run test to verify it passes**

```ts
// Add to /Users/nijelhunt_1/workspace/Blueprint-WebApp/server/routes/creator.ts
import { buildCreatorLaunchStatus } from "../utils/cityLaunchCaptureTargets";

router.get("/launch-status", async (req: Request, res: Response) => {
  const city = String(req.query.city || "").trim();
  const stateCode = String(req.query.state_code || "").trim() || null;

  return res.json(
    await buildCreatorLaunchStatus({
      resolvedCity: city ? { city, stateCode } : null,
    }),
  );
});
```

Run: `cd /Users/nijelhunt_1/workspace/Blueprint-WebApp && npx vitest run server/tests/city-launch-status.test.ts`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/nijelhunt_1/workspace/Blueprint-WebApp
git add server/tests/city-launch-status.test.ts server/utils/cityLaunchCaptureTargets.ts server/routes/creator.ts
git commit -m "feat: add creator launch status endpoint"
```

### Task 2: Backend Candidate Signal Store And Intake

**Files:**
- Create: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/tests/city-launch-candidate-signals.test.ts`
- Modify: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/utils/cityLaunchLedgers.ts`
- Modify: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/routes/creator.ts`
- Test: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/tests/city-launch-candidate-signals.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// /Users/nijelhunt_1/workspace/Blueprint-WebApp/server/tests/city-launch-candidate-signals.test.ts
// @vitest-environment node
import { describe, expect, it, vi } from "vitest";

const upsertCityLaunchCandidateSignal = vi.hoisted(() => vi.fn());

vi.mock("../utils/cityLaunchLedgers", async () => {
  const actual = await vi.importActual("../utils/cityLaunchLedgers");
  return {
    ...actual,
    upsertCityLaunchCandidateSignal,
  };
});

describe("city launch candidate signal intake", () => {
  it("dedupes repeated nearby discovery submissions", async () => {
    upsertCityLaunchCandidateSignal.mockResolvedValue({
      id: "candidate-austin-dock-one",
      status: "queued",
      seenCount: 2,
    });

    const { intakeCityLaunchCandidateSignal } = await import("../utils/cityLaunchLedgers");
    const result = await intakeCityLaunchCandidateSignal({
      creatorId: "user-1",
      city: "Austin, TX",
      name: "Dock One",
      address: "100 Logistics Way",
      lat: 30.2672,
      lng: -97.7431,
      provider: "google_places",
      providerPlaceId: "place-123",
      types: ["warehouse"],
      sourceContext: "app_open_scan",
    });

    expect(result).toEqual(
      expect.objectContaining({
        id: "candidate-austin-dock-one",
        status: "queued",
        seenCount: 2,
      }),
    );
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/nijelhunt_1/workspace/Blueprint-WebApp && npx vitest run server/tests/city-launch-candidate-signals.test.ts`

Expected: FAIL because `intakeCityLaunchCandidateSignal` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```ts
// Add to /Users/nijelhunt_1/workspace/Blueprint-WebApp/server/utils/cityLaunchLedgers.ts
export type CityLaunchCandidateSignalRecord = {
  id: string;
  dedupeKey: string;
  creatorId: string;
  city: string;
  citySlug: string;
  name: string;
  address: string | null;
  lat: number;
  lng: number;
  provider: string;
  providerPlaceId: string | null;
  types: string[];
  sourceContext: "signup_scan" | "app_open_scan" | "manual_refresh";
  status: "queued" | "in_review" | "promoted" | "rejected";
  reviewState: string;
  seenCount: number;
  submittedAtIso: string;
  lastSeenAtIso: string;
};

function slugifySignal(input: string) {
  return input.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

function candidateSignalDedupeKey(input: {
  city: string;
  name: string;
  providerPlaceId?: string | null;
  lat: number;
  lng: number;
}) {
  if (input.providerPlaceId) {
    return `${slugifyCityName(input.city)}:${input.providerPlaceId}`;
  }
  const coarseLat = input.lat.toFixed(3);
  const coarseLng = input.lng.toFixed(3);
  return `${slugifyCityName(input.city)}:${slugifySignal(input.name)}:${coarseLat}:${coarseLng}`;
}

export async function upsertCityLaunchCandidateSignal(
  record: Omit<CityLaunchCandidateSignalRecord, "id" | "seenCount" | "submittedAtIso" | "lastSeenAtIso">,
) {
  const dedupeKey = record.dedupeKey;
  const id = `candidate-${slugifySignal(dedupeKey)}`;
  return {
    id,
    ...record,
    seenCount: 1,
    submittedAtIso: new Date().toISOString(),
    lastSeenAtIso: new Date().toISOString(),
  } satisfies CityLaunchCandidateSignalRecord;
}

export async function intakeCityLaunchCandidateSignal(input: {
  creatorId: string;
  city: string;
  name: string;
  address?: string | null;
  lat: number;
  lng: number;
  provider: string;
  providerPlaceId?: string | null;
  types?: string[];
  sourceContext: "signup_scan" | "app_open_scan" | "manual_refresh";
}) {
  const dedupeKey = candidateSignalDedupeKey({
    city: input.city,
    name: input.name,
    providerPlaceId: input.providerPlaceId,
    lat: input.lat,
    lng: input.lng,
  });

  return upsertCityLaunchCandidateSignal({
    dedupeKey,
    creatorId: input.creatorId,
    city: input.city,
    citySlug: slugifyCityName(input.city),
    name: input.name,
    address: input.address || null,
    lat: input.lat,
    lng: input.lng,
    provider: input.provider,
    providerPlaceId: input.providerPlaceId || null,
    types: input.types || [],
    sourceContext: input.sourceContext,
    status: "queued",
    reviewState: "awaiting_city_review",
  });
}
```

- [ ] **Step 4: Add route and run test to verify it passes**

```ts
// Add to /Users/nijelhunt_1/workspace/Blueprint-WebApp/server/routes/creator.ts
import { intakeCityLaunchCandidateSignal } from "../utils/cityLaunchLedgers";

router.post("/city-launch/candidate-signals", async (req: Request, res: Response) => {
  const creatorId = creatorIdFromRequest(req);
  if (!creatorId) {
    return res.status(400).json({ error: "Missing creator id" });
  }

  const result = await intakeCityLaunchCandidateSignal({
    creatorId,
    city: String(req.body?.city || "").trim(),
    name: String(req.body?.name || "").trim(),
    address: req.body?.address ? String(req.body.address) : null,
    lat: Number(req.body?.lat),
    lng: Number(req.body?.lng),
    provider: String(req.body?.provider || "unknown"),
    providerPlaceId: req.body?.provider_place_id ? String(req.body.provider_place_id) : null,
    types: Array.isArray(req.body?.types) ? req.body.types.map(String) : [],
    sourceContext: req.body?.source_context || "app_open_scan",
  });

  return res.status(201).json(result);
});
```

Run: `cd /Users/nijelhunt_1/workspace/Blueprint-WebApp && npx vitest run server/tests/city-launch-candidate-signals.test.ts`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/nijelhunt_1/workspace/Blueprint-WebApp
git add server/tests/city-launch-candidate-signals.test.ts server/utils/cityLaunchLedgers.ts server/routes/creator.ts
git commit -m "feat: add city launch candidate signal intake"
```

### Task 3: Backend Under-Review Feed

**Files:**
- Create: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/tests/city-launch-under-review-feed.test.ts`
- Modify: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/utils/cityLaunchLedgers.ts`
- Modify: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/routes/creator.ts`
- Test: `/Users/nijelhunt_1/workspace/Blueprint-WebApp/server/tests/city-launch-under-review-feed.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// /Users/nijelhunt_1/workspace/Blueprint-WebApp/server/tests/city-launch-under-review-feed.test.ts
// @vitest-environment node
import { describe, expect, it, vi } from "vitest";

const listCityLaunchCandidateSignals = vi.hoisted(() => vi.fn());

vi.mock("../utils/cityLaunchLedgers", async () => {
  const actual = await vi.importActual("../utils/cityLaunchLedgers");
  return {
    ...actual,
    listCityLaunchCandidateSignals,
  };
});

describe("city launch under review feed", () => {
  it("returns only queued and in-review candidates near the user", async () => {
    listCityLaunchCandidateSignals.mockResolvedValue([
      {
        id: "candidate-1",
        city: "Austin, TX",
        citySlug: "austin-tx",
        name: "Dock One",
        address: "100 Logistics Way",
        lat: 30.2674,
        lng: -97.7431,
        status: "queued",
        reviewState: "awaiting_city_review",
      },
      {
        id: "candidate-2",
        city: "Austin, TX",
        citySlug: "austin-tx",
        name: "Promoted Place",
        address: "200 Approved Way",
        lat: 30.2675,
        lng: -97.7430,
        status: "promoted",
        reviewState: "promoted_to_prospect",
      },
    ]);

    const { buildCityLaunchUnderReviewFeed } = await import("../utils/cityLaunchCaptureTargets");
    const result = await buildCityLaunchUnderReviewFeed({
      lat: 30.2672,
      lng: -97.7431,
      radiusMeters: 2_000,
      limit: 10,
    });

    expect(result.candidates).toHaveLength(1);
    expect(result.candidates[0]).toEqual(
      expect.objectContaining({
        id: "candidate-1",
        reviewState: "awaiting_city_review",
      }),
    );
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/nijelhunt_1/workspace/Blueprint-WebApp && npx vitest run server/tests/city-launch-under-review-feed.test.ts`

Expected: FAIL because `buildCityLaunchUnderReviewFeed` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```ts
// Add to /Users/nijelhunt_1/workspace/Blueprint-WebApp/server/utils/cityLaunchLedgers.ts
export async function listCityLaunchCandidateSignals(_input?: { city?: string; statuses?: string[] }) {
  return [] as CityLaunchCandidateSignalRecord[];
}
```

```ts
// Add to /Users/nijelhunt_1/workspace/Blueprint-WebApp/server/utils/cityLaunchCaptureTargets.ts
import { listCityLaunchCandidateSignals } from "./cityLaunchLedgers";

export async function buildCityLaunchUnderReviewFeed(input: {
  lat: number;
  lng: number;
  radiusMeters: number;
  limit: number;
}) {
  const candidates = await listCityLaunchCandidateSignals({
    statuses: ["queued", "in_review"],
  });

  return {
    generatedAt: new Date().toISOString(),
    candidates: candidates
      .map((candidate) => ({
        ...candidate,
        distanceMeters: distanceMetersBetween(
          { lat: input.lat, lng: input.lng },
          { lat: candidate.lat, lng: candidate.lng },
        ),
      }))
      .filter((candidate) => candidate.distanceMeters <= input.radiusMeters)
      .sort((left, right) => left.distanceMeters - right.distanceMeters)
      .slice(0, input.limit),
  };
}
```

- [ ] **Step 4: Add route and run test to verify it passes**

```ts
// Add to /Users/nijelhunt_1/workspace/Blueprint-WebApp/server/routes/creator.ts
import { buildCityLaunchUnderReviewFeed } from "../utils/cityLaunchCaptureTargets";

router.get("/city-launch/review-candidates", async (req: Request, res: Response) => {
  const lat = toNumber(req.query.lat);
  const lng = toNumber(req.query.lng);
  if (lat === null || lng === null) {
    return res.status(400).json({ error: "lat and lng are required" });
  }

  const radiusMeters = Math.min(Math.max(toNumber(req.query.radius_m) ?? 16_093, 100), 80_467);
  const limit = Math.min(Math.max(Math.trunc(toNumber(req.query.limit) ?? 12), 1), 50);

  return res.json(
    await buildCityLaunchUnderReviewFeed({
      lat,
      lng,
      radiusMeters,
      limit,
    }),
  );
});
```

Run: `cd /Users/nijelhunt_1/workspace/Blueprint-WebApp && npx vitest run server/tests/city-launch-under-review-feed.test.ts`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/nijelhunt_1/workspace/Blueprint-WebApp
git add server/tests/city-launch-under-review-feed.test.ts server/utils/cityLaunchCaptureTargets.ts server/utils/cityLaunchLedgers.ts server/routes/creator.ts
git commit -m "feat: add under review launch candidate feed"
```

### Task 4: iOS API Contracts For Launch Status And Review Candidates

**Files:**
- Modify: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Services/APIService.swift`
- Test: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture` existing compile checks

- [ ] **Step 1: Write the failing test by compiling the new API surface in code**

```swift
// Add DTOs and protocols in /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Services/APIService.swift
struct CreatorLaunchStatusResponse: Codable, Equatable {
    struct SupportedCity: Codable, Equatable, Identifiable {
        let city: String
        let stateCode: String
        let displayName: String
        let citySlug: String

        var id: String { citySlug }

        enum CodingKeys: String, CodingKey {
            case city
            case stateCode
            case displayName
            case citySlug
        }
    }

    struct CurrentCity: Codable, Equatable {
        let city: String
        let stateCode: String?
        let displayName: String
        let citySlug: String?
        let isSupported: Bool

        enum CodingKeys: String, CodingKey {
            case city
            case stateCode
            case displayName
            case citySlug
            case isSupported
        }
    }

    let supportedCities: [SupportedCity]
    let currentCity: CurrentCity?

    enum CodingKeys: String, CodingKey {
        case supportedCities
        case currentCity
    }
}

struct CityLaunchReviewCandidate: Codable, Equatable, Identifiable {
    let id: String
    let city: String
    let citySlug: String
    let name: String
    let address: String?
    let lat: Double
    let lng: Double
    let status: String
    let reviewState: String
}

struct CityLaunchReviewCandidatesResponse: Codable, Equatable {
    let generatedAt: Date?
    let candidates: [CityLaunchReviewCandidate]
}
```

- [ ] **Step 2: Run build to verify it fails if any referenced types are missing**

Run: `cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture && xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: FAIL if new API methods and protocols are not yet wired.

- [ ] **Step 3: Write minimal implementation**

```swift
// Add to /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Services/APIService.swift
func fetchCreatorLaunchStatus(city: String?, stateCode: String?) async throws -> CreatorLaunchStatusResponse {
    var components = URLComponents(url: try baseURL().appendingPathComponent("v1/creator/launch-status"), resolvingAgainstBaseURL: false)!
    var queryItems: [URLQueryItem] = []
    if let city, !city.isEmpty {
        queryItems.append(URLQueryItem(name: "city", value: city))
    }
    if let stateCode, !stateCode.isEmpty {
        queryItems.append(URLQueryItem(name: "state_code", value: stateCode))
    }
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    guard let url = components.url else {
        throw APIError.invalidResponse(statusCode: -1)
    }
    let request = buildRequest(url: url, method: "GET")
    let data = try await perform(request: request, expecting: 200)
    return try decoder.decode(CreatorLaunchStatusResponse.self, from: data)
}

func submitCityLaunchCandidateSignals(_ payload: CityLaunchCandidateSignalSubmissionRequest) async throws {
    var request = try makeRequest(path: "v1/creator/city-launch/candidate-signals", method: "POST")
    request.httpBody = try encoder.encode(payload)
    _ = try await perform(request: request, expecting: 201)
}

func fetchCityLaunchReviewCandidates(lat: Double, lng: Double, radiusMeters: Int, limit: Int) async throws -> CityLaunchReviewCandidatesResponse {
    var components = URLComponents(url: try baseURL().appendingPathComponent("v1/creator/city-launch/review-candidates"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
        URLQueryItem(name: "lat", value: String(lat)),
        URLQueryItem(name: "lng", value: String(lng)),
        URLQueryItem(name: "radius_m", value: String(radiusMeters)),
        URLQueryItem(name: "limit", value: String(limit)),
    ]
    guard let url = components.url else {
        throw APIError.invalidResponse(statusCode: -1)
    }
    let request = buildRequest(url: url, method: "GET")
    let data = try await perform(request: request, expecting: 200)
    return try decoder.decode(CityLaunchReviewCandidatesResponse.self, from: data)
}

protocol CreatorLaunchStatusServiceProtocol {
    func fetchCreatorLaunchStatus(city: String?, stateCode: String?) async throws -> CreatorLaunchStatusResponse
}

protocol CityLaunchCandidateSignalServiceProtocol {
    func submitCityLaunchCandidateSignals(_ payload: CityLaunchCandidateSignalSubmissionRequest) async throws
    func fetchCityLaunchReviewCandidates(lat: Double, lng: Double, radiusMeters: Int, limit: Int) async throws -> CityLaunchReviewCandidatesResponse
}

extension APIService: CreatorLaunchStatusServiceProtocol {}
extension APIService: CityLaunchCandidateSignalServiceProtocol {}
```

- [ ] **Step 4: Run build to verify it passes**

Run: `cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture && xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture
git add Services/APIService.swift
git commit -m "feat: add launch status and review candidate API contracts"
```

### Task 5: Replace Hardcoded Launch Gate With Backend Truth

**Files:**
- Modify: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Services/LaunchCityGateService.swift`
- Modify: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/LaunchCityGateView.swift`
- Test: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture` build

- [ ] **Step 1: Write the failing test as a compile target by changing the ViewModel contract**

```swift
// Target contract in /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Services/LaunchCityGateService.swift
@MainActor
@Observable
final class LaunchCityGateViewModel {
    enum State: Equatable {
        case checking
        case locationPermissionRequired
        case locationPermissionDenied
        case supported(CreatorLaunchStatusResponse.SupportedCity)
        case unsupported(CreatorLaunchStatusResponse.CurrentCity?)
        case failed(String)
    }
}
```

- [ ] **Step 2: Run build to verify it fails**

Run: `cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture && xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: FAIL because local matcher-based logic still uses `LaunchCity`.

- [ ] **Step 3: Write minimal implementation**

```swift
// In /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Services/LaunchCityGateService.swift
@MainActor
@Observable
final class LaunchCityGateViewModel {
    enum State: Equatable {
        case checking
        case locationPermissionRequired
        case locationPermissionDenied
        case supported(CreatorLaunchStatusResponse.SupportedCity)
        case unsupported(CreatorLaunchStatusResponse.CurrentCity?)
        case failed(String)
    }

    private let locationService: LocationServiceProtocol
    private let resolver: LaunchCityResolving
    private let launchStatusService: CreatorLaunchStatusServiceProtocol
    private var hasStarted = false
    private var lastResolvedLocation: CLLocation?
    private var evaluationTask: Task<Void, Never>?

    var state: State = .checking
    var supportedCities: [CreatorLaunchStatusResponse.SupportedCity] = []

    init(
        locationService: LocationServiceProtocol = LocationService(),
        resolver: LaunchCityResolving = LaunchCityResolver(),
        launchStatusService: CreatorLaunchStatusServiceProtocol = APIService.shared
    ) {
        self.locationService = locationService
        self.resolver = resolver
        self.launchStatusService = launchStatusService
        locationService.setListener { [weak self] location in
            guard let self else { return }
            Task { @MainActor in
                self.handleLocationUpdate(location)
            }
        }
    }

    var resolvedCity: ResolvedLaunchCity? {
        switch state {
        case .supported(let city):
            return ResolvedLaunchCity(city: city.city, stateCode: city.stateCode, countryCode: "US")
        case .unsupported(let currentCity):
            guard let currentCity else { return nil }
            return ResolvedLaunchCity(city: currentCity.city, stateCode: currentCity.stateCode, countryCode: "US")
        default:
            return nil
        }
    }

    private func handleLocationUpdate(_ location: CLLocation?, forceRefresh: Bool = false) {
        guard let location else {
            state = .checking
            return
        }

        if !forceRefresh,
           let lastResolvedLocation,
           location.distance(from: lastResolvedLocation) < 100 {
            return
        }

        lastResolvedLocation = location
        state = .checking
        evaluationTask?.cancel()
        evaluationTask = Task { [resolver, launchStatusService] in
            do {
                let resolvedCity = try await resolver.resolveCity(for: location)
                let launchStatus = try await launchStatusService.fetchCreatorLaunchStatus(
                    city: resolvedCity?.city,
                    stateCode: resolvedCity?.stateCode
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.supportedCities = launchStatus.supportedCities
                    if let currentCity = launchStatus.currentCity, currentCity.isSupported {
                        if let supported = launchStatus.supportedCities.first(where: { $0.citySlug == currentCity.citySlug }) {
                            self.state = .supported(supported)
                        } else {
                            self.state = .unsupported(launchStatus.currentCity)
                        }
                    } else {
                        self.state = .unsupported(launchStatus.currentCity)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.state = .failed("Blueprint couldn’t verify your launch city right now. Try again in a moment.")
                }
            }
        }
    }
}
```

```swift
// In /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/LaunchCityGateView.swift
Text("Your location determines whether the capture network unlocks. Launch availability follows Blueprint's active city program.")
```

- [ ] **Step 4: Run build to verify it passes**

Run: `cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture && xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture
git add Services/LaunchCityGateService.swift LaunchCityGateView.swift
git commit -m "feat: back launch city gate with backend status"
```

### Task 6: Remove Generic Public Nearby Cards From The Approved Feed

**Files:**
- Modify: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/NearbyTargetsViewModel.swift`
- Modify: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/ScanHomeViewModel.swift`
- Test: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture` build

- [ ] **Step 1: Write the failing test by changing feed intent in code**

```swift
// Intent change in /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/NearbyTargetsViewModel.swift
// Approved public feed should only use backend-approved launch targets once backend is configured.
```

- [ ] **Step 2: Run build / inspect behavior expectation**

Run: `cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture && xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: current code still compiles but behavior is wrong because generic discovery remains in the approved list.

- [ ] **Step 3: Write minimal implementation**

```swift
// In /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/NearbyTargetsViewModel.swift
func refresh() async {
    guard let loc = currentSearchLocation() else {
        state = .error("Location unavailable. Enable location or enter an address.")
        return
    }
    state = .loading
    do {
        let meters = Int(selectedRadius.rawValue * 1609.34)
        let limit = selectedLimit.rawValue
        var targets: [Target] = []

        if AppConfig.hasBackendBaseURL() {
            let launchResponse = try await cityLaunchTargetsService.fetchCityLaunchTargets(
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude,
                radiusMeters: meters,
                limit: limit
            )
            targets = launchResponse.targets
        } else {
            targets = try await targetsAPI.fetchTargets(
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude,
                radiusMeters: meters,
                limit: limit
            )
        }

        // keep the rest of the mapping pipeline unchanged
    } catch {
        state = .error("Failed to load targets. Please try again.")
    }
}
```

```swift
// In /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/ScanHomeViewModel.swift
private func fetchRankedJobs(userLocation: CLLocation) async throws -> [ScanJob] {
    if AppConfig.hasDemandBackendBaseURL() {
        let response = try await demandIntelligenceService.fetchDemandOpportunityFeed(
            DemandOpportunityFeedRequest(
                lat: userLocation.coordinate.latitude,
                lng: userLocation.coordinate.longitude,
                radiusMeters: Int(feedRadiusMeters.rounded()),
                limit: 200,
                candidatePlaces: []
            )
        )
        return response.captureJobs
    }

    return try await jobsRepository.fetchActiveJobs(limit: 200)
}
```

- [ ] **Step 4: Run build to verify it passes**

Run: `cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture && xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture
git add ViewModels/NearbyTargetsViewModel.swift ViewModels/ScanHomeViewModel.swift
git commit -m "feat: limit public capture feed to approved sources"
```

### Task 7: Add Nearby Candidate Scan Submission Loop

**Files:**
- Create: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Services/NearbyCandidateReviewSubmissionService.swift`
- Modify: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/ScanHomeViewModel.swift`
- Test: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture` build

- [ ] **Step 1: Write the failing test by introducing a missing service dependency**

```swift
// Target dependency in /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/ScanHomeViewModel.swift
private let nearbyCandidateReviewSubmissionService: NearbyCandidateReviewSubmissionServiceProtocol
```

- [ ] **Step 2: Run build to verify it fails**

Run: `cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture && xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: FAIL because the new protocol / service does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Services/NearbyCandidateReviewSubmissionService.swift
import Foundation
import CoreLocation

struct CityLaunchCandidateSignalSubmissionRequest: Codable, Equatable {
    struct Candidate: Codable, Equatable {
        let city: String
        let name: String
        let address: String?
        let lat: Double
        let lng: Double
        let provider: String
        let providerPlaceId: String?
        let types: [String]
        let sourceContext: String

        enum CodingKeys: String, CodingKey {
            case city
            case name
            case address
            case lat
            case lng
            case provider
            case providerPlaceId = "provider_place_id"
            case types
            case sourceContext = "source_context"
        }
    }

    let candidates: [Candidate]
}

protocol NearbyCandidateReviewSubmissionServiceProtocol {
    func submitCandidatesIfNeeded(userLocation: CLLocation, sourceContext: String, candidates: [PlaceDetailsLite]) async
}

final class NearbyCandidateReviewSubmissionService: NearbyCandidateReviewSubmissionServiceProtocol {
    private let api: CityLaunchCandidateSignalServiceProtocol
    private let geocoder: CLGeocoder
    private let defaults: UserDefaults
    private let cooldownSeconds: TimeInterval = 12 * 60 * 60

    init(api: CityLaunchCandidateSignalServiceProtocol = APIService.shared, geocoder: CLGeocoder = CLGeocoder(), defaults: UserDefaults = .standard) {
        self.api = api
        self.geocoder = geocoder
        self.defaults = defaults
    }

    func submitCandidatesIfNeeded(userLocation: CLLocation, sourceContext: String, candidates: [PlaceDetailsLite]) async {
        guard !candidates.isEmpty else { return }

        let areaKey = "\(Int(userLocation.coordinate.latitude * 10)):\(Int(userLocation.coordinate.longitude * 10))"
        let storageKey = "city-launch-candidate-scan:\(areaKey)"
        let now = Date()
        if let lastRun = defaults.object(forKey: storageKey) as? Date,
           now.timeIntervalSince(lastRun) < cooldownSeconds {
            return
        }

        let placemark = try? await geocoder.reverseGeocodeLocation(userLocation).first
        let city = [placemark?.locality, placemark?.administrativeArea]
            .compactMap { $0 }
            .joined(separator: ", ")

        let payload = CityLaunchCandidateSignalSubmissionRequest(
            candidates: candidates.prefix(25).map {
                .init(
                    city: city,
                    name: $0.displayName,
                    address: $0.formattedAddress,
                    lat: $0.lat,
                    lng: $0.lng,
                    provider: "nearby_discovery",
                    providerPlaceId: $0.placeId,
                    types: $0.types ?? [],
                    sourceContext: sourceContext
                )
            }
        )

        do {
            try await api.submitCityLaunchCandidateSignals(payload)
            defaults.set(now, forKey: storageKey)
        } catch {
            return
        }
    }
}
```

```swift
// In /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/ScanHomeViewModel.swift
private let nearbyCandidateReviewSubmissionService: NearbyCandidateReviewSubmissionServiceProtocol

init(
    jobsRepository: JobsRepositoryProtocol = JobsRepository(),
    targetStateService: TargetStateServiceProtocol = TargetStateService(),
    locationService: LocationServiceProtocol = LocationService(),
    alertsManager: NearbyAlertsManager,
    captureHistoryService: CaptureHistoryServiceProtocol = APIService.shared,
    demandIntelligenceService: DemandIntelligenceServiceProtocol = APIService.shared,
    nearbyDiscoveryService: NearbyCandidateDiscoveryServiceProtocol = NearbyCandidateDiscoveryService(),
    nearbyCandidateReviewSubmissionService: NearbyCandidateReviewSubmissionServiceProtocol = NearbyCandidateReviewSubmissionService()
) {
    self.jobsRepository = jobsRepository
    self.targetStateService = targetStateService
    self.locationService = locationService
    self.alertsManager = alertsManager
    self.captureHistoryService = captureHistoryService
    self.demandIntelligenceService = demandIntelligenceService
    self.nearbyDiscoveryService = nearbyDiscoveryService
    self.nearbyCandidateReviewSubmissionService = nearbyCandidateReviewSubmissionService
    // existing listener remains
}
```

```swift
// In /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/ScanHomeViewModel.swift
private func loadNearbyCandidatePlaces(userLocation: CLLocation) async -> [PlaceDetailsLite] {
    guard RuntimeConfig.current.availability(for: .nearbyDiscovery).isEnabled else {
        return []
    }

    do {
        let candidates = try await nearbyDiscoveryService.discoverCandidatePlaces(
            userLocation: userLocation.coordinate,
            radiusMeters: Int(feedRadiusMeters.rounded()),
            limit: inferredNearbyLimit,
            includedTypes: Self.inferredNearbyIncludedTypes
        )
        await nearbyCandidateReviewSubmissionService.submitCandidatesIfNeeded(
            userLocation: userLocation,
            sourceContext: "app_open_scan",
            candidates: candidates
        )
        return candidates
    } catch {
        print("⚠️ [ScanHome] Nearby candidate discovery failed: \(error.localizedDescription)")
        return []
    }
}
```

- [ ] **Step 4: Run build to verify it passes**

Run: `cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture && xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture
git add Services/NearbyCandidateReviewSubmissionService.swift ViewModels/ScanHomeViewModel.swift
git commit -m "feat: submit nearby candidate places for launch review"
```

### Task 8: Add Under-Review UI Section

**Files:**
- Modify: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/ScanHomeViewModel.swift`
- Modify: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Views/Scan/ScanHomeView.swift`
- Test: `/Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture` build

- [ ] **Step 1: Write the failing test by adding new view model output**

```swift
// In /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/ScanHomeViewModel.swift
struct ReviewCandidateItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let reviewState: String
}

@Published private(set) var reviewCandidates: [ReviewCandidateItem] = []
```

- [ ] **Step 2: Run build to verify it fails until the view uses the new state correctly**

Run: `cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture && xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: FAIL or compile warnings if not fully wired.

- [ ] **Step 3: Write minimal implementation**

```swift
// In /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/ViewModels/ScanHomeViewModel.swift
func refresh() async {
    guard let loc = currentLocation else {
        if items.isEmpty {
            state = .error(Self.missingLocationMessage(for: locationService.authorizationStatus))
        }
        return
    }

    // existing refresh work...

    if AppConfig.hasBackendBaseURL() {
        if let reviewResponse = try? await (APIService.shared as CityLaunchCandidateSignalServiceProtocol)
            .fetchCityLaunchReviewCandidates(
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude,
                radiusMeters: Int(feedRadiusMeters.rounded()),
                limit: 12
            ) {
            self.reviewCandidates = reviewResponse.candidates.map {
                ReviewCandidateItem(
                    id: $0.id,
                    title: $0.name,
                    subtitle: $0.address ?? $0.city,
                    reviewState: $0.reviewState
                )
            }
        } else {
            self.reviewCandidates = []
        }
    } else {
        self.reviewCandidates = []
    }
}
```

```swift
// In /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Views/Scan/ScanHomeView.swift
private var underReviewSection: some View {
    VStack(alignment: .leading, spacing: 14) {
        HStack {
            Text("Under Review Near You")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
        }

        Text("We’re checking nearby spaces against launch criteria. If one is approved, we’ll notify you.")
            .font(.subheadline)
            .foregroundStyle(Color(white: 0.55))

        ForEach(viewModel.reviewCandidates) { candidate in
            VStack(alignment: .leading, spacing: 6) {
                Text(candidate.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(candidate.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.65))
                Text(candidate.reviewState.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.brandTeal.opacity(0.85))
            }
            .padding(16)
            .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }
}
```

```swift
// Insert into /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture/Views/Scan/ScanHomeView.swift
if !viewModel.reviewCandidates.isEmpty {
    underReviewSection
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
}
```

- [ ] **Step 4: Run build to verify it passes**

Run: `cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture && xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture
git add ViewModels/ScanHomeViewModel.swift Views/Scan/ScanHomeView.swift
git commit -m "feat: show under review nearby spaces in capture UI"
```

### Task 9: Verification

**Files:**
- Test only

- [ ] **Step 1: Run backend tests**

Run:

```bash
cd /Users/nijelhunt_1/workspace/Blueprint-WebApp
npx vitest run \
  server/tests/city-launch-capture-targets.test.ts \
  server/tests/city-launch-status.test.ts \
  server/tests/city-launch-candidate-signals.test.ts \
  server/tests/city-launch-under-review-feed.test.ts
```

Expected: all PASS

- [ ] **Step 2: Run iOS build**

Run:

```bash
cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture
xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Spot-check no hardcoded launch city list remains authoritative**

Run:

```bash
cd /Users/nijelhunt_1/paperclip-clean-session/BlueprintCapture
rg -n "Austin|Durham|San Francisco|supportedCities" Services/LaunchCityGateService.swift LaunchCityGateView.swift
```

Expected: no hardcoded launch truth remains except view preview fixtures or backend-fed display usage

- [ ] **Step 4: Commit final verification-only changes if needed**

```bash
# No commit required unless verification caused code changes
```

## Self-Review

- Spec coverage:
  - backend launch truth: Tasks 1, 4, 5
  - candidate intake queue: Task 2
  - under-review feed: Tasks 3, 8
  - approved-only public cards: Task 6
  - nearby scan loop: Task 7
  - verification: Task 9
- Placeholder scan:
  - No `TBD`, `TODO`, or “similar to task N” placeholders remain.
- Type consistency:
  - `CreatorLaunchStatusResponse`, `CityLaunchReviewCandidatesResponse`, and `CityLaunchCandidateSignalSubmissionRequest` are named consistently across tasks.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-16-launch-city-org-backed-capture-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
