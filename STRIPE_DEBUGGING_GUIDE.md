# Stripe Debugging Guide

## Console Logging Overview

All Stripe-related operations now log detailed information to Xcode's console with prefixes for easy filtering:

- **[Stripe]** - Service-level logs (API calls, network requests, configuration)
- **[StripeUI]** - UI-level logs (user interactions, view state changes)

## How to View Logs in Xcode

1. Open Xcode
2. Run your app
3. Open the **Debug Area** (View → Debug Area → Show Debug Area or ⌘⇧Y)
4. In the console at the bottom, filter by typing "Stripe" to see all Stripe-related logs

## Common Error Scenarios & Solutions

### Error: "Unable to load Stripe account status"

**Console Output Should Show:**
```
[Stripe] Fetching account state...
[Stripe] Using backend URL: https://your-backend.com
[Stripe] Request URL: https://your-backend.com/v1/stripe/account
[Stripe] ✗ HTTP 401: {error details}
```

**Common Causes:**

1. **Missing or Invalid Backend URL**
   ```
   [Stripe] ✗ Missing backend URL configuration
   ```
   - **Solution:** Verify `BACKEND_BASE_URL` is set in `Secrets.plist`

2. **HTTP 401 (Unauthorized)**
   ```
   [Stripe] ✗ HTTP 401: {"error":"Invalid API key"}
   ```
   - **Solution:** Check backend is running and API keys are correct

3. **HTTP 500 (Server Error)**
   ```
   [Stripe] ✗ HTTP 500: Internal server error
   ```
   - **Solution:** Check backend logs for the actual error

4. **Decoding Error**
   ```
   [Stripe] ✗ Decoding error: Swift.DecodingError...
   [Stripe] Response body: {actual response JSON}
   ```
   - **Solution:** Backend response format doesn't match expected `StripeAccountState` structure. Check backend is returning correct fields.

5. **Network Error**
   ```
   [Stripe] ✗ Network error: The network connection was lost.
   ```
   - **Solution:** Check internet connection and backend URL is reachable

### Error: "Failed to open onboarding"

**Console Output Should Show:**
```
[Stripe] Creating onboarding link...
[Stripe] Using backend URL: https://your-backend.com
[Stripe] Request URL: https://your-backend.com/v1/stripe/account/onboarding_link
[Stripe] ✗ HTTP 400: {error details}
```

**Common Causes:**

1. **Missing Backend URL**
   ```
   [Stripe] ✗ Missing configuration: No backend URL or fallback onboarding URL
   ```
   - **Solution:** Ensure `BACKEND_BASE_URL` is set in `Secrets.plist`

2. **Endpoint Not Found**
   ```
   [Stripe] ✗ HTTP 404: Not Found
   ```
   - **Solution:** Backend endpoint `/v1/stripe/account/onboarding_link` is not implemented

3. **Stripe Account Not Configured**
   ```
   [Stripe] ✗ HTTP 400: {"error":"Stripe account not configured"}
   ```
   - **Solution:** Backend Stripe Connect account is not set up or API keys are invalid

## Required Configuration

### In `Secrets.plist`:

```xml
<dict>
    <key>BACKEND_BASE_URL</key>
    <string>https://your-backend-domain.com</string>
</dict>
```

### Backend Endpoints Required:

Your backend must implement these endpoints with proper authentication:

**1. Fetch Account State**
- **Endpoint:** `GET /v1/stripe/account`
- **Returns:** 
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

**2. Create Onboarding Link**
- **Endpoint:** `POST /v1/stripe/account/onboarding_link`
- **Returns:**
  ```json
  {
    "onboarding_url": "https://connect.stripe.com/..."
  }
  ```

**3. Update Payout Schedule**
- **Endpoint:** `PUT /v1/stripe/account/payout_schedule`
- **Body:**
  ```json
  {
    "schedule": "weekly"
  }
  ```

**4. Trigger Instant Payout**
- **Endpoint:** `POST /v1/stripe/account/instant_payout`
- **Body:**
  ```json
  {
    "amount_cents": 100000
  }
  ```

## Step-by-Step Debugging Process

1. **Open Console Filters**
   - Open Xcode Debug Area
   - Type "Stripe" in the filter to isolate logs

2. **Trigger the Action**
   - Try loading the Stripe Payouts screen or clicking buttons

3. **Read the Log Chain**
   - Look for `✓` (success) or `✗` (error) markers
   - Check the request URL is correct
   - Check the HTTP status code

4. **Identify the Problem**
   - If "Missing configuration" → check `Secrets.plist`
   - If "HTTP 401/403" → check authentication/headers
   - If "HTTP 404" → check endpoint implementation on backend
   - If "HTTP 500" → check backend logs
   - If "Decoding error" → check response format matches expected JSON schema

5. **Fix and Test**
   - Make the necessary changes
   - Rebuild and run the app
   - Repeat steps 2-4 to verify the fix

## Example: Successful Account State Load

```
[Stripe] Fetching account state...
[Stripe] Using backend URL: https://api.blueprintcapture.com
[Stripe] Request URL: https://api.blueprintcapture.com/v1/stripe/account
[Stripe] Created GET request to: https://api.blueprintcapture.com/v1/stripe/account
[Stripe] Performing request: GET https://api.blueprintcapture.com/v1/stripe/account
[Stripe] Response status: 200
[Stripe] ✓ Request successful (status 200)
[Stripe] ✓ Account state fetched successfully
[Stripe] Account ready: true, Payouts enabled: true
```

## Example: Failed Onboarding Link Creation

```
[Stripe] Creating onboarding link...
[Stripe] ✗ Missing configuration: No backend URL or fallback onboarding URL
```

**Action:** Set `BACKEND_BASE_URL` in Secrets.plist

## Disabling Logs in Production

When releasing to production, logs automatically won't show in App Store builds. However, if you want to disable them programmatically:

Create a build configuration flag to disable debug logs:

```swift
#if DEBUG
    print("[Stripe] ...")
#endif
```

This is already how logging should work - the `print()` statements won't be visible in production releases.

## Notes

- All timestamps and response bodies are logged to help debug timing issues and unexpected data formats
- Network errors include detailed error descriptions
- HTTP responses show status codes and response bodies (even on errors)
- The logging is comprehensive but shouldn't impact performance
