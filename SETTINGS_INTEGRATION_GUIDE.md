# Settings Tab & Bank Connection Integration Guide

## Overview

The Settings tab provides comprehensive user account management with integrated bank connection functionality using Plaid and Stripe. The implementation uses a mock API service that can be easily swapped for real backend services.

## Features Implemented

### 1. **User Profile Management**
- View user information (name, email, phone, company)
- Edit profile with validation
- Async profile updates

### 2. **Earnings Dashboard**
- Total earned amount display
- Pending payout tracking
- Number of scans completed

### 3. **Bank Connection (Plaid + Stripe)**
- Secure bank account connection via Plaid Link
- Stripe Connect integration for payouts
- Display connected bank information
- Change or disconnect bank account
- Error handling and loading states

### 4. **Account Settings**
- Edit profile
- Privacy & Security placeholder
- Sign out functionality

## Architecture

### Components

#### `SettingsViewModel.swift`
Main state management class with:
- `@Published` properties for reactive updates
- Error handling with `SettingsError` enum
- Async functions for all operations
- Integration with `APIService` for backend calls

#### `APIService.swift` (in SettingsViewModel)
Mock implementation of all backend calls:
- `fetchUserProfile()` - Get user data
- `updateUserProfile()` - Save profile changes
- `fetchEarnings()` - Get earnings data
- `fetchBillingInfo()` - Get connected bank info
- `exchangePlaidToken()` - Exchange Plaid public token
- `createStripeAccount()` - Create Stripe account
- `disconnectBankAccount()` - Remove bank connection

#### `SettingsView.swift`
Main UI view displaying:
- Profile card with user info
- Earnings section
- Billing information section
- Account settings section
- Loading and error states

#### `EditProfileView.swift`
Form for editing profile:
- Full name, email, phone, company
- Input validation
- Save/cancel actions

#### `StripeBillingSetupView.swift`
Bank connection setup flow:
- Feature highlights
- Plaid Link simulation (shows bank picker)
- Links to Plaid/Stripe terms

#### `PlaidLinkSimulationView.swift`
Simulates Plaid Link interface:
- Bank selection picker
- Account detail display
- Confirmation flow

## Integration with Real Services

### Plaid Integration

1. **Install Plaid SDK:**
   ```bash
   # Add to your Podfile
   pod 'Plaid'
   ```

2. **Update `StripeBillingSetupView.swift`:**
   ```swift
   import PlaidLink
   
   // Replace PlaidLinkSimulationView with real Plaid Link
   func openPlaidLink() {
       let configuration = PLKConfiguration(
           clientName: "Blueprint Capture",
           environment: .sandbox, // Use .production in production
           products: [.auth],
           publicKey: "YOUR_PLAID_PUBLIC_KEY"
       )
       
       PLKPlaidLinkViewController.create(configuration: configuration) { publicToken, metadata in
           if let publicToken = publicToken {
               Task {
                   await viewModel.connectPlaidBank(
                       publicToken: publicToken,
                       accountId: metadata?.accounts.first?.id ?? "",
                       bankName: metadata?.institution?.name ?? ""
                   )
               }
           }
       }.present(from: self)
   }
   ```

### Backend API Integration

1. **Update `APIService` in `SettingsViewModel.swift`:**

   ```swift
   class APIService {
       let baseURL = "https://your-api.com"
       
       func fetchUserProfile() async throws -> UserProfile {
           let url = URL(string: "\(baseURL)/api/user/profile")!
           let (data, _) = try await URLSession.shared.data(from: url)
           return try JSONDecoder().decode(UserProfile.self, from: data)
       }
       
       func updateUserProfile(_ profile: UserProfile) async throws -> UserProfile {
           var request = URLRequest(url: URL(string: "\(baseURL)/api/user/profile")!)
           request.httpMethod = "PUT"
           request.setValue("application/json", forHTTPHeaderField: "Content-Type")
           request.httpBody = try JSONEncoder().encode(profile)
           
           let (data, _) = try await URLSession.shared.data(for: request)
           return try JSONDecoder().decode(UserProfile.self, from: data)
       }
       
       func exchangePlaidToken(_ publicToken: String) async throws -> String {
           var request = URLRequest(url: URL(string: "\(baseURL)/api/plaid/exchange-token")!)
           request.httpMethod = "POST"
           request.setValue("application/json", forHTTPHeaderField: "Content-Type")
           
           let payload = ["public_token": publicToken]
           request.httpBody = try JSONEncoder().encode(payload)
           
           let (data, _) = try await URLSession.shared.data(for: request)
           let response = try JSONDecoder().decode(["access_token": String].self, from: data)
           return response["access_token"] ?? ""
       }
       
       func createStripeAccount(accessToken: String, accountId: String, bankName: String) async throws -> BillingInfo {
           var request = URLRequest(url: URL(string: "\(baseURL)/api/stripe/create-account")!)
           request.httpMethod = "POST"
           request.setValue("application/json", forHTTPHeaderField: "Content-Type")
           
           let payload = [
               "plaid_access_token": accessToken,
               "account_id": accountId,
               "bank_name": bankName
           ] as [String : Any]
           request.httpBody = try JSONSerialization.data(withJSONObject: payload)
           
           let (data, _) = try await URLSession.shared.data(for: request)
           return try JSONDecoder().decode(BillingInfo.self, from: data)
       }
   }
   ```

