# Stripe Integration Flow Diagram

> Current-vs-public-copy note: This document is historical/internal Stripe architecture/debugging context. It is not current payout, provider, launch, buyer, or earnings proof, and it must not be reused as external capturer or startup copy without reconciling against `README.md`, `docs/CAPTURER_MARKETING_COPY_POSITIONING_2026-05-13.md`, and `docs/PUBLIC_COPY_TRUTH_INDEX_2026-05-24.md`.

## 📊 Overall Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        iOS App                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  StripeOnboardingView / SettingsView                     │  │
│  │  - Displays Stripe account status                        │  │
│  │  - Buttons to manage onboarding, payouts                 │  │
│  │  - Shows errors to user                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                          ↓ (calls)                               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  StripeConnectService                                    │  │
│  │  - Communicates with backend API                         │  │
│  │  - Handles network requests                              │  │
│  │  - Logs all operations to console [Stripe]               │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬──────────────────────────────────┘
                             │ (HTTP requests)
                             │
                    INTERNET │
                             │
┌────────────────────────────┴──────────────────────────────────┐
│                      Backend API                              │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  /v1/stripe/account                                      │ │
│  │  /v1/stripe/account/onboarding_link                      │ │
│  │  /v1/stripe/account/payout_schedule                      │ │
│  │  /v1/stripe/account/instant_payout                       │ │
│  └──────────────────────────────────────────────────────────┘ │
│                          ↓ (calls)                             │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Stripe API                                              │ │
│  │  - Fetches account details                               │ │
│  │  - Creates onboarding links                              │ │
│  │  - Updates payout settings                               │ │
│  │  - Processes payouts                                     │ │
│  └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## 🔄 Request/Response Flow - Account Status

```
iOS App                          Backend                         Stripe
   │                               │                               │
   │  GET /v1/stripe/account       │                               │
   ├──────────────────────────────→│                               │
   │  [Stripe] Fetching account    │                               │
   │  [Stripe] Request URL: ...    │    GET /v1/accounts/acct_     │
   │                               ├──────────────────────────────→│
   │                               │                               │
   │                               │    200 OK {account data}      │
   │                               │←──────────────────────────────┤
   │                               │                               │
   │     200 OK {account_state}    │                               │
   │←──────────────────────────────┤                               │
   │  [Stripe] Response status 200 │                               │
   │  [Stripe] ✓ Account state OK  │                               │
   │                               │                               │
```

## 🔄 Request/Response Flow - Error Case

```
iOS App                          Backend                         Stripe
   │                               │                               │
   │  GET /v1/stripe/account       │                               │
   ├──────────────────────────────→│                               │
   │  [Stripe] Fetching account    │                               │
   │  [Stripe] Request URL: ...    │    GET /v1/accounts/acct_     │
   │                               ├──────────────────────────────→│
   │                               │                               │
   │                               │    401 Unauthorized           │
   │                               │←──────────────────────────────┤
   │     401 Unauthorized          │                               │
   │←──────────────────────────────┤                               │
   │  [Stripe] Response status 401 │                               │
   │  [Stripe] ✗ HTTP 401: {...}  │                               │
   │  [StripeUI] ✗ Error loading   │                               │
   │                               │                               │
   │  Show alert to user           │                               │
   │  "Unable to load status"      │                               │
   │                               │                               │
```

## 🔍 Logging Points Throughout the Flow

```
┌─ Start ─────────────────────────────────────────────────────┐
│                                                               │
│  [Stripe] Fetching account state...                          │
│                                                               │
├─ Configuration Check ───────────────────────────────────────┤
│                                                               │
│  if backendBaseURL() == nil:                                 │
│    ✗ [Stripe] Missing backend URL configuration             │
│    └─→ Throw missingConfiguration                           │
│                                                               │
│  else:                                                        │
│    ✓ [Stripe] Using backend URL: https://api.example.com    │
│                                                               │
├─ Request Creation ──────────────────────────────────────────┤
│                                                               │
│  ✓ [Stripe] Created GET request to: https://...             │
│  ✓ [Stripe] Request URL: https://api.example.com/...        │
│                                                               │
├─ Network Call ──────────────────────────────────────────────┤
│                                                               │
│  [Stripe] Performing request: GET https://...               │
│                                                               │
├─ Response Received ─────────────────────────────────────────┤
│                                                               │
│  [Stripe] Response status: 200                               │
│                                                               │
│  Status code check:                                          │
│  ├─ 2xx (200-299): Continue                                 │
│  ├─ 3xx (300-399): ✗ [Stripe] ✗ HTTP 3xx                   │
│  ├─ 4xx (400-499): ✗ [Stripe] ✗ HTTP 4xx: {error}          │
│  └─ 5xx (500-599): ✗ [Stripe] ✗ HTTP 5xx: {error}          │
│                                                               │
├─ Data Decoding ─────────────────────────────────────────────┤
│                                                               │
│  Try decode StripeAccountState:                              │
│  ├─ Success: ✓ [Stripe] ✓ Account state OK                  │
│  └─ Fail: ✗ [Stripe] ✗ Decoding error                       │
│           ✗ [Stripe] Response body: {JSON}                  │
│                                                               │
├─ Return to UI ──────────────────────────────────────────────┤
│                                                               │
│  Success:                                                    │
│  └─ Return StripeAccountState                               │
│     [StripeUI] (no error)                                   │
│                                                               │
│  Error:                                                      │
│  └─ Throw error                                              │
│     [StripeUI] ✗ Error loading account state: {error}       │
│     → Show alert to user                                     │
│                                                               │
└─ End ──────────────────────────────────────────────────────┘
```

