export type NearbyDiscoveryProviderHint = "places_nearby" | "gemini_maps_grounding";

export interface NearbyProxyPlace {
  place_id: string;
  display_name: string;
  formatted_address?: string;
  lat: number;
  lng: number;
  place_types: string[];
}

export interface NearbyProxyAutocompleteSuggestion {
  place_id: string;
  primary_text: string;
  secondary_text: string;
  place_types: string[];
}

export interface NearbyProxyDiscoveryRequest {
  lat: number;
  lng: number;
  radius_m?: number;
  limit?: number;
  included_types?: string[];
  provider_hint?: NearbyDiscoveryProviderHint;
  allow_fallback?: boolean;
}

export interface NearbyProxyAutocompleteRequest {
  query: string;
  session_token?: string;
  origin?: {
    lat: number;
    lng: number;
  };
  radius_m?: number;
  limit?: number;
  provider_hint?: NearbyDiscoveryProviderHint;
  allow_fallback?: boolean;
}

export interface NearbyProxyDetailsRequest {
  place_ids: string[];
  provider_hint?: NearbyDiscoveryProviderHint;
  allow_fallback?: boolean;
}

export interface NearbyProxyDiscoveryResponse {
  provider_used: NearbyDiscoveryProviderHint;
  fallback_used: boolean;
  places: NearbyProxyPlace[];
}

export interface NearbyProxyAutocompleteResponse {
  provider_used: NearbyDiscoveryProviderHint;
  fallback_used: boolean;
  suggestions: NearbyProxyAutocompleteSuggestion[];
}

export interface NearbyProxyDetailsResponse {
  provider_used: NearbyDiscoveryProviderHint;
  fallback_used: boolean;
  places: NearbyProxyPlace[];
}

export class NearbyProxyError extends Error {
  constructor(
    public readonly code: string,
    public readonly statusCode: number,
    message: string,
  ) {
    super(message);
    this.name = "NearbyProxyError";
  }
}

interface NearbyProxyOptions {
  fetchImpl?: typeof fetch;
  placesApiKey?: string | null;
  geminiApiKey?: string | null;
  geminiModel?: string | null;
}

type ProviderExecutionResult = {
  provider_used: NearbyDiscoveryProviderHint;
  places: NearbyProxyPlace[];
};

export async function proxyNearbyDiscovery(
  payload: NearbyProxyDiscoveryRequest,
  options: NearbyProxyOptions = {},
): Promise<NearbyProxyDiscoveryResponse> {
  validateCoordinate(payload.lat, "lat");
  validateCoordinate(payload.lng, "lng");

  const primary = normalizeProviderHint(payload.provider_hint);
  const allowFallback = payload.allow_fallback === true;
  const execute = async (provider: NearbyDiscoveryProviderHint): Promise<ProviderExecutionResult> => {
    switch (provider) {
      case "gemini_maps_grounding":
        return {
          provider_used: provider,
          places: await discoverNearbyWithGemini(payload, options),
        };
      case "places_nearby":
      default:
        return {
          provider_used: "places_nearby",
          places: await discoverNearbyWithPlaces(payload, options),
        };
    }
  };

  try {
    const primaryResult = await execute(primary);
    if (primaryResult.places.length > 0 || !allowFallback) {
      return {
        provider_used: primaryResult.provider_used,
        fallback_used: false,
        places: primaryResult.places,
      };
    }

    const fallbackProvider = alternateProvider(primary);
    const fallbackResult = await execute(fallbackProvider);
    return {
      provider_used: fallbackResult.provider_used,
      fallback_used: true,
      places: fallbackResult.places,
    };
  } catch (error) {
    if (!allowFallback) {
      throw error;
    }

    const fallbackProvider = alternateProvider(primary);
    const fallbackResult = await execute(fallbackProvider);
    return {
      provider_used: fallbackResult.provider_used,
      fallback_used: true,
      places: fallbackResult.places,
    };
  }
}

