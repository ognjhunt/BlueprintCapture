# Stripe Quick Setup - Blueprint (Replit Backend)

## ⚡ TL;DR - Get Running in 5 Minutes

### Step 1: Update Secrets.plist
Add this ONE line to `BlueprintCapture/Support/Secrets.plist`:

```xml
<key>BACKEND_BASE_URL</key>
<string>https://www.tryblueprint.io</string>
```

### Step 2: Build and Run
```bash
⌘B  (Build)
⌘R  (Run)
```

### Step 3: Debug
1. Open console: `⌘⇧Y`
2. Type "Stripe" in filter
3. Open Stripe Payouts screen
4. Check console for logs

### Step 4: Check for Success
You should see:
```
[Stripe] ✓ Account state fetched successfully
```

If you see an error, jump to the "Error Guide" section below.

---

## Your Backend Endpoints

All endpoints are on your Replit backend:

```
Base URL: https://www.tryblueprint.io

GET  /v1/stripe/account
POST /v1/stripe/account/onboarding_link
PUT  /v1/stripe/account/payout_schedule
POST /v1/stripe/account/instant_payout
```

---

## Error Guide

### ❌ "Missing backend URL configuration"
```
Fix: Make sure you added BACKEND_BASE_URL to Secrets.plist
Location: BlueprintCapture/Support/Secrets.plist
Value: https://www.tryblueprint.io
```

### ❌ "HTTP 404: Not Found"
```
Problem: Backend endpoint doesn't exist
Check: 
  1. Is backend running?
  2. Are endpoints at /v1/stripe/account, etc.?
  3. Verify backend URL is correct
```

### ❌ "HTTP 401: Unauthorized"
```
Problem: Stripe API keys not configured
Check:
  1. STRIPE_SECRET_KEY set on backend?
  2. STRIPE_CONNECT_ACCOUNT_ID set?
  3. Using test keys (pk_test_)?
```

### ❌ "Network error: Connection refused"
```
Problem: Can't reach backend
Fix:
  1. Check backend is running
  2. Test in terminal:
     curl https://www.tryblueprint.io/v1/stripe/account
```

### ❌ "Decoding error" + Response body shown
```
Problem: Backend returning wrong format
Check: Response has all these fields:
  - onboarding_complete
  - payouts_enabled
  - payout_schedule
  - instant_payout_eligible
  - next_payout (or null)
  - requirements_due (or null)
```

---

## Testing

### Test 1: Backend Reachable?
```bash
curl -i https://www.tryblueprint.io/v1/stripe/account
```

Should return status (200, 401, or 500) - NOT 404 or timeout.

### Test 2: App Working?
1. Build and run app
2. Open Stripe Payouts screen
3. Check console (⌘⇧Y) for logs
4. Look for `✓` success markers

---

## Secrets.plist Example

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>BACKEND_BASE_URL</key>
    <string>https://www.tryblueprint.io</string>
    
    <key>STRIPE_PUBLISHABLE_KEY</key>
    <string>pk_test_...</string>
    
    <key>STRIPE_ACCOUNT_ID</key>
    <string>acct_...</string>
    
    <!-- Other existing keys -->
    <key>GOOGLE_PLACES_API_KEY</key>
    <string>...</string>
</dict>
</plist>
```

---

## Console Log Examples

### ✅ Success
```
[Stripe] Fetching account state...
[Stripe] Using backend URL: https://www.tryblueprint.io
[Stripe] Request URL: https://www.tryblueprint.io/v1/stripe/account
[Stripe] Response status: 200
[Stripe] ✓ Account state fetched successfully
[Stripe] Account ready: true, Payouts enabled: true
```

### ❌ Missing Config
```
[Stripe] Fetching account state...
[Stripe] ✗ Missing backend URL configuration
```

### ❌ HTTP Error
```
[Stripe] Response status: 401
[Stripe] ✗ HTTP 401: {"error":"Invalid API key"}
```

---

## Files to Reference

- **All docs?** → `STRIPE_DOCUMENTATION_INDEX.md`
- **Specific error?** → `STRIPE_ERROR_REFERENCE.txt` (keep open!)
- **Detailed setup?** → `STRIPE_BACKEND_CONFIG.md`
- **Architecture?** → `STRIPE_FLOW_DIAGRAM.md`

---

## Next Steps

1. Add BACKEND_BASE_URL to Secrets.plist
2. Build and run the app
3. Open Stripe Payouts screen
4. Check console for success (✓) or error (✗)
5. Use error guide above if needed

That's it! Your Stripe integration is now ready to debug.
