# Stripe Debugging Implementation ✅

> Current-vs-public-copy note: This document is historical/internal Stripe debugging context. It is not current payout, provider, launch, buyer, or earnings proof, and it must not be reused as external capturer or startup copy without reconciling against `README.md`, `docs/CAPTURER_MARKETING_COPY_POSITIONING_2026-05-13.md`, and `docs/PUBLIC_COPY_TRUTH_INDEX_2026-05-24.md`.

## What Was Done

Your Stripe integration now has **comprehensive console logging** to help you debug the "Unable to load Stripe account status" and "Failed to open onboarding" errors.

### Changes Made

**2 Files Modified:**
```
✓ BlueprintCapture/Services/StripeConnectService.swift
  └─ Added detailed [Stripe] logging to all API calls
  └─ Logs HTTP status codes, response bodies, errors
  └─ Validates configuration with helpful messages
  
✓ BlueprintCapture/StripeOnboardingView.swift  
  └─ Added [StripeUI] error logging
  └─ Prints actual error reasons to console
```

**6 Documentation Files Created:**
```
📄 STRIPE_DEBUG_QUICK_START.md
   Quick reference with common issues and fixes

📄 STRIPE_DEBUGGING_GUIDE.md
   Complete guide with all error scenarios

📄 STRIPE_CONFIGURATION_CHECKLIST.md
   Full configuration requirements for client and backend

📄 STRIPE_FLOW_DIAGRAM.md
   Visual diagrams of the system architecture and flows

📄 STRIPE_ISSUE_SUMMARY.md
   Summary of problem and solution

📄 STRIPE_ERROR_REFERENCE.txt
   Quick error lookup table (keep open while debugging)
```

## How to Use

### Step 1: Open the Console
```
Xcode → View → Debug Area → Show Debug Area (⌘⇧Y)
```

### Step 2: Filter for Stripe Logs
In the console at the bottom, type: `Stripe`

### Step 3: Reproduce the Error
- Try opening the Stripe Payouts screen
- Try clicking "Open Stripe Onboarding"

### Step 4: Check the Console Output

You'll now see detailed logs like:

**✅ Success:**
```
[Stripe] Fetching account state...
[Stripe] Using backend URL: https://api.example.com
[Stripe] Response status: 200
[Stripe] ✓ Account state fetched successfully
```

**❌ Error:**
```
[Stripe] Fetching account state...
[Stripe] ✗ Missing backend URL configuration
```

**❌ HTTP Error:**
```
[Stripe] Response status: 401
[Stripe] ✗ HTTP 401: {"error":"Invalid API key"}
```

## Most Likely Issues

### 1. "Missing backend URL configuration"
**Solution:** Add to `Secrets.plist`:
```xml
<key>BACKEND_BASE_URL</key>
<string>https://your-backend.com</string>
```

### 2. "HTTP 401: Invalid API key"
**Solution:** Verify on backend:
- `STRIPE_SECRET_KEY` is set
- `STRIPE_CONNECT_ACCOUNT_ID` is set
- Using correct environment (test vs live)

### 3. "HTTP 404: Not Found"
**Solution:** Implement these endpoints on backend:
- `GET /v1/stripe/account`
- `POST /v1/stripe/account/onboarding_link`
- `PUT /v1/stripe/account/payout_schedule`
- `POST /v1/stripe/account/instant_payout`

### 4. "Decoding error" + Response body
**Solution:** Ensure backend returns:
```json
{
  "onboarding_complete": true,
  "payouts_enabled": true,
  "payout_schedule": "weekly",
  "instant_payout_eligible": false,
  "next_payout": {
    "estimated_arrival": "2025-10-27T00:00:00Z",
    "amount_cents": 50000
  },
  "requirements_due": null
}
```

### 5. "Network error"
**Solution:**
- Check internet connection
- Verify backend URL is correct
- Start backend server
- Check backend is accessible: `curl https://your-backend.com`

## Console Log Examples

### ✅ Successful Account State Load
```
[Stripe] Fetching account state...
[Stripe] Using backend URL: https://api.example.com
[Stripe] Request URL: https://api.example.com/v1/stripe/account
[Stripe] Created GET request to: https://api.example.com/v1/stripe/account
[Stripe] Performing request: GET https://api.example.com/v1/stripe/account
[Stripe] Response status: 200
[Stripe] ✓ Request successful (status 200)
[Stripe] ✓ Account state fetched successfully
[Stripe] Account ready: true, Payouts enabled: true
```