## 🛠️ Error Handling Paths

### Path 1: Missing Configuration
```
StripeConnectService.fetchAccountState()
  │
  ├─→ Check backendBaseURL()
  │   └─ nil → [Stripe] ✗ Missing backend URL configuration
  │           Throw missingConfiguration error
  │
  └─→ StripeOnboardingView.loadAccountState() catches
      └─ [StripeUI] ✗ Error loading account state
          Show "Unable to load Stripe account status."
```

### Path 2: Network/HTTP Error
```
StripeConnectService.perform()
  │
  ├─→ URLSession.data(for: request)
  │   └─ Failure → [Stripe] ✗ Network error: {error}
  │               Throw networkError
  │
  └─→ StripeOnboardingView catches
      └─ [StripeUI] ✗ Error loading account state
          Show "Unable to load Stripe account status."
```

### Path 3: HTTP Non-2xx Status
```
StripeConnectService.perform()
  │
  ├─→ Check status code (200..<300)
  │   └─ Fail (e.g., 401) → [Stripe] ✗ HTTP 401: {body}
  │                         Throw invalidResponse
  │
  └─→ StripeOnboardingView catches
      └─ [StripeUI] ✗ Error loading account state
          Show "Unable to load Stripe account status."
```

### Path 4: JSON Decoding Error
```
StripeConnectService.fetchAccountState()
  │
  ├─→ JSONDecoder.decode(StripeAccountState.self)
  │   └─ Fail → [Stripe] ✗ Decoding error: {error}
  │             [Stripe] Response body: {JSON}
  │             Throw decodingError
  │
  └─→ StripeOnboardingView catches
      └─ [StripeUI] ✗ Error loading account state
          Show "Unable to load Stripe account status."
```

## 📱 UI Layer - Where Users See Results

```
StripeOnboardingView
┌─────────────────────────────────┐
│                                 │
│  .task {                         │
│    await loadAccountState()      │
│  }                               │
│                                 │
│  if let state = accountState {  │
│    // Display account info      │
│    Label { "Account ready" }    │
│  }                               │
│                                 │
│  .alert("Error", isPresented: ) │
│    Text(errorMessage)           │
│    Button("OK") { }             │
│                                 │
└─────────────────────────────────┘
```

## 🔑 Key Log Markers

| Marker | Meaning | Next Action |
|--------|---------|-------------|
| `[Stripe]` | Service-level log | Check network/configuration |
| `[StripeUI]` | UI-level error | Error shown to user |
| `✓` | Success | Operation completed |
| `✗` | Error | Read error details |

## 🚨 Common Failure Points

```
1. Configuration Missing
   └─ No BACKEND_BASE_URL in Secrets.plist
   └─ Log: ✗ Missing backend URL configuration
   └─ Fix: Add to Secrets.plist

2. Backend Offline
   └─ Backend server not running
   └─ Log: ✗ Network error: Connection refused
   └─ Fix: Start backend server

3. Endpoint Not Implemented
   └─ Backend doesn't have /v1/stripe/account
   └─ Log: ✗ HTTP 404: Not Found
   └─ Fix: Implement endpoint

4. Authentication Failed
   └─ Invalid Stripe API keys on backend
   └─ Log: ✗ HTTP 401: Invalid API key
   └─ Fix: Check backend configuration

5. Response Format Wrong
   └─ Backend returns unexpected JSON structure
   └─ Log: ✗ Decoding error + Response body: {...}
   └─ Fix: Match response schema

6. Wrong Environment
   └─ Using test keys in production or vice versa
   └─ Log: Will work but test data won't match reality
   └─ Fix: Use correct environment keys
```

## 📊 Data Flow Diagram

```
Secrets.plist
    │
    ├─ BACKEND_BASE_URL ──→ AppConfig.backendBaseURL()
    ├─ STRIPE_ACCOUNT_ID ─→ AppConfig.stripeAccountID()
    └─ STRIPE_*_KEY ──────→ AppConfig.stripe*()
                               │
                               ↓
                   StripeConnectService
                               │
                ┌──────────────┼──────────────┐
                │              │              │
                ↓              ↓              ↓
          fetchAccountState  createOnboardingLink  updatePayoutSchedule
                │              │              │
                └──────────────┼──────────────┘
                               │
                               ↓
                          Backend API
                               │
                               ↓
                        Stripe API
                               │
                ┌──────────────┼──────────────┐
                │              │              │
                ↓              ↓              ↓
        Account Details  Onboarding URL  Updated Settings
                │              │              │
                └──────────────┼──────────────┘
                               │
                               ↓
                  JSON Response Decoding
                               │
        ┌──────────────────────┴──────────────────────┐
        │                                              │
        ↓                                              ↓
    StripeAccountState                         DecodingError
        │                                              │
        ↓                                              ↓
    Success Callback                         Error Handler
        │                                              │
        ↓                                              ↓
    Update UI State                        Show Error Message
    Display Account Info
```

---

**Note:** All logging includes timestamps and full error details for debugging in the Xcode console.
