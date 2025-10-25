# Stripe Debugging - Quick Start

## What Was Added

✅ **Comprehensive Console Logging** to all Stripe operations with `[Stripe]` and `[StripeUI]` prefixes
✅ **Error Details Printed** - All errors now show the actual reason in console
✅ **Configuration Validation** - Logs when required settings are missing
✅ **Request/Response Logging** - URLs, HTTP status codes, and response bodies are logged

## How to Debug Now

### Step 1: Open Xcode Console
```
Xcode → View → Debug Area → Show Debug Area (or ⌘⇧Y)
```

### Step 2: Filter for Stripe Logs
- In the console at the bottom, type `Stripe` in the search field

### Step 3: Reproduce the Error
- Try to load the Stripe Payouts screen
- Try to click "Open Stripe Onboarding"

### Step 4: Read the Console Output
Look for patterns like:

**Success:**
```
[Stripe] ✓ Account state fetched successfully
[Stripe] Account ready: true, Payouts enabled: true
```

**Missing Configuration:**
```
[Stripe] ✗ Missing backend URL configuration
```

**HTTP Error:**
```
[Stripe] ✗ HTTP 401: {"error":"Invalid API key"}
```

**Decoding Error:**
```
[Stripe] ✗ Decoding error: ...
[Stripe] Response body: {...actual JSON response...}
```

## Most Likely Issues

### 1️⃣ `Unable to load Stripe account status` + Missing Backend URL
**Console shows:** `[Stripe] ✗ Missing backend URL configuration`

**Fix:** Add to `Secrets.plist`:
```xml
<key>BACKEND_BASE_URL</key>
<string>https://your-backend-domain.com</string>
```

### 2️⃣ `Failed to open onboarding` + HTTP 404
**Console shows:** `[Stripe] ✗ HTTP 404: Not Found`

**Fix:** Verify backend implements `/v1/stripe/account/onboarding_link` endpoint

### 3️⃣ HTTP 401 Unauthorized
**Console shows:** `[Stripe] ✗ HTTP 401: {"error":"..."}`

**Fix:** 
- Verify backend is running
- Check Stripe API keys are configured on backend
- Ensure user is authenticated if needed

### 4️⃣ Decoding Error
**Console shows:** `[Stripe] ✗ Decoding error:` + response JSON

**Fix:** Backend response format doesn't match expected structure. Check JSON structure matches the required schema.

## Required Backend Endpoints

Your backend must have these endpoints:

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/v1/stripe/account` | Fetch account state |
| POST | `/v1/stripe/account/onboarding_link` | Create onboarding link |
| PUT | `/v1/stripe/account/payout_schedule` | Update payout schedule |
| POST | `/v1/stripe/account/instant_payout` | Trigger instant payout |

## Files Modified

- `BlueprintCapture/Services/StripeConnectService.swift` - Added detailed logging to all API calls
- `BlueprintCapture/StripeOnboardingView.swift` - Added error logging to all error handlers

## Next Steps

1. **Run the app** and open the Stripe Payouts screen
2. **Check the console** for the exact error message
3. **Use this guide** to identify and fix the issue
4. See `STRIPE_DEBUGGING_GUIDE.md` for detailed troubleshooting