### ❌ Missing Backend URL
```
[Stripe] Fetching account state...
[Stripe] ✗ Missing backend URL configuration
[StripeUI] ✗ Error loading account state: missingConfiguration
```

### ❌ Backend Offline
```
[Stripe] Fetching account state...
[Stripe] Using backend URL: https://api.example.com
[Stripe] Request URL: https://api.example.com/v1/stripe/account
[Stripe] ✗ Network error: The network connection was lost.
```

### ❌ Stripe API Keys Wrong
```
[Stripe] Response status: 401
[Stripe] ✗ HTTP 401: {"error":"Invalid API key"}
[StripeUI] ✗ Error loading account state: invalidResponse(status: 401)
```

### ❌ Endpoint Not Implemented
```
[Stripe] Response status: 404
[Stripe] ✗ HTTP 404: Not Found
```

### ❌ Response Format Wrong
```
[Stripe] ✗ Decoding error: keyNotFound(CodingKeys(stringValue: "payout_schedule"...))
[Stripe] Response body: {"onboarding_complete":true,"payouts_enabled":false}
```

## Debugging Checklist

- [ ] Backend URL is set in `Secrets.plist`
- [ ] Backend server is running
- [ ] All 4 Stripe endpoints are implemented
- [ ] Stripe API keys are configured on backend
- [ ] Response JSON matches expected schema
- [ ] Console shows ✓ success markers
- [ ] App displays account state without errors

## Documentation Guide

| Document | Purpose |
|----------|---------|
| `STRIPE_DEBUG_QUICK_START.md` | Quick reference, common fixes |
| `STRIPE_DEBUGGING_GUIDE.md` | Detailed troubleshooting, all scenarios |
| `STRIPE_CONFIGURATION_CHECKLIST.md` | Complete setup, endpoints, examples |
| `STRIPE_FLOW_DIAGRAM.md` | Architecture, flows, diagrams |
| `STRIPE_ISSUE_SUMMARY.md` | What was wrong and what was fixed |
| `STRIPE_ERROR_REFERENCE.txt` | Error lookup table (keep open) |

## Backend Requirements

Your backend MUST implement these endpoints:

### 1. Get Account State
```
GET /v1/stripe/account
Returns: {
  "onboarding_complete": boolean,
  "payouts_enabled": boolean,
  "payout_schedule": "weekly|daily|monthly|manual",
  "instant_payout_eligible": boolean,
  "next_payout": {
    "estimated_arrival": "ISO8601 date",
    "amount_cents": number
  },
  "requirements_due": [string] or null
}
```

### 2. Create Onboarding Link
```
POST /v1/stripe/account/onboarding_link
Returns: {
  "onboarding_url": "https://connect.stripe.com/..."
}
```

### 3. Update Payout Schedule
```
PUT /v1/stripe/account/payout_schedule
Body: { "schedule": "weekly" }
Returns: {}
```

### 4. Trigger Instant Payout
```
POST /v1/stripe/account/instant_payout
Body: { "amount_cents": 100000 }
Returns: {}
```

## Log Markers Explained

| Marker | Meaning |
|--------|---------|
| `[Stripe]` | Service-level operation |
| `[StripeUI]` | User interface layer |
| `✓` | Success |
| `✗` | Error |

## Next Steps

1. **Run the app** in Xcode
2. **Open Debug Area** (⌘⇧Y)
3. **Type "Stripe"** in console filter
4. **Open Stripe screen** or click button
5. **Read the console output** for actual error
6. **Match error to documentation** and fix
7. **Rebuild and test** (⌘B then run)

## Questions?

- **Quick debug?** → `STRIPE_DEBUG_QUICK_START.md`
- **Specific error?** → `STRIPE_DEBUGGING_GUIDE.md`
- **How to configure?** → `STRIPE_CONFIGURATION_CHECKLIST.md`
- **System design?** → `STRIPE_FLOW_DIAGRAM.md`
- **Error lookup?** → `STRIPE_ERROR_REFERENCE.txt`

---

**Implementation Date:** October 25, 2025  
**Status:** ✅ Complete - All logging added and documented
