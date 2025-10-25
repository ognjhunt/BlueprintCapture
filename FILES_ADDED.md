# New Files Structure

## Tab Bar System

### MainTabView.swift
**Purpose**: Container view that manages tab switching between Scan and Settings
**Key Components**:
- TabView with 2 tabs
- Camera.viewfinder icon for Scan tab
- Person.circle.fill icon for Settings tab
- Blueprint blue tint color

**Quick Look**:
```swift
struct MainTabView: View {
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView() // Scan tab
            SettingsView() // Settings tab
        }
    }
}
```

---

## Settings Tab

### SettingsView.swift
**Purpose**: Main settings interface showing profile, earnings, and billing
**Sections**:
1. Profile Card - User info and quick edit button
2. Earnings Card - Shows total earned, pending payout, scans completed
3. Billing Card - Connected bank or connect button
4. Account Settings - Edit profile, privacy, sign out

**Dependencies**: 
- SettingsViewModel (state)
- EditProfileView (sheet)
- StripeOnboardingView (sheet)

---

### SettingsViewModel.swift
**Purpose**: State management + mock API service
**Contains**:
- SettingsError enum
- SettingsViewModel class with @Published properties
- APIService class with mock implementations

**Published Properties**:
- profile: UserProfile
- totalEarnings: Decimal
- pendingPayout: Decimal
- scansCompleted: Int
- billingInfo: BillingInfo?
- isLoading: Bool
- error: SettingsError?

**Key Methods**:
- loadUserData() - Fetch all user data
- startEditingProfile() / cancelEditingProfile()
- saveProfile() - Save edited profile
- connectPlaidBank() - Connect bank account
- disconnectBankAccount() - Remove bank account

**APIService Methods** (Mock):
- fetchUserProfile()
- updateUserProfile()
- fetchEarnings()
- fetchBillingInfo()
- exchangePlaidToken()
- createStripeAccount()
- disconnectBankAccount()

---

### EditProfileView.swift
**Purpose**: Form for editing user profile
**Fields**:
- Full Name (text)
- Email (email keyboard)
- Phone Number (phone keyboard)
- Company (text)

**Features**:
- Input validation (name and email required)
- Email format validation (@)
- Loading state with overlay
- Error alerts
- Save/Cancel buttons
- Uses Form with Sections

---

## Payouts

### StripeOnboardingView.swift
**Purpose**: Stripe Connect onboarding & payout management
**Sections**:
1. Account status and requirements
2. Open hosted onboarding
3. Payout schedule controls
4. Instant payout (when eligible)

---

## Data Models (Updated)

### BillingInfo (in SettingsViewModel.swift)
```swift
struct BillingInfo: Codable, Identifiable {
    let id: UUID
    let bankName: String          // "Chase Bank"
    let lastFour: String          // "4242"
    let accountHolderName: String // "Jordan Smith"
    let stripeAccountId: String   // "acct_..."
}
```

### UserProfile (existing, no changes)
```swift
struct UserProfile: Identifiable {
    let id: UUID
    var fullName: String
    var email: String
    var phoneNumber: String
    var company: String
}
```

---

## File Summary

| File | Lines | Purpose |
|------|-------|---------|
| MainTabView.swift | ~20 | Tab navigation container |
| SettingsView.swift | ~430 | Main settings UI |
| SettingsViewModel.swift | ~585 | State + API service |
| EditProfileView.swift | ~70 | Profile editing form |
| StripeOnboardingView.swift | ~230 | Stripe onboarding & payouts |
| **Total** | **~1,040** | **New functionality** |

---

## Integration Points

### To Connect Real Backend:
1. Update APIService base URL
2. Replace mock delays with real URLSession calls
3. Add authentication headers
4. Handle real error responses

### To Connect Stripe:
1. Enable Connect (Express) in Dashboard
2. Implement account link + account state endpoints
3. Store Stripe account ID
4. Set up payout schedules / instant payouts

---

## Testing Tips

1. **Tab Navigation**: Tap between Scan and Settings tabs
2. **Profile Editing**: Edit profile, see changes in form (mock save)
3. **Bank Connection**: 
   - Click "Connect Bank Account"
   - Select a bank from picker
   - Confirm connection
   - See "connected" state
   - Try "Change Bank Account" or "Disconnect"
4. **Error Handling**: Network errors show alert with description
5. **Loading States**: All async operations show loading overlay

---

## Git Status

New files (untracked):
- BlueprintCapture/MainTabView.swift
- BlueprintCapture/SettingsView.swift
- BlueprintCapture/SettingsViewModel.swift
- BlueprintCapture/EditProfileView.swift
- BlueprintCapture/StripeBillingSetupView.swift
- BlueprintCapture/EditProfileView.swift (created via terminal)

Modified files:
- BlueprintCapture/BlueprintCaptureApp.swift (root view changed to MainTabView)

---

## No Breaking Changes

✅ Existing ContentView still works (now in Scan tab)
✅ CaptureSessionView unchanged
✅ All existing models still work
✅ Theme system extended (not changed)
✅ Project builds without errors
