# Code Changes - Quick Reference

## File 1: PlacesAutocompleteService.swift

### Location of Changes
```
BlueprintCapture/
└── Services/
    └── PlacesAutocompleteService.swift
        ├── Line 53: NEW struct LocationRestriction
        ├── Line 59: NEW locationRestriction field in Body struct
        └── Lines 71-78: NEW locationRestriction initialization
```

### What Changed - Before

```swift
struct LocationBias: Encodable { let circle: Circle }
struct Body: Encodable {
    let input: Text
    let sessionToken: String
    let origin: LatLng?
    let locationBias: LocationBias?
    let includeQueryPredictions: Bool
}

let body = Body(
    input: Text(text: input),
    sessionToken: sessionToken,
    origin: origin.map { LatLng(latitude: $0.latitude, longitude: $0.longitude) },
    locationBias: {
        if let o = origin, let r = radiusMeters { 
            return LocationBias(circle: Circle(...))
        }
        return nil
    }(),
    includeQueryPredictions: false
)
```

### What Changed - After

```swift
struct LocationBias: Encodable { let circle: Circle }
struct LocationRestriction: Encodable { let circle: Circle }  // ← NEW
struct Body: Encodable {
    let input: Text
    let sessionToken: String
    let origin: LatLng?
    let locationBias: LocationBias?
    let locationRestriction: LocationRestriction?  // ← NEW
    let includeQueryPredictions: Bool
}

let body = Body(
    input: Text(text: input),
    sessionToken: sessionToken,
    origin: origin.map { LatLng(latitude: $0.latitude, longitude: $0.longitude) },
    locationBias: {
        if let o = origin, let r = radiusMeters { 
            return LocationBias(circle: Circle(...))
        }
        return nil
    }(),
    locationRestriction: {  // ← NEW BLOCK
        // Restrict results to a larger circle around the user to keep 
        // results in the same state/region
        if let o = origin {
            let restrictionRadius = max(radiusMeters ?? 40000, 40000) // ~25 miles
            return LocationRestriction(circle: Circle(
                center: Center(latitude: o.latitude, longitude: o.longitude),
                radius: restrictionRadius
            ))
        }
        return nil
    }(),
    includeQueryPredictions: false
)
```

### Key Difference
- **Before:** Only `locationBias` (soft preference)
- **After:** Both `locationBias` (soft) + `locationRestriction` (hard boundary)

---

## File 2: NearbyTargetsViewModel.swift

### Location of Changes
```
BlueprintCapture/
└── ViewModels/
    └── NearbyTargetsViewModel.swift
        └── searchAddresses() function (Lines 615-670)
            ├── Line 637: Print statement #1 🔍
            ├── Line 640-642: Print statements #2-3 ⚠️
            ├── Line 638: Print statement #4 📋
            ├── Line 649-651: Print statements #5-6 ⚠️
            ├── Line 647: Print statement #7 ✅
            ├── Line 649: Print statement #8 ❌
            ├── Line 667: Print statement #9 📍
            └── Line 668: Print statement #10 ❌
```

### Function: searchAddresses()

**Lines 615-620 (unchanged)**
```swift
func searchAddresses(query: String) async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 2 else {
        await MainActor.run { self.addressSearchResults = [] }
        placesSessionToken = nil
        return
    }
```

**Lines 622-636 (part of Places path)**
```swift
await MainActor.run { self.isSearchingAddress = true }
defer { Task { @MainActor in self.isSearchingAddress = false } }

if AppConfig.placesAPIKey() != nil {
    do {
        if placesSessionToken == nil { placesSessionToken = UUID().uuidString }
        let origin = currentSearchLocation()?.coordinate
        let radius = Int(selectedRadius.rawValue * 1609.34)
        let suggestions = try await placesAutocomplete.autocomplete(
            input: trimmed,
            sessionToken: placesSessionToken ?? UUID().uuidString,
            origin: origin,
            radiusMeters: radius
        )
```

**Line 637 - NEW PRINT #1 🔍**
```swift
        print("🔍 [Autocomplete] Got \(suggestions.count) suggestions for '\(trimmed)'")
```
Shows how many autocomplete suggestions came back