export async function proxyPlacesAutocomplete(
  payload: NearbyProxyAutocompleteRequest,
  options: NearbyProxyOptions = {},
): Promise<NearbyProxyAutocompleteResponse> {
  const query = payload.query.trim();
  if (!query) {
    throw new NearbyProxyError("invalid_argument", 400, "query is required");
  }

  const apiKey = resolvePlacesApiKey(options);
  const fetchImpl = options.fetchImpl ?? fetch;
  const url = "https://places.googleapis.com/v1/places:autocomplete";
  const requestBody = {
    input: query,
    sessionToken: payload.session_token?.trim() || "server-session",
    origin: payload.origin ? { latitude: payload.origin.lat, longitude: payload.origin.lng } : undefined,
    locationBias: payload.origin
      ? {
          circle: {
            center: { latitude: payload.origin.lat, longitude: payload.origin.lng },
            radius: Math.min(Math.max(payload.radius_m ?? 5000, 100), 16000),
          },
        }
      : undefined,
    locationRestriction: payload.origin
      ? {
          circle: {
            center: { latitude: payload.origin.lat, longitude: payload.origin.lng },
            radius: Math.min(Math.max(payload.radius_m ?? 80000, 100), 80000),
          },
        }
      : undefined,
    includedRegionCodes: ["us"],
    languageCode: "en",
    includeQueryPredictions: true,
  };

  const response = await fetchImpl(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.types,suggestions.placePrediction.structuredFormat",
    },
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    throw new NearbyProxyError(
      "places_autocomplete_failed",
      response.status,
      `Places autocomplete returned HTTP ${response.status}.`,
    );
  }

  const decoded = await response.json() as {
    suggestions?: Array<{
      placePrediction?: {
        placeId?: string;
        text?: { text?: string };
        types?: string[];
        structuredFormat?: {
          mainText?: { text?: string };
          secondaryText?: { text?: string };
        };
      };
    }>;
  };

  const limit = Math.max(1, Math.min(payload.limit ?? 8, 20));
  const suggestions = (decoded.suggestions ?? [])
    .map((suggestion) => suggestion.placePrediction)
    .filter((prediction): prediction is NonNullable<typeof prediction> => !!prediction?.placeId)
    .map((prediction) => {
      let primaryText = prediction.structuredFormat?.mainText?.text?.trim() ?? "";
      let secondaryText = prediction.structuredFormat?.secondaryText?.text?.trim() ?? "";
      if (!primaryText) {
        const combined = prediction.text?.text?.trim() ?? "";
        const pieces = combined.split(",").map((piece) => piece.trim()).filter(Boolean);
        primaryText = pieces[0] ?? combined;
        secondaryText = pieces.slice(1).join(", ");
      }

      return {
        place_id: prediction.placeId!,
        primary_text: primaryText,
        secondary_text: secondaryText,
        place_types: prediction.types ?? [],
      } satisfies NearbyProxyAutocompleteSuggestion;
    })
    .slice(0, limit);

  return {
    provider_used: "places_nearby",
    fallback_used: false,
    suggestions,
  };
}

export async function proxyPlaceDetails(
  payload: NearbyProxyDetailsRequest,
  options: NearbyProxyOptions = {},
): Promise<NearbyProxyDetailsResponse> {
  const placeIds = dedupeStrings(payload.place_ids);
  if (placeIds.length === 0) {
    throw new NearbyProxyError("invalid_argument", 400, "place_ids is required");
  }

  const apiKey = resolvePlacesApiKey(options);
  const fetchImpl = options.fetchImpl ?? fetch;
  const placeResults = await Promise.all(placeIds.map(async (placeId) => {
    const response = await fetchImpl(`https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`, {
      headers: {
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": "id,displayName,formattedAddress,location,types",
      },
    });

    if (!response.ok) {
      throw new NearbyProxyError(
        "places_details_failed",
        response.status,
        `Places details returned HTTP ${response.status}.`,
      );
    }

    const decoded = await response.json() as {
      id?: string;
      displayName?: { text?: string };
      formattedAddress?: string;
      location?: { latitude?: number; longitude?: number };
      types?: string[];
    };

    const id = decoded.id?.trim();
    const displayName = decoded.displayName?.text?.trim();
    const lat = decoded.location?.latitude;
    const lng = decoded.location?.longitude;
    if (!id || !displayName || typeof lat !== "number" || typeof lng !== "number") {
      return null;
    }

    return {
      place_id: id,
      display_name: displayName,
      formatted_address: decoded.formattedAddress,
      lat,
      lng,
      place_types: decoded.types ?? [],
    } satisfies NearbyProxyPlace;
  }));
  const places = placeResults.flatMap((place) => place ? [place] : []);

  return {
    provider_used: "places_nearby",
    fallback_used: false,
    places,
  };
}

