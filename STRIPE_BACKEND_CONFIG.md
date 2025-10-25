# Stripe Backend Configuration - Blueprint

## Your Backend Setup

**Backend Base URL:**
```
https://www.tryblueprint.io
```

**All endpoints are at:** `/v1/stripe/`

## Required Secrets.plist Configuration

Add this to `BlueprintCapture/Support/Secrets.plist`:

```xml
<key>BACKEND_BASE_URL</key>
<string>https://www.tryblueprint.io</string>
```

That's it! The app will automatically append `/v1/stripe/...` to create the full endpoints.

## Your Endpoints

### 1. Fetch Account Status
```
GET https://www.tryblueprint.io/v1/stripe/account
```

**Response:**
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

### 2. Create Onboarding Link
```
POST https://www.tryblueprint.io/v1/stripe/account/onboarding_link
```

**Response:**
```json
{
  "onboarding_url": "https://connect.stripe.com/oauth/authorize?..."
}
```

### 3. Update Payout Schedule
```
PUT https://www.tryblueprint.io/v1/stripe/account/payout_schedule
```

**Request Body:**
```json
{
  "schedule": "weekly"
}
```

**Valid schedules:** `daily`, `weekly`, `monthly`, `manual`

**Response:**
```json
{}
```

### 4. Trigger Instant Payout
```
POST https://www.tryblueprint.io/v1/stripe/account/instant_payout
```

**Request Body:**
```json
{
  "amount_cents": 100000
}
```

**Response:**
```json
{}
```

## Testing Your Backend

### Test 1: Verify Backend is Reachable
```bash
curl -i https://www.tryblueprint.io/v1/stripe/account
```

Should return `200 OK` or `401 Unauthorized` (not `404` or timeout).

### Test 2: Run the App and Check Logs

1. **Add BACKEND_BASE_URL to Secrets.plist** (see above)
2. **Open Xcode console:** `⌘⇧Y`
3. **Filter for "Stripe":** Type in console search
4. **Open Stripe Payouts screen** in the app
5. **Check console for logs:**

**Expected success logs:**
```
[Stripe] Fetching account state...
[Stripe] Using backend URL: https://www.tryblueprint.io
[Stripe] Request URL: https://www.tryblueprint.io/v1/stripe/account
[Stripe] Response status: 200
[Stripe] ✓ Account state fetched successfully
[Stripe] Account ready: true, Payouts enabled: true
```

**Common errors:**

| Error | Meaning | Fix |
|-------|---------|-----|
| `Missing backend URL` | BACKEND_BASE_URL not set | Add to Secrets.plist |
| `HTTP 404: Not Found` | Backend endpoint not implemented | Check backend |
| `HTTP 401: Unauthorized` | Auth failed or invalid Stripe keys | Check backend Stripe config |
| `Network error` | Can't reach backend | Verify URL and backend is running |

## How the App Uses These Endpoints

### When App Starts / Opens Stripe Screen
```
App calls:
  GET /v1/stripe/account
  
Backend calls:
  GET https://api.stripe.com/v1/accounts/{account_id}
  
Backend returns to App:
  {"onboarding_complete": true, ...}
  
App displays:
  ✓ Account status, payout schedule, next payout date
```

### When User Clicks "Open Stripe Onboarding"
```
App calls:
  POST /v1/stripe/account/onboarding_link
  
Backend calls:
  POST https://api.stripe.com/v1/account_links
  
Backend returns to App:
  {"onboarding_url": "https://connect.stripe.com/..."}
  
App opens:
  Safari/browser with Stripe Express onboarding
```

### When User Updates Payout Schedule
```
App calls:
  PUT /v1/stripe/account/payout_schedule
  Body: {"schedule": "weekly"}
  
Backend calls:
  POST https://api.stripe.com/v1/accounts/{account_id}
  With: settings[payouts][schedule]=weekly
  
Backend returns to App:
  {}
  
App refreshes:
  Account status reflects new schedule
```

### When User Clicks "Cash Out Now"
```
App calls:
  POST /v1/stripe/account/instant_payout
  Body: {"amount_cents": 100000}
  
Backend calls:
  POST https://api.stripe.com/v1/payouts
  
Backend returns to App:
  {} (or error if insufficient funds)
  
App displays:
  Success message or error
```

## Secrets.plist Setup - Complete

Open `BlueprintCapture/Support/Secrets.plist` and add/update:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Stripe Backend Configuration - REQUIRED -->
    <key>BACKEND_BASE_URL</key>
    <string>https://www.tryblueprint.io</string>
    
    <!-- Stripe Keys (already should be set) -->
    <key>STRIPE_PUBLISHABLE_KEY</key>
    <string>pk_test_...</string>
    
    <key>STRIPE_ACCOUNT_ID</key>
    <string>acct_...</string>
    
    <!-- Other existing keys -->
    <key>GOOGLE_PLACES_API_KEY</key>
    <string>AIza...</string>
    
    <key>STREET_VIEW_API_KEY</key>
    <string>AIza...</string>
    
    <key>GEMINI_API_KEY</key>
    <string>AIza...</string>
</dict>
</plist>
```

## Quick Start Checklist

- [ ] Add `BACKEND_BASE_URL` to `Secrets.plist`
- [ ] Verify backend is running: `curl https://www.tryblueprint.io/v1/stripe/account`
- [ ] Open app in Xcode
- [ ] Open Debug Area: `⌘⇧Y`
- [ ] Filter console for "Stripe"
- [ ] Open Stripe Payouts screen
- [ ] Check console for logs with ✓ success markers
- [ ] If errors, check error reference

## Debugging Tips

### Backend URL Not Configured
```
Console shows:
  [Stripe] ✗ Missing backend URL configuration

Fix:
  1. Open Secrets.plist
  2. Add BACKEND_BASE_URL key
  3. Set value to: https://www.tryblueprint.io
  4. Save file
  5. Rebuild app (⌘B)
```

### Backend Offline
```
Console shows:
  [Stripe] ✗ Network error: Connection refused

Fix:
  1. Verify backend URL is correct
  2. Check backend is running
  3. Test: curl https://www.tryblueprint.io/v1/stripe/account
```

### Wrong Response Format
```
Console shows:
  [Stripe] ✗ Decoding error: keyNotFound(...)
  [Stripe] Response body: {...}

Fix:
  Check backend is returning all required fields:
  - onboarding_complete
  - payouts_enabled
  - payout_schedule
  - instant_payout_eligible
  - next_payout (or null)
  - requirements_due (or null)
```

## More Help

- **Quick debugging?** → `STRIPE_ERROR_REFERENCE.txt`
- **Backend setup?** → This file (you're reading it!)
- **Detailed guide?** → `STRIPE_DEBUGGING_GUIDE.md`
- **Endpoint specs?** → `STRIPE_CONFIGURATION_CHECKLIST.md`

---

**Backend:** Replit (blueprint-vision-fork-nijelhunt)  
**Base URL:** `https://www.tryblueprint.io`  
**Endpoints:** `/v1/stripe/account`, `/v1/stripe/account/onboarding_link`, `/v1/stripe/account/payout_schedule`, `/v1/stripe/account/instant_payout`
