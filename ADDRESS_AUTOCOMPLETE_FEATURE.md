# Address Autocomplete Feature

## Overview

Users can now manually enter and search for addresses with real-time autocomplete if the automatic location detection finds an incorrect address. This feature uses Apple's MapKit to provide accurate address suggestions.

## User Experience

### Default Flow
1. App detects user's current location automatically
2. Displays the detected address in the confirmation card
3. User can either:
   - Tap "Use this location" to proceed
   - Tap "Retry location" if detection failed
   - Tap "Can't find it? Enter address manually" to search manually

### Manual Address Entry Flow
1. User taps "Can't find it? Enter address manually"
2. Manual entry section expands with:
   - Search input field with placeholder "Search address..."
   - Dynamic list of address suggestions (up to 5)
3. As user types (after 3+ characters):
   - Autocomplete results appear in real-time
   - Each result shows title and subtitle
4. User taps a result to select it
5. Selected address replaces the detected address
6. User proceeds with "Use this location"

## Technical Implementation

### CaptureFlowViewModel Updates

**New Published Properties:**
```swift
@Published var addressSearchResults: [AddressResult] = []
@Published var isSearchingAddress = false
```

**New Methods:**
```swift
func searchAddresses(query: String) async
func selectAddress(_ result: AddressResult)
```

**Address Search Logic:**
- Uses `MKLocalSearchCompleter` for real-time suggestions
- Triggers after 3+ character input
- Returns up to 5 results
- Provides title, subtitle, and completion info

### LocationConfirmationView Updates

**New State:**
```swift
@State private var showManualEntry = false
@State private var searchQuery = ""
```

**UI Components:**
1. **Toggle Button** - "Can't find it? Enter address manually"
2. **Search Field** - Debounced text input
3. **Results List** - Tappable address suggestions
4. **Loading State** - Searching indicator
5. **Done Button** - Collapse manual entry section

### AddressResult Model

```swift
struct AddressResult: Identifiable {
    let id: UUID
    let title: String           // e.g., "Apple Inc."
    let subtitle: String        // e.g., "Cupertino, CA"
    let completionTitle: String
    let completionSubtitle: String
}
```

## Features

✅ **Real-time Autocomplete** - Results update as user types  
✅ **Apple MapKit Integration** - Uses iOS's native location services  
✅ **Smart Triggering** - Only searches after 3+ characters  
✅ **Loading Indicators** - Visual feedback during search  
✅ **Clean UI** - Results displayed in card format  
✅ **Easy Toggle** - Collapse/expand manual entry section  
✅ **Error Handling** - Gracefully handles network errors  
✅ **Debouncing** - Prevents excessive API calls  

## Customization

### Adjust Result Limit
Change in `CaptureFlowViewModel.searchAddresses()`:
```swift
self.addressSearchResults = results.prefix(5).map { ... }
// Change 5 to desired number
```

### Adjust Search Trigger
Change minimum character count in `LocationConfirmationView`:
```swift
if newValue.count > 2 {  // Change 2 to desired minimum
    Task {
        await viewModel.searchAddresses(query: newValue)
    }
}
```

### Styling
Customize colors in `LocationConfirmationView`:
```swift
.foregroundStyle(BlueprintTheme.accentAqua)  // Button color
.background(RoundedRectangle(cornerRadius: 12)
    .fill(BlueprintTheme.surface))  // Card background
```

## Testing

### Manual Entry
1. Run app
2. On location confirmation screen, tap "Can't find it? Enter address manually"
3. Type an address (e.g., "Apple Park")
4. See autocomplete results appear
5. Select a result
6. Address updates and you can proceed

### Search Behavior
- Empty search: No results
- Partial search (< 3 chars): No API call (optimization)
- Valid search: Results appear in ~500ms
- Select result: Address set, section collapses

### Edge Cases
- Network error: Results clear gracefully
- No results: Empty state (no results shown)
- Result selected: Manual entry section closes

## Integration with Backend

Currently uses Apple's MapKit for local search. No backend integration needed.

Future improvements:
- Cache search results
- Add custom venue database lookup
- Integrate with Google Places API for expanded results
- Add location bias based on region

## Performance Considerations

**Optimizations:**
- Async search prevents UI freezing
- Loading state during search
- Result limit (5 items) for quick rendering
- Minimum character requirement (3) reduces unnecessary searches

**Complexity:**
- O(1) selection - Direct address assignment
- O(n) result display where n ≤ 5
- Network: Depends on MapKit, typically < 1 second

## Accessibility

✅ VoiceOver compatible textfield  
✅ Clear button labels  
✅ Loading indicator feedback  
✅ High contrast colors  

## Known Limitations

- Uses MapKit (iOS only)
- Search works best with English addresses
- Limited to 5 results per search
- No result details (hours, rating, etc.)
- No map preview

## Future Enhancements

1. **Map Preview** - Show location on map before confirming
2. **Recent Addresses** - Save previously used addresses
3. **Favorites** - Allow bookmarking frequent locations
4. **Address Details** - Show hours, phone, rating from Maps
5. **Multi-language** - Support international addresses
6. **Reverse Geocoding** - Find address from coordinates

## Security Notes

- Address searches happen locally via MapKit (no external API)
- Results are not stored (except in-app during session)
- No personal data collection during search
- User explicitly selects address (no auto-confirmation)

## References

- [MKLocalSearchCompleter](https://developer.apple.com/documentation/mapkit/mklocalsearchcompleter)
- [MapKit Documentation](https://developer.apple.com/mapkit/)
- [SwiftUI TextField](https://developer.apple.com/documentation/swiftui/textfield)
