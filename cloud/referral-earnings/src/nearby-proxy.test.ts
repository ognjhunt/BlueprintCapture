import test from "node:test";
import assert from "node:assert/strict";

import {
  proxyNearbyDiscovery,
  proxyPlaceDetails,
  proxyPlacesAutocomplete,
  type NearbyProxyAutocompleteRequest,
  type NearbyProxyDetailsRequest,
  type NearbyProxyDiscoveryRequest,
} from "./nearby-proxy.js";

test("proxyNearbyDiscovery returns Places results when the primary provider succeeds", async () => {
  const payload: NearbyProxyDiscoveryRequest = {
    lat: 37.77,
    lng: -122.39,
    radius_m: 5000,
    limit: 5,
    included_types: ["warehouse_store"],
    provider_hint: "places_nearby",
    allow_fallback: true,
  };

  const fetchImpl: typeof fetch = async (input) => {
    const url = String(input);
    assert.match(url, /places:searchNearby/);
    return new Response(JSON.stringify({
      places: [
        {
          id: "place-1",
          displayName: { text: "Dock Warehouse" },
          formattedAddress: "1 Warehouse Way",
          location: { latitude: 37.771, longitude: -122.391 },
          types: ["warehouse_store"],
        },
      ],
    }), { status: 200 });
  };

  const response = await proxyNearbyDiscovery(payload, {
    fetchImpl,
    placesApiKey: "places-key",
  });

  assert.equal(response.provider_used, "places_nearby");
  assert.equal(response.fallback_used, false);
  assert.equal(response.places[0]?.place_id, "place-1");
});

test("proxyNearbyDiscovery falls back to Gemini when Places fails", async () => {
  const payload: NearbyProxyDiscoveryRequest = {
    lat: 37.77,
    lng: -122.39,
    radius_m: 5000,
    limit: 5,
    included_types: ["warehouse_store"],
    provider_hint: "places_nearby",
    allow_fallback: true,
  };

  const fetchImpl: typeof fetch = async (input) => {
    const url = String(input);
    if (url.includes("places:searchNearby")) {
      return new Response("permission denied", { status: 403 });
    }
    if (url.includes("generateContent")) {
      return new Response(JSON.stringify({
        candidates: [
          {
            content: {
              parts: [
                {
                  text: JSON.stringify([
                    {
                      placeId: "place-2",
                      name: "Fallback Retail",
                      formattedAddress: "2 Market St",
                      lat: 37.772,
                      lng: -122.392,
                      types: ["department_store"],
                    },
                  ]),
                },
              ],
            },
          },
        ],
      }), { status: 200 });
    }
    throw new Error(`Unexpected url ${url}`);
  };

  const response = await proxyNearbyDiscovery(payload, {
    fetchImpl,
    placesApiKey: "places-key",
    geminiApiKey: "gemini-key",
  });

  assert.equal(response.provider_used, "gemini_maps_grounding");
  assert.equal(response.fallback_used, true);
  assert.equal(response.places[0]?.place_id, "place-2");
});

test("proxyPlacesAutocomplete normalizes Places predictions", async () => {
  const payload: NearbyProxyAutocompleteRequest = {
    query: "dock",
    session_token: "session-1",
    origin: { lat: 37.77, lng: -122.39 },
  };

  const fetchImpl: typeof fetch = async () => new Response(JSON.stringify({
    suggestions: [
      {
        placePrediction: {
          placeId: "place-1",
          structuredFormat: {
            mainText: { text: "Dock Warehouse" },
            secondaryText: { text: "1 Warehouse Way" },
          },
          types: ["warehouse_store"],
        },
      },
    ],
  }), { status: 200 });

  const response = await proxyPlacesAutocomplete(payload, {
    fetchImpl,
    placesApiKey: "places-key",
  });

  assert.equal(response.provider_used, "places_nearby");
  assert.equal(response.suggestions[0]?.primary_text, "Dock Warehouse");
  assert.equal(response.suggestions[0]?.secondary_text, "1 Warehouse Way");
});

test("proxyPlaceDetails normalizes batch detail responses", async () => {
  const payload: NearbyProxyDetailsRequest = {
    place_ids: ["place-1", "place-2"],
  };

  const fetchImpl: typeof fetch = async (input) => {
    const url = String(input);
    const placeId = url.endsWith("place-1") ? "place-1" : "place-2";
    return new Response(JSON.stringify({
      id: placeId,
      displayName: { text: `Name for ${placeId}` },
      formattedAddress: `${placeId} Main St`,
      location: { latitude: 37.77, longitude: -122.39 },
      types: ["store"],
    }), { status: 200 });
  };

  const response = await proxyPlaceDetails(payload, {
    fetchImpl,
    placesApiKey: "places-key",
  });

  assert.equal(response.provider_used, "places_nearby");
  assert.equal(response.places.length, 2);
  assert.equal(response.places[1]?.display_name, "Name for place-2");
});
