# Stripe Configuration Checklist

Use this checklist to verify your Stripe integration is properly configured on both client and backend.

## ✅ Client Configuration (iOS App)

### 1. Secrets.plist Configuration

Open `BlueprintCapture/Support/Secrets.plist` and verify these keys exist:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Backend Configuration - REQUIRED -->
    <key>BACKEND_BASE_URL</key>
    <string>https://your-backend-domain.com</string>
    
    <!-- Stripe Configuration - REQUIRED -->
    <key>STRIPE_PUBLISHABLE_KEY</key>
    <string>pk_test_...</string>
    
    <key>STRIPE_ACCOUNT_ID</key>
    <string>acct_...</string>
    
    <!-- Fallback URLs (use if not using backend) -->
    <key>STRIPE_ONBOARDING_URL</key>
    <string>https://connect.stripe.com/...</string>
    
    <key>STRIPE_PAYOUT_SCHEDULE_URL</key>
    <string>https://your-backend.com/stripe/payout-schedule</string>
    
    <key>STRIPE_INSTANT_PAYOUT_URL</key>
    <string>https://your-backend.com/stripe/instant-payout</string>
    
    <!-- Other Keys -->
    <key>GOOGLE_PLACES_API_KEY</key>
    <string>AIza...</string>
    
    <key>STREET_VIEW_API_KEY</key>
    <string>AIza...</string>
    
    <key>GEMINI_API_KEY</key>
    <string>AIza...</string>
    