2. **Backend Endpoints Required:**
   - `GET /api/user/profile` - Get user profile
   - `PUT /api/user/profile` - Update user profile
   - `GET /api/earnings` - Get earnings data
   - `GET /api/billing/info` - Get billing info
   - `POST /api/plaid/exchange-token` - Exchange Plaid token for access token
   - `POST /api/stripe/create-account` - Create Stripe Connect account
   - `DELETE /api/billing/account` - Disconnect bank account

### Stripe Connect Setup

1. **Create a Stripe Connect account** at https://connect.stripe.com

2. **Backend should:**
   - Exchange Plaid access token for bank account details
   - Create a Stripe Connect account with the user's information
   - Link the Plaid bank account to the Stripe account
   - Store the Stripe account ID for future payouts

3. **Backend code example (Node.js):**
   ```javascript
   const plaid = require('plaid');
   const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
   
   app.post('/api/plaid/exchange-token', async (req, res) => {
       const { public_token } = req.body;
       
       try {
           // Exchange public token for access token
           const tokenResponse = await plaidClient.itemPublicTokenExchange({
               public_token
           });
           
           const accessToken = tokenResponse.access_token;
           res.json({ access_token: accessToken });
       } catch (error) {
           res.status(500).json({ error: error.message });
       }
   });
   
   app.post('/api/stripe/create-account', async (req, res) => {
       const { plaid_access_token, account_id, bank_name, user_id } = req.body;
       
       try {
           // Get bank account details from Plaid
           const authResponse = await plaidClient.authGet({
               access_token: plaid_access_token
           });
           
           const account = authResponse.numbers.ach.find(a => a.account_id === account_id);
           
           // Create Stripe Connect account
           const stripeAccount = await stripe.accounts.create({
               country: 'US',
               type: 'express',
               email: userEmail,
               business_type: 'individual',
               individual: {
                   address: {
                       country: 'US',
                       state: userState,
                       postal_code: userZip,
                       line1: userAddress
                   },
                   dob: {
                       day: dobDay,
                       month: dobMonth,
                       year: dobYear
                   },
                   email: userEmail,
                   first_name: firstName,
                   last_name: lastName,
                   phone: userPhone,
                   ssn_last_4: ssnLast4
               }
           });
           
           // Create bank account token
           const token = await stripe.tokens.create({
               bank_account: {
                   country: 'US',
                   currency: 'usd',
                   account_holder_name: account.name,
                   account_holder_type: 'individual',
                   routing_number: account.routing,
                   account_number: account.account
               }
           });
           
           // Add bank account to Connect account
           await stripe.accounts.createExternalAccount(
               stripeAccount.id,
               { external_account: token.id }
           );
           
           // Save to database
           await User.updateOne(
               { _id: user_id },
               {
                   stripe_account_id: stripeAccount.id,
                   plaid_access_token: plaid_access_token,
                   bank_name: bank_name
               }
           );
           
           res.json({
               bankName: bank_name,
               lastFour: account.account.slice(-4),
               accountHolderName: account.name,
               stripeAccountId: stripeAccount.id
           });
       } catch (error) {
           res.status(500).json({ error: error.message });
       }
   });
   ```

## Testing

### Mock Mode (Current)
The app works completely with mock data. You can:
- Edit profile information
- See sample earnings
- Simulate bank connections with the bank picker
- Test the entire flow without a backend

### Testing with Real Services

1. Set up Plaid sandbox account
2. Create Stripe test account
3. Update `APIService` with real backend URLs
4. Test on physical device or simulator

## Error Handling

The app includes comprehensive error handling:
- Network errors with user-friendly messages
- Invalid data validation
- Bank connection failures with retry options
- Loading states during async operations
- Alert dialogs for user feedback

## Next Steps

1. **Connect to real backend:**
   - Update `APIService` URLs
   - Implement authentication/tokens
   - Add proper error handling

2. **Integrate Plaid SDK:**
   - Install Plaid framework
   - Replace `PlaidLinkSimulationView` with real Plaid Link
   - Test with different banks

3. **Set up Stripe Connect:**
   - Create Stripe Connect account
   - Implement bank account verification
   - Set up payout schedules

4. **Add additional features:**
   - Transaction history
   - Payout history and status
   - Payment method management
   - Two-factor authentication
   - Recurring payouts configuration

## Security Considerations

- Never store full bank account numbers
- Use Plaid's secure token exchange
- Implement proper authentication on backend
- Use HTTPS for all API calls
- Store sensitive data in Keychain
- Implement proper error messages (don't expose sensitive data)

## References

- [Plaid Link Integration](https://plaid.com/docs/link/)
- [Stripe Connect Documentation](https://stripe.com/docs/connect)
- [Swift async/await guide](https://developer.apple.com/documentation/swift/concurrency)