function normalizeProviderHint(value?: string | null): NearbyDiscoveryProviderHint {
  return value === "gemini_maps_grounding" ? "gemini_maps_grounding" : "places_nearby";
}

function alternateProvider(provider: NearbyDiscoveryProviderHint): NearbyDiscoveryProviderHint {
  return provider === "places_nearby" ? "gemini_maps_grounding" : "places_nearby";
}

async function discoverNearbyWithPlaces(
  payload: NearbyProxyDiscoveryRequest,
  options: NearbyProxyOptions,
): Promise<NearbyProxyPlace[]> {
  const apiKey = resolvePlacesApiKey(options);
  const fetchImpl = options.fetchImpl ?? fetch;
  const response = await fetchImpl("https://places.googleapis.com/v1/places:searchNearby", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "places.id,places.displayName,places.formattedAddress,places.location,places.types",
    },
    body: JSON.stringify({
      includedTypes: sanitizeStringArray(payload.included_types),
      maxResultCount: Math.max(1, Math.min(payload.limit ?? 8, 20)),
      locationRestriction: {
        circle: {
          center: {
            latitude: payload.lat,
            longitude: payload.lng,
          },
          radius: Math.max(100, Math.min(payload.radius_m ?? 16093, 160934)),
        },
      },
      rankPreference: "DISTANCE",
    }),
  });

  if (!response.ok) {
    throw new NearbyProxyError(
      "places_nearby_failed",
      response.status,
      `Places nearby search returned HTTP ${response.status}.`,
    );
  }

  const decoded = await response.json() as {
    places?: Array<{
      id?: string;
      displayName?: { text?: string };
      formattedAddress?: string;
      location?: { latitude?: number; longitude?: number };
      types?: string[];
    }>;
  };

  return (decoded.places ?? []).flatMap((place) => {
    const placeId = place.id?.trim();
    const displayName = place.displayName?.text?.trim();
    const lat = place.location?.latitude;
    const lng = place.location?.longitude;
    if (!placeId || !displayName || typeof lat !== "number" || typeof lng !== "number") {
      return [];
    }

    return [{
      place_id: placeId,
      display_name: displayName,
      formatted_address: place.formattedAddress,
      lat,
      lng,
      place_types: place.types ?? [],
    } satisfies NearbyProxyPlace];
  });
}

