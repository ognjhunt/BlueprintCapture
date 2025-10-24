# Autocomplete: Before vs After

## Visual Flow Comparison

### BEFORE ❌
```
User types: "2" → API Call 1 starts
User types: "0" → API Call 2 starts
User types: "2" → API Call 3 starts
User types: " " → API Call 4 starts
User types: "a" → API Call 5 starts
User types: "s" → API Call 6 starts

Results shown: Whichever API call finishes last wins
Problem: Could show "Main St" results for "202 ash" query
```

### AFTER ✅
```
User types: "2" → debounce timer starts (350ms)
User types: "0" → timer cancelled, new timer starts
User types: "2" → timer cancelled, new timer starts
User types: " " → timer cancelled, new timer starts
User types: "a" → timer cancelled, new timer starts
User types: "s" → timer cancelled, new timer starts
[350ms pause]
API Call starts for "202 as"
User types: "h" → API call cancelled, new timer starts
[350ms pause]
API Call starts for "202 ash"
Results shown: Only "202 ash" results

Validation: Query checked before showing results
```

## Code Comparison

### searchAddresses Method

#### BEFORE
```swift
func searchAddresses(query: String) async {
    guard trimmed.count > 2 else {
        addressSearchResults = []
        return
    }
    
    isSearchingAddress = true
    defer { isSearchingAddress = false }
    
    // Make API call immediately
    let suggestions = try await placesAutocomplete.autocomplete(...)
    
    // Show results (no validation if query changed)
    addressSearchResults = results
}
```

#### AFTER
```swift
func searchAddresses(query: String) async {
    // Cancel any pending search
    searchDebounceTask?.cancel()
    
    // Track current query
    currentSearchQuery = query
    
    guard trimmed.count >= 3 else {
        addressSearchResults = []
        placesSessionToken = nil
        return
    }
    
    isSearchingAddress = true
    
    // Debounce: wait 350ms
    searchDebounceTask = Task {
        try await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        await performAddressSearch(query: trimmed)
    }
}

private func performAddressSearch(query: String) async {
    // Validate query still matches
    guard query == currentSearchQuery.trimmingCharacters(...) else {
        print("Query changed, discarding stale search")
        return
    }
    
    // Make API call
    let suggestions = try await placesAutocomplete.autocomplete(...)
    
    // Validate again before showing results
    guard query == currentSearchQuery.trimmingCharacters(...) else {
        print("Query changed after fetch, discarding results")
        return
    }
    
    // Show results only if still valid
    addressSearchResults = results
}
```

## Session Token Management

### BEFORE
```swift
// Session token created on each search
func searchAddresses(query: String) async {
    if placesSessionToken == nil { 
        placesSessionToken = UUID().uuidString 
    }
    // ... search logic
}

// Never cleared on selection
```

### AFTER
```swift
// Session token reused across searches
func performAddressSearch(query: String) async {
    if placesSessionToken == nil {
        placesSessionToken = UUID().uuidString
        print("🔑 Created new session token")
    }
    // ... search logic
}

// Cleared on selection to start fresh
func setCustomSearchCenter(...) {
    // ... other logic
    placesSessionToken = nil
}

func selectAddress(_ result: AddressResult) {
    // ... other logic
    placesSessionToken = nil
}
```

## Benefits at a Glance

| Issue | Before | After |
|-------|--------|-------|
| API calls per "hello" typed | 5 calls | 1 call (after 350ms pause) |
| Stale results | ⚠️ Possible | ✅ Prevented |
| Race conditions | ⚠️ Possible | ✅ Prevented |
| Session token | ⚠️ Created each search | ✅ Reused, cleared on selection |
| Fast typing | ⚠️ Laggy, many calls | ✅ Smooth, debounced |
| Query validation | ❌ None | ✅ Multiple checkpoints |

## Real-World Example

### Scenario: User searching for "202 Ashe Ave, Raleigh, NC"

#### BEFORE
1. Types "202" → Makes API call immediately
2. Types " a" → Makes another API call
3. Types "s" → Makes another API call
4. Types "h" → Makes another API call
5. API call from step 1 returns → Shows "202" results
6. API call from step 4 returns → Shows "202 ash" results
7. User confused because results flickered

**Total API Calls**: 4+
**User Experience**: Flickering, confusing

#### AFTER
1. Types "202" → Starts 350ms timer
2. Types " a" → Cancels timer, starts new one
3. Types "s" → Cancels timer, starts new one
4. Types "h" → Cancels timer, starts new one
5. [350ms pause]
6. Makes ONE API call for "202 ash"
7. Validates query hasn't changed
8. Shows "202 ash" results

**Total API Calls**: 1
**User Experience**: Smooth, no flickering

## Console Output Comparison

### BEFORE
```
🔍 [Autocomplete] Got 5 suggestions for '202'
🔍 [Autocomplete] Got 3 suggestions for '202 a'
✅ [Autocomplete] Displaying 5 search results
🔍 [Autocomplete] Got 4 suggestions for '202 as'
✅ [Autocomplete] Displaying 3 search results
🔍 [Autocomplete] Got 1 suggestions for '202 ash'
✅ [Autocomplete] Displaying 4 search results
✅ [Autocomplete] Displaying 1 search results
```

### AFTER
```
🔍 [Autocomplete] Search cancelled for '202'
🔍 [Autocomplete] Search cancelled for '202 a'
🔍 [Autocomplete] Search cancelled for '202 as'
🔑 [Autocomplete] Created new session token: ABC123...
🔍 [Autocomplete] Got 1 suggestions for '202 ash'
📋 [Places Details] Got details for 1 of 1 suggestions
✅ [Autocomplete] Displaying 1 search results (0 establishments, 1 addresses)
```

## What Stayed the Same

✅ All public APIs remain identical  
✅ No changes required in Views  
✅ `onChange` handler still calls `searchAddresses(query:)`  
✅ Same result types and data structures  
✅ Same UI/UX - users won't notice the difference (except it works better!)

## Implementation Matches React Solution

| React Concept | Swift Implementation |
|--------------|---------------------|
| `useState` for separate query/results | `currentSearchQuery` + `addressSearchResults` |
| `useEffect` with cleanup function | `Task` with cancellation check |
| `setTimeout` with `clearTimeout` | `Task.sleep` with `task.cancel()` |
| Session token in `useRef` | `placesSessionToken` property |
| Query validation before `setState` | Query validation before `MainActor.run` |
| 350ms debounce constant | 350_000_000 nanoseconds |