</dict>
</plist>
```

**Verification:**
- [ ] `BACKEND_BASE_URL` is set and points to a running backend
- [ ] `STRIPE_PUBLISHABLE_KEY` starts with `pk_test_` (testing) or `pk_live_` (production)
- [ ] `STRIPE_ACCOUNT_ID` starts with `acct_`
- [ ] At least one of `BACKEND_BASE_URL` OR fallback URLs are set

### 2. Code Files Verify

**Check these files were modified with logging:**

```bash
# Should contain [Stripe] and [StripeUI] logging
grep -r "\[Stripe\]" BlueprintCapture/
```

- [ ] `StripeConnectService.swift` has `print("[Stripe]` calls
- [ ] `StripeOnboardingView.swift` has `print("[StripeUI]` calls

## ✅ Backend Configuration

### 1. Required Environment Variables

Your backend must have these variables set:

```bash
# Stripe Configuration
STRIPE_SECRET_KEY=sk_test_...  # or sk_live_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_CONNECT_ACCOUNT_ID=acct_...

# Optional: For restricted API keys (recommended for security)
STRIPE_RESTRICTED_KEY=rk_test_...

# API Configuration
BACKEND_BASE_URL=https://your-backend.com
ALLOWED_ORIGINS=https://your-app-domain.com
```

**Verification:**
- [ ] `STRIPE_SECRET_KEY` is set in backend environment
- [ ] `STRIPE_CONNECT_ACCOUNT_ID` matches the account you want to use
- [ ] Backend is running on `BACKEND_BASE_URL`

### 2. Required API Endpoints

Your backend must implement these endpoints with proper error handling:

#### **GET /v1/stripe/account**
```swift
// Request Headers:
GET /v1/stripe/account HTTP/1.1
Accept: application/json
Content-Type: application/json

// Expected Response (200 OK):
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

// Error Response Example (401 Unauthorized):
HTTP/1.1 401 Unauthorized
{
  "error": "Invalid API key or account"
}
```

**Implementation Guide:**
- Use Stripe API: `GET /v1/accounts/{account_id}` to fetch account details
- Extract `charges_enabled` → `payouts_enabled`
- Extract `requirements.currently_due` → `requirements_due`
- Transform Stripe response to match `StripeAccountState` schema

**Verification:**
- [ ] Endpoint returns 200 with correct JSON structure
- [ ] Returns 401/403 if user is not authenticated
- [ ] All required fields are present

#### **POST /v1/stripe/account/onboarding_link**
```swift
// Request Headers:
POST /v1/stripe/account/onboarding_link HTTP/1.1
Accept: application/json
Content-Type: application/json
Body: {}

// Expected Response (200 OK):
{
  "onboarding_url": "https://connect.stripe.com/oauth/authorize?..."
}

// Error Response Example (400 Bad Request):
HTTP/1.1 400 Bad Request
{
  "error": "Stripe account not configured"
}
```

**Implementation Guide:**
- Use Stripe API: `POST /v1/account_links` with `account={account_id}`, `type=account_onboarding`
- Return the generated URL as `onboarding_url`
- Include refresh and return URLs if needed

**Verification:**
- [ ] Endpoint returns 200 with onboarding URL
- [ ] URL starts with `https://connect.stripe.com/`
- [ ] Returns 400 if Stripe account not configured

#### **PUT /v1/stripe/account/payout_schedule**
```swift
// Request Headers:
PUT /v1/stripe/account/payout_schedule HTTP/1.1
Accept: application/json
Content-Type: application/json

// Request Body:
{
  "schedule": "weekly"
}

// Expected Response (200 OK):
{}

// Valid schedule values: "daily", "weekly", "monthly", "manual"
```

**Implementation Guide:**
- Use Stripe API: `POST /v1/accounts/{account_id}` with `settings[payouts][schedule]`
- Validate `schedule` value is one of: daily, weekly, monthly, manual
- Return empty object {} on success

**Verification:**
- [ ] Endpoint returns 200 on success
- [ ] Returns 400 if invalid schedule value
- [ ] Stripe account is updated with new schedule

#### **POST /v1/stripe/account/instant_payout**
```swift
// Request Headers:
POST /v1/stripe/account/instant_payout HTTP/1.1
Accept: application/json
Content-Type: application/json

// Request Body:
{
  "amount_cents": 100000
}

// Expected Response (200 OK):
{}

// Error Response Example (400 Bad Request):
HTTP/1.1 400 Bad Request
{
  "error": "Insufficient funds"
}
```

**Implementation Guide:**
- Use Stripe Payouts API: `POST /v1/payouts` with the Connect account
- Set `amount` in cents
- Return empty object {} on success
- Return 400 with error message if insufficient funds

**Verification:**
- [ ] Endpoint returns 200 on success
- [ ] Returns 400 with reason if payout fails
- [ ] Payout is created in Stripe Dashboard

### 3. Backend Security

Recommended security practices:

```javascript
// Middleware for authentication
const authMiddleware = async (req, res, next) => {
  const userId = req.user.id; // From auth token
  if (!userId) return res.status(401).json({ error: "Unauthorized" });
  next();
};

// Middleware for Stripe account validation
const stripeAccountMiddleware = async (req, res, next) => {
  const stripeAccountId = process.env.STRIPE_CONNECT_ACCOUNT_ID;
  if (!stripeAccountId) return res.status(500).json({ error: "Misconfigured" });
  req.stripeAccountId = stripeAccountId;
  next();
};
```

**Verification:**
- [ ] All Stripe endpoints require authentication
- [ ] All requests validate user permissions
- [ ] Error messages don't leak sensitive info

## ✅ Testing Checklist

### 1. Local Testing

```bash
# Start your backend
npm start  # or python manage.py runserver, etc.

# Verify backend is running
curl https://your-backend.com/v1/stripe/account

# Should return something (likely 401 if no auth, not 404)
```

**Verification:**
- [ ] Backend API responds (not 404 or timeout)
- [ ] Returns proper error for missing auth (401)
- [ ] No CORS errors

### 2. Xcode Console Testing

1. Run the app in Xcode
2. Open Debug Area: ⌘⇧Y
3. In Xcode console, type: `Stripe` to filter logs
4. Tap "Manage Payouts & Onboarding" or open Settings → Stripe section
5. Watch console for logs

**Expected Logs:**
```
[Stripe] Fetching account state...
[Stripe] Using backend URL: https://your-backend.com
[Stripe] Request URL: https://your-backend.com/v1/stripe/account
[Stripe] Created GET request to: ...
[Stripe] Performing request: GET ...
[Stripe] Response status: 200
[Stripe] ✓ Request successful (status 200)
[Stripe] ✓ Account state fetched successfully
[Stripe] Account ready: true, Payouts enabled: true
```

**Verification:**
- [ ] No "Missing configuration" errors
- [ ] No "HTTP 4xx/5xx" errors
- [ ] Response status is 200
- [ ] Account state shows correct values

### 3. Common Test Scenarios

| Scenario | Expected Console Output | Action |
|----------|------------------------|--------|
| **Happy Path** | `✓ Account state fetched successfully` | Verify all data displays correctly |
| **Missing Backend URL** | `✗ Missing backend URL configuration` | Add `BACKEND_BASE_URL` to Secrets.plist |
| **Backend Offline** | `✗ Network error: Connection refused` | Start backend server |
| **Wrong Endpoint** | `✗ HTTP 404: Not Found` | Verify endpoint path on backend |
| **Unauthorized** | `✗ HTTP 401: Invalid API key` | Check Stripe API keys on backend |
| **Bad Response Format** | `✗ Decoding error: ...` + response body | Check backend returns correct JSON schema |

## 🔍 Debugging Commands

### View all Stripe logs:
```bash
# In Xcode console, filter by typing:
Stripe
```

### Check if backend is running:
```bash
curl -i https://your-backend.com/v1/stripe/account
```

### Check environment variables on backend:
```bash
# SSH into backend and verify:
echo $STRIPE_SECRET_KEY
echo $STRIPE_CONNECT_ACCOUNT_ID
echo $BACKEND_BASE_URL
```

### Test Stripe API directly (if you have backend shell access):
```bash
curl -i https://api.stripe.com/v1/accounts/acct_... \
  -u sk_test_...:
```

## ✅ Final Verification Checklist

Before testing in production, verify:

- [ ] All `Secrets.plist` keys are set
- [ ] Backend URL is reachable and running
- [ ] All 4 Stripe endpoints are implemented on backend
- [ ] Stripe API keys are correct (not expired, right environment)
- [ ] Console logs show successful calls (✓ markers)
- [ ] App can display account state without errors
- [ ] "Open Stripe Onboarding" button works
- [ ] Payout schedule can be updated
- [ ] Instant payout works (or shows proper error if not eligible)

## Common Issues Summary

| Issue | Solution |
|-------|----------|
| "Unable to load Stripe account status" | Set `BACKEND_BASE_URL` in Secrets.plist |
| "Failed to open onboarding" | Implement `/v1/stripe/account/onboarding_link` endpoint |
| HTTP 401 errors | Verify Stripe API keys on backend |
| Decoding errors | Check JSON response schema matches expected format |
| Network timeouts | Verify backend URL is correct and backend is running |
| CORS errors | Add frontend domain to backend CORS allowed origins |

## Support

For more details:
- See `STRIPE_DEBUGGING_GUIDE.md` for troubleshooting
- See `STRIPE_DEBUG_QUICK_START.md` for quick reference