async function discoverNearbyWithGemini(
  payload: NearbyProxyDiscoveryRequest,
  options: NearbyProxyOptions,
): Promise<NearbyProxyPlace[]> {
  const apiKey = resolveGeminiApiKey(options);
  const fetchImpl = options.fetchImpl ?? fetch;
  const model = options.geminiModel?.trim() || "gemini-2.5-flash";
  const normalizedTypes = sanitizeStringArray(payload.included_types)
    .map((value) => value.replace(/[_-]+/g, " "));
  const prompt = [
    `Find up to ${Math.max(1, Math.min(payload.limit ?? 8, 20))} real nearby places for Blueprint capture discovery.`,
    `Use Google Maps grounding and do not invent places.`,
    `Return only strict JSON array objects with keys: placeId, name, formattedAddress, lat, lng, types, score, siteType, reasoning.`,
    `Search radius: ${Math.max(100, Math.min(payload.radius_m ?? 16093, 160934))} meters.`,
    normalizedTypes.length > 0 ? `Target categories: ${normalizedTypes.join(", ")}.` : "",
  ].filter(Boolean).join(" ");

  const response = await fetchImpl(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [{
          parts: [{ text: prompt }],
        }],
        tools: [{ googleMaps: {} }],
        toolConfig: {
          retrievalConfig: {
            latLng: {
              latitude: payload.lat,
              longitude: payload.lng,
            },
          },
        },
      }),
    },
  );

  if (!response.ok) {
    throw new NearbyProxyError(
      "gemini_nearby_failed",
      response.status,
      `Gemini maps grounding returned HTTP ${response.status}.`,
    );
  }

  const decoded = await response.json() as {
    candidates?: Array<{
      content?: {
        parts?: Array<{ text?: string }>;
      };
    }>;
  };

  const candidateText = decoded.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? "";
  const jsonArrayText = extractFirstJsonArray(candidateText);
  if (!jsonArrayText) {
    throw new NearbyProxyError("gemini_nearby_parse_failed", 502, "Gemini nearby response could not be parsed.");
  }

  const parsed = JSON.parse(jsonArrayText) as Array<Record<string, unknown>>;
  return parsed.flatMap((item) => {
    const placeId = stringValue(item["placeId"] ?? item["place_id"]);
    const displayName = stringValue(item["name"] ?? item["display_name"]);
    const formattedAddress = stringValue(item["formattedAddress"] ?? item["formatted_address"]);
    const lat = numberValue(item["lat"]);
    const lng = numberValue(item["lng"]);
    const placeTypes = stringArrayValue(item["types"] ?? item["place_types"]);
    if (!placeId || !displayName || lat == null || lng == null) {
      return [];
    }

    return [{
      place_id: placeId,
      display_name: displayName,
      formatted_address: formattedAddress,
      lat,
      lng,
      place_types: placeTypes,
    } satisfies NearbyProxyPlace];
  });
}

function validateCoordinate(value: number, field: string): void {
  if (!Number.isFinite(value)) {
    throw new NearbyProxyError("invalid_argument", 400, `${field} must be a number`);
  }
}

function resolvePlacesApiKey(options: NearbyProxyOptions): string {
  const apiKey = normalizeSecret(options.placesApiKey)
    ?? normalizeSecret(process.env.BLUEPRINT_GOOGLE_PLACES_API_KEY)
    ?? normalizeSecret(process.env.GOOGLE_PLACES_API_KEY)
    ?? normalizeSecret(process.env.PLACES_API_KEY);
  if (!apiKey) {
    throw new NearbyProxyError("places_api_key_missing", 503, "Google Places proxy key is not configured.");
  }
  return apiKey;
}

function resolveGeminiApiKey(options: NearbyProxyOptions): string {
  const apiKey = normalizeSecret(options.geminiApiKey)
    ?? normalizeSecret(process.env.BLUEPRINT_GEMINI_API_KEY)
    ?? normalizeSecret(process.env.GEMINI_API_KEY)
    ?? normalizeSecret(process.env.GOOGLE_AI_API_KEY)
    ?? normalizeSecret(process.env.GEMINI_MAPS_API_KEY);
  if (!apiKey) {
    throw new NearbyProxyError("gemini_api_key_missing", 503, "Gemini proxy key is not configured.");
  }
  return apiKey;
}

function normalizeSecret(value?: string | null): string | null {
  const normalized = value?.trim();
  return normalized ? normalized : null;
}

function sanitizeStringArray(values?: string[]): string[] {
  return dedupeStrings(values ?? []).slice(0, 20);
}

function dedupeStrings(values: string[]): string[] {
  const deduped = new Set<string>();
  for (const value of values) {
    const normalized = value.trim();
    if (normalized) {
      deduped.add(normalized);
    }
  }
  return Array.from(deduped);
}

function extractFirstJsonArray(text: string): string | null {
  const start = text.indexOf("[");
  if (start < 0) return null;

  let depth = 0;
  for (let index = start; index < text.length; index += 1) {
    const character = text[index];
    if (character === "[") depth += 1;
    if (character === "]") {
      depth -= 1;
      if (depth === 0) {
        return text.slice(start, index + 1);
      }
    }
  }

  return null;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function stringArrayValue(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}
