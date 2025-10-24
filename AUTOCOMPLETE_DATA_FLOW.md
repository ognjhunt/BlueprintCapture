# Autocomplete Search Data Flow

## User Action Flow

```
┌─────────────────────────────────────────────────────────────┐
│ User taps "Search location" chip                             │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────v──────────────┐
        │ addressSearchSheet appears   │
        │ with TextField               │
        │ "Search another address"     │
        └──────────────┬───────────────┘
                       │
    ┌──────────────────v──────────────────┐
    │ User types "Main St" (3+ chars)     │
    │ onChange triggers searchAddresses() │
    └──────────────┬───────────────────────┘
                   │
      ┌────────────v─────────────┐
      │ Does user have API key?  │
      └────────────┬──────┬──────┘
                   │      │
         YES ◄─────┘      └─────► NO
          │                        │
         v                        v
   ┌────────────────┐    ┌──────────────────┐
   │ Places API     │    │ MapKit Fallback  │
   │ (Primary)      │    │ (Fallback)       │
   └────────────────┘    └──────────────────┘
```

## Data Processing Pipeline (BEFORE Fixes)

```
User Input: "202"
    │
    ├─ originCoordinate: (NC lat/lng)
    ├─ radius: 1600m (1 mile)
    └─ sessionToken: UUID
            │
            v
    ┌────────────────────────────┐
    │ Places Autocomplete API    │
    │ locationBias ← soft only   │ ← PROBLEM: No hard restriction
    │ RESPONSE: [5 suggestions]  │
    │  ├─ 202 Elm, NC            │
    │  ├─ 202 Oak, NC            │
    │  ├─ 202 Maple, SC          │ ← Wrong state!
    │  ├─ 202 Pine, SC           │
    │  └─ 202 Main, NC           │
    └────────────┬───────────────┘
                 │ placeIds
                 v
    ┌────────────────────────────┐
    │ Places Details API         │
    │ Fetch details for all 5    │
    │ RESPONSE: [3 details]      │ ← Some failed silently!
    │  ├─ 202 Elm, Greensboro    │
    │  ├─ 202 Oak, Charlotte     │
    │  └─ 202 Main, Raleigh      │
    └────────────┬───────────────┘
                 │ (Missing 202 Maple SC, 202 Pine SC)
                 │ (But also missing NC ones!)
                 │
                 v
    ┌────────────────────────────┐
    │ UI displays: 1 result      │ ← Only showing 1!
    │ "202 Main, Raleigh, NC"    │
    │ (No logging = can't debug) │
    └────────────────────────────┘
```

## Data Processing Pipeline (AFTER Fixes)

```
User Input: "202"
    │
    ├─ originCoordinate: (NC lat/lng)
    ├─ radius: 1600m (1 mile)
    └─ sessionToken: UUID
            │
            v
    ┌────────────────────────────────────┐
    │ Places Autocomplete API            │
    │ ✅ locationBias (soft, ~1mi)       │
    │ ✅ locationRestriction (hard, 40km)│ ← NEW: Hard boundary
    │                                    │
    │ RESPONSE: [4 suggestions]          │
    │  ├─ 202 Elm, NC            ✅      │
    │  ├─ 202 Oak, NC            ✅      │
    │  ├─ 202 Maple, NC          ✅      │
    │  └─ 202 Main, NC           ✅      │
    │                                    │
    │ 🔍 [Autocomplete] Got 4 suggestions│ ← Debug log
    └────────────┬───────────────────────┘
                 │ placeIds
                 v
    ┌────────────────────────────────┐
    │ Places Details API             │
    │ Fetch details for all 4        │
    │ RESPONSE: [4 details]          │
    │  ├─ 202 Elm, Greensboro   ✅   │
    │  ├─ 202 Oak, Charlotte    ✅   │
    │  ├─ 202 Maple, Durham     ✅   │
    │  └─ 202 Main, Raleigh     ✅   │
    │                                │
    │ 📋 [Places Details] Got        │ ← Debug log
    │    details for 4 of 4          │
    └────────────┬────────────────────┘
                 │
                 v
    ┌────────────────────────────────┐
    │ Build LocationSearchResult[]    │
    │ ✅ 202 Elm St, Greensboro, NC   │
    │ ✅ 202 Oak Ave, Charlotte, NC   │
    │ ✅ 202 Maple Dr, Durham, NC     │
    │ ✅ 202 Main St, Raleigh, NC     │
    │                                │
    │ ✅ [Autocomplete]               │ ← Debug log
    │    Displaying 4 search results  │
    └────────────┬────────────────────┘
                 │
                 v
    ┌────────────────────────────┐
    │ addressSearchResults       │
    │ populated with 4 items     │
    │ (User sees all 4)          │
    └────────────────────────────┘
```

## Error Flow (What Gets Logged)

### Path 1: Places API Returns Results ✅
```
🔍 [Autocomplete] Got 5 suggestions for '202'
   ↓ (Fetch details for each)
📋 [Places Details] Got details for 5 of 5 suggestions
   ↓ (All matched, create LocationSearchResults)
✅ [Autocomplete] Displaying 5 search results
   ↓
User sees: 5 location options
```

### Path 2: Some Details Fail ⚠️
```
🔍 [Autocomplete] Got 5 suggestions for '202'
   ↓ (Fetch details, but 2 fail)
📋 [Places Details] Got details for 3 of 5 suggestions
⚠️ [Autocomplete] Missing details for placeId ChIJ...
⚠️ [Autocomplete] Missing details for placeId ChIJ...
   ↓ (Only use the 3 that succeeded)
✅ [Autocomplete] Displaying 3 search results
   ↓
User sees: 3 location options
Dev sees: Console warning about 2 failures
```

### Path 3: Places API Returns Empty ⚠️
```
🔍 [Autocomplete] Got 0 suggestions for 'xyzabc'
❌ [Autocomplete] Error: No suggestions returned
   ↓ (Fall through to MapKit)
📍 [MapKit] Displaying 2 search results
   ↓
User sees: 2 location options from MapKit
Dev sees: Autocomplete failed, using fallback
```

### Path 4: Places API Not Configured 🔄
```
❌ [Autocomplete] Error: missing API key
   ↓ (Immediately skip to MapKit)
📍 [MapKit] Displaying 8 search results
   ↓
User sees: 8 location options from MapKit
Dev sees: Places API not configured, fallback working
```

## Key Improvements

| Aspect | Before | After | Impact |
|--------|--------|-------|--------|
| **State Boundary** | Soft bias only | Soft + hard restriction | ✅ SC results eliminated |
| **Result Count** | 1 (silent fail) | 4-5 (with logging) | ✅ Multiple options shown |
| **Debugging** | No visibility | 8 debug points | ✅ Easy to trace issues |
| **Error Handling** | Silent fallback | Explicit error logging | ✅ Know what failed |
| **Graceful Degradation** | Works if lucky | Works + shows why | ✅ Better reliability |

---

**Data Sources:**
- Location: `CLLocationManager` (user's current position)
- Suggestions: Google Places Autocomplete API
- Details: Google Places Details API (parallel fetch)
- Fallback: MapKit Local Search

**Caching:**
- Places session token (UUID per search session)
- Street view URLs (per location coordinate)
- No caching of autocomplete results (fresh per search)