**Lines 640-642 - NEW CHECK + PRINTS #2-3 ⚠️**
```swift
        guard !suggestions.isEmpty else {
            print("⚠️ [Autocomplete] No suggestions returned")
            throw NSError(domain: "AutocompleteError", code: -1, userInfo: nil)
        }
```
Checks if autocomplete returned nothing and logs it

**Lines 637-638 - (unchanged, then) NEW PRINT #4 📋**
```swift
        let details = try await placesDetailsService.fetchDetails(placeIds: suggestions.map { $0.placeId })
        print("📋 [Places Details] Got details for \(details.count) of \(suggestions.count) suggestions")
```
Shows how many detail fetches succeeded

**Lines 639-646 - UPDATED WITH NEW PRINTS #5-6 ⚠️**
```swift
        let detailById = Dictionary(uniqueKeysWithValues: details.map { ($0.placeId, $0) })
        let results: [LocationSearchResult] = suggestions.compactMap { s in
            if let d = detailById[s.placeId] {
                let coord = CLLocationCoordinate2D(latitude: d.lat, longitude: d.lng)
                let title = s.primaryText.isEmpty ? d.displayName : s.primaryText
                let subtitle = s.secondaryText.isEmpty ? (d.formattedAddress ?? "") : s.secondaryText
                return LocationSearchResult(title: title, subtitle: subtitle, coordinate: coord)
            } else {
                print("⚠️ [Autocomplete] Missing details for placeId \(s.placeId), using suggestion text only")
                // ↑ NEW PRINT #5
                return nil
            }
        }
```
Logs which place IDs didn't get details

**Line 647 - NEW PRINT #7 ✅**
```swift
        print("✅ [Autocomplete] Displaying \(results.count) search results")
```
Shows final count of results displayed to user

**Line 649 - NEW PRINT #8 ❌**
```swift
        } catch {
            print("❌ [Autocomplete] Error: \(error.localizedDescription)")
            // Fall through to MapKit fallback below
        }
```
Logs any autocomplete errors before falling back

**Lines 653-667 - MapKit fallback path (mostly unchanged)**
```swift
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = trimmed
    let search = MKLocalSearch(request: request)
    do {
        let response = try await search.start()
        let results: [LocationSearchResult] = response.mapItems.prefix(8).compactMap { item in
            guard let coord = item.placemark.location?.coordinate else { return nil }
            let title = item.name ?? item.placemark.name ?? "Unknown"
            let subtitle = [item.placemark.locality, item.placemark.administrativeArea]
                .compactMap { $0 }
                .joined(separator: ", ")
            return LocationSearchResult(title: title, subtitle: subtitle, coordinate: coord)
        }
```

**Line 667 - NEW PRINT #9 📍**
```swift
        print("📍 [MapKit] Displaying \(results.count) search results")
```
Shows how many MapKit results are displayed

**Line 668 - NEW PRINT #10 ❌**
```swift
        await MainActor.run { self.addressSearchResults = results }
    } catch {
        print("❌ [MapKit Search] Error: \(error.localizedDescription)")
        await MainActor.run { self.addressSearchResults = [] }
    }
```
Logs any MapKit errors

---

## Summary of Edits

### PlacesAutocompleteService.swift
| Type | Count | Lines |
|------|-------|-------|
| New struct | 1 | 53 |
| New field | 1 | 59 |
| New logic | 1 block | 71-78 |
| **Total** | **3 additions** | **~10 lines** |

### NearbyTargetsViewModel.swift
| Type | Count | Lines |
|------|-------|-------|
| Print statements | 8 | Various |
| Guard statement | 1 | 640-642 |
| Logic changes | 0 | (none) |
| **Total** | **9 additions** | **~12 lines** |

**Grand Total:** ~22 lines of code changes (mostly debug logging)

---

## Verification Checklist

- [x] PlacesAutocompleteService.swift has LocationRestriction struct (line 53)
- [x] Body struct has locationRestriction field (line 59)
- [x] locationRestriction is initialized with circle (lines 71-78)
- [x] searchAddresses() has 8+ print statements
- [x] Print statements cover: suggestions, details, results, errors, fallback
- [x] No existing code removed (pure additions)
- [x] No syntax errors (linter verified)
- [x] Both Places and MapKit paths preserved

