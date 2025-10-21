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
- StripeBillingSetupView (sheet)

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

## Bank Connection

### StripeBillingSetupView.swift
**Purpose**: Bank connection setup flow
**Sections**:
1. Header with icon and description
2. Feature highlights (3 rows)
3. Plaid + Stripe info box
4. Connect button
5. Legal links (Plaid & Stripe terms)

**Features**:
- Opens PlaidLinkSimulationView as sheet
- Handles successful connections
- Shows error alerts
- Loading states
- Links to external terms

---

### PlaidLinkSimulationView.swift
**Purpose**: Simulates Plaid Link interface (replace with real Plaid SDK)
**Components**:
- Bank selection picker (5 sample banks)
- Account details card preview
- Confirm & Connect button
- Cancel button

**Sample Banks**:
1. Chase Bank
2. Bank of America
3. Wells Fargo
4. Citibank
5. US Bank

**Features**:
- Wheel picker for bank selection
- Account type display (Checking)
- Account number preview (masked)
- Async connection with delay
- Callback to parent when complete

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
| SettingsView.swift | ~250 | Main settings UI |
| SettingsViewModel.swift | ~200 | State + API service |
| EditProfileView.swift | ~70 | Profile editing form |
| StripeBillingSetupView.swift | ~350 | Bank setup flow |
| PlaidLinkSimulationView.swift | ~150 | Bank picker simulation |
| **Total** | **~1,040** | **New functionality** |

---

## Integration Points

### To Connect Real Plaid:
1. Install Plaid SDK
2. Replace PlaidLinkSimulationView with PlaidLinkViewController
3. Pass real Plaid public key
4. Handle real public tokens

### To Connect Real Backend:
1. Update APIService base URL
2. Replace mock delays with real URLSession calls
3. Add authentication headers
4. Handle real error responses

### To Connect Stripe:
1. Backend exchanges Plaid token
2. Create Stripe Connect account
3. Store Stripe account ID
4. Set up payout schedules

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
