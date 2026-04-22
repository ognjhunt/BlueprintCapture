# BlueprintCapture Full-App Mockup Prompt Pack
Date: 2026-04-21

Purpose: generate a cohesive first-pass UI/UX mock system for the full BlueprintCapture iOS app using `gpt-image-2`, grounded in the current repo structure and the capture-first doctrine.

## Product Grounding

BlueprintCapture is not a generic gig-work app and not a buyer dashboard.

It is the evidence-capture client for the Blueprint platform:

- it records truthful, site-specific walkthrough evidence
- it preserves raw capture truth, timestamps, motion, poses, depth, and device metadata
- it packages and uploads canonical bundles for downstream world-model packaging and hosted access
- it must keep rights, privacy, provenance, and review states legible without pretending unsupported readiness

The UI should therefore feel:

- exact-site, documentary, and high-trust
- native-mobile and highly intuitive
- minimal, calm, and operational
- visually premium without looking like a startup dashboard

## Real App Surface Inventory

This prompt pack is based on the current live shell and major screens in this repo:

- `BlueprintCaptureApp -> OnboardingFlowView`
- `LaunchCityGateRootView -> LaunchCityGateView`
- `MainTabView`
- `Views/Scan/ScanHomeView.swift`
- `Views/Scan/CaptureSearchSheet.swift`
- `Views/Scan/JobDetailSheet.swift`
- `Views/Scan/AnywhereCaptureFlowView.swift`
- `ProfileReviewView.swift`
- `LocationConfirmationView.swift`
- `PermissionRequestView.swift`
- `CaptureSessionView.swift`
- `Views/Scan/ScanRecordingView.swift`
- `Views/Capture/PostCaptureSummaryView.swift`
- `Views/Wallet/WalletView.swift`
- `Views/Wallet/CaptureDetailView.swift`
- `Views/Wallet/ManagePayoutsView.swift`
- `StripeOnboardingView.swift`
- `Views/Profile/ProfileTabView.swift`
- `SettingsView.swift`
- `EditProfileView.swift`
- `Views/Referral/ReferralDashboardView.swift`

## Global Art Direction

- `Use case`: ui-mockup
- `Asset type`: premium iPhone app mockup board, shown as multiple tall device screens in one composition
- `Primary request`: create a full mobile UI redesign for BlueprintCapture, the app used to discover capture opportunities, record truthful site evidence, manage uploads, and handle contributor earnings and account state
- `Style/medium`: monochrome editorial mobile product design, black/white/grayscale only, native iOS feel with documentary restraint, subtle world-model and route-overlay cues, evidence-first presentation
- `Composition/framing`: 3 to 5 iPhone screens per board, dark app canvas, sharp spacing rhythm, clean tab bars, minimal copy, image-led or camera-led surfaces where relevant
- `Lighting/mood`: cinematic, rigorous, premium, exact-site, operational, trustworthy
- `Color palette`: pure black, white, graphite, charcoal, smoke gray
- `Materials/textures`: glass camera overlays, matte black surfaces, thin divider rules, subtle map grain, archival proof inserts, route traces, capture timelines
- `Constraints`: iPhone-first, minimal text, no fake operational claims, no invented payout readiness, no generic SaaS cards, no bright gradients, no neon AI cliches, no playful fintech look
- `Avoid`: colorful gamification, blue/purple startup gradients, cheerful creator-economy visuals, cartoon robots, cluttered dashboards, fake analytics, dense legal paragraphs

## Shared Visual Rules

- Keep the entire redesign black, white, and grayscale only.
- Preserve a strong sense of documentary realism around sites and capture.
- Use real-space photography, map fragments, route traces, evidence boards, and live camera framing instead of abstract illustrations.
- Let capture, rights, and upload state feel tangible through overlays and proof modules.
- Keep the tab shell minimal and elegant.
- Make critical actions obvious with shape, contrast, and spacing rather than loud color.
- Treat every screen as part of one coherent design system.

## Global Text Tokens

Use only sparse believable text. Favor these exact tokens where needed:

- `Blueprint`
- `Captures`
- `Wallet`
- `Profile`
- `Inspect`
- `Start capture`
- `Upload`
- `Export bundle`
- `Request launch access`
- `Continue`
- `Save for later`
- `Manage payouts`
- `Settings`

## Board 1: Onboarding And Launch Access

### Goal

Show that BlueprintCapture is a high-trust capture client for the broader platform, not a casual camera app.

### Screens to show

- welcome
- auth / create account
- invite code
- permissions
- device capability
- connect glasses
- launch-city gate

### Prompt

Use case: ui-mockup
Asset type: premium iPhone app mockup board
Primary request: Design Board 1 for BlueprintCapture, covering the onboarding and launch-access flow for a truthful evidence-capture app.
Scene/background: dark mobile product board with 4 to 5 tall iPhone screens showing welcome, account creation, permissions, glasses connection, and the launch-city gate.
Subject: a documentary-feeling contributor onboarding flow that explains capture responsibility, exact-location access, and city availability without looking like gig-work gamification.
Style/medium: monochrome editorial iOS design, black/white/grayscale only, sparse typography, calm premium product language, subtle route and evidence cues.
Composition/framing: one board with multiple iPhone screens arranged cleanly; first screen is a strong welcome hero, middle screens show auth and permissions, final screen shows a launch-city gate with supported cities list and one decisive CTA.
Lighting/mood: rigorous, premium, calm, operational.
Text (verbatim): "Blueprint" "Get paid to scan spaces" "Create your account" "Enable Permissions" "Connect Smart Glasses" "Blueprint city launch" "Request launch access" "Continue"
Constraints: make the flow feel serious, simple, and trustworthy; no fintech celebration energy; permissions and city gating must feel clear and credible.
Avoid: bright onboarding gradients, playful illustration characters, generic creator-economy tropes, colorful permission icons.

## Board 2: Capture Discovery Feed

### Goal

Reimagine the main `Captures` tab as the app's operating center for discovery, open capture, search, and job review.

### Screens to show

- scan home
- featured open-to-capture feed
- search sheet
- job detail sheet
- glasses connect sheet

### Prompt

Use case: ui-mockup
Asset type: premium iPhone app mockup board
Primary request: Design Board 2 for BlueprintCapture, covering the main capture discovery feed and opportunity selection flow.
Scene/background: dark mobile board with 4 to 5 iPhone screens showing the captures home feed, search results, a nearby-space search sheet, a rich job detail surface, and a glasses-connect modal.
Subject: exact-site discovery for real spaces, with featured capture opportunities, open-capture entry points, restrained status banners, and a detailed review sheet before recording starts.
Style/medium: monochrome editorial native app design with subtle site photography, route traces, mini maps, rights notes, and high-contrast card hierarchy.
Composition/framing: first screen shows the main `Captures` tab with a premium feed; second shows search; third shows a detail sheet with large site imagery and clear restrictions; fourth shows a minimal glasses-connect flow.
Lighting/mood: operational, premium, cinematic, highly legible.
Text (verbatim): "Captures" "Open to Capture" "Under Review" "Search" "Start capture" "Use iPhone Camera" "Use Glasses" "Smart Glasses"
Constraints: discovery must feel image-led and intuitive, not list-heavy; rights and restrictions must read as operational proof, not generic warning text.
Avoid: marketplace clutter, giant badge forests, colorful maps, generic ride-share UI.

## Board 3: Space Submission Flow

### Goal

Show the manual space-submission path for new or not-yet-approved locations, making it feel disciplined and easy.

### Screens to show

- profile review
- location confirmation
- manual address entry
- permission request
- ready-to-capture preflight

### Prompt

Use case: ui-mockup
Asset type: premium iPhone app mockup board
Primary request: Design Board 3 for BlueprintCapture, covering the space-submission and pre-capture review flow used before a manual site submission is recorded.
Scene/background: dark mobile board with 4 to 5 iPhone screens showing profile confirmation, exact address selection, context notes, sensor permissions, and a capture preflight state.
Subject: an exact-site submission flow that feels careful, native, and grounded in rights-safe capture rather than casual posting.
Style/medium: monochrome editorial iOS design, quiet but premium, with subtle map fragments, typed form blocks, route hints, and evidence-style instructional overlays.
Composition/framing: sequential flow across several device screens; one screen should emphasize address confirmation, one should show context and guardrails, one should show permissions, and one should show a preflight state before live capture begins.
Lighting/mood: calm, careful, high-trust, exacting.
Text (verbatim): "Before you capture" "Submit a Space" "Confirm Location" "Enable Capture Access" "Continue" "Allow Access & Continue"
Constraints: keep forms minimal and beautifully structured; this should feel faster and clearer than the current app while staying rigorous.
Avoid: crowded forms, bright CTA colors, social-posting patterns, generic productivity UI.

## Board 4: Live Capture And Post-Capture Review

### Goal

Make the core capture experience feel like Blueprint's most distinctive surface: documentary, precise, and world-model aware.

### Screens to show

- live camera capture
- live guidance / pass briefing
- anchor tools / quality overlay
- recording state
- post-capture summary

### Prompt

Use case: ui-mockup
Asset type: premium iPhone app mockup board
Primary request: Design Board 4 for BlueprintCapture, covering the live capture experience and the immediate post-capture summary.
Scene/background: dark mobile board with 4 to 5 iPhone screens; some screens show a live exact-site camera preview, others show capture overlays, route traces, semantic anchor tools, and the post-capture review summary.
Subject: truthful site capture for downstream world-model packaging, with visible quality signals, pass guidance, upload state, and export options.
Style/medium: monochrome cinematic camera UI, black/white/grayscale only, documentary feel, subtle AR or route overlays, precise native control surfaces.
Composition/framing: at least two screens should be full-camera dominant; another should show recording guidance and anchor chips; the last should show a premium post-capture summary with duration, notes, workflow progress, upload, export, and save-later actions.
Lighting/mood: exact-site, immersive, disciplined, premium.
Text (verbatim): "Start capture" "Recording" "Upload" "Export bundle" "Save for later" "Capture complete"
Constraints: this board should feel like the heart of the product; the UI must communicate real capture truth, not simulated AI magic.
Avoid: sci-fi holograms, colorful scanning effects, game HUD clutter, fake 3D maps.

## Board 5: Wallet And Payout Operations

### Goal

Rework earnings and payout surfaces so they feel trustworthy, quiet, and easy to parse, while staying subordinate to the capture product.

### Screens to show

- wallet overview
- ledger tabs
- capture detail / submission detail
- manage payouts
- Stripe onboarding / identity verification

### Prompt

Use case: ui-mockup
Asset type: premium iPhone app mockup board
Primary request: Design Board 5 for BlueprintCapture, covering the wallet, payout, and capture-detail operations flow.
Scene/background: dark mobile board with 4 to 5 iPhone screens showing wallet overview, payout status, submission detail, payout method management, and identity verification.
Subject: a premium contributor-wallet experience that clearly separates approved earnings, review-held captures, payout readiness, and payout setup without looking like a finance startup.
Style/medium: monochrome editorial mobile design with documentary restraint, elegant ledger modules, quiet status pills, and sparse information density.
Composition/framing: first screen shows a strong wallet summary; second shows payout and history tabs; third shows a capture detail surface with review/timeline modules; fourth and fifth show payout setup and verification.
Lighting/mood: trustworthy, calm, mature, legible.
Text (verbatim): "Wallet" "Payouts" "Cashouts" "History" "Submission" "Manage Payouts" "Payouts" "Start Verification"
Constraints: no colorful finance visuals, no faux trading app patterns, no celebratory confetti; make payout states concrete and conservative.
Avoid: glossy fintech cards, bright green growth motifs, big charts, generic bank-app look.

## Board 6: Profile, Settings, And Referral Control Center

### Goal

Unify personal profile, contributor stats, settings, and referrals into a calm control center that still feels part of the same capture-first product.

### Screens to show

- profile tab
- contributor stats / progress
- settings
- edit profile
- referral dashboard

### Prompt

Use case: ui-mockup
Asset type: premium iPhone app mockup board
Primary request: Design Board 6 for BlueprintCapture, covering the profile, settings, and referral-control surfaces.
Scene/background: dark mobile board with 4 to 5 iPhone screens showing the profile tab, contributor statistics, settings, edit profile, and referral dashboard.
Subject: a contributor control center that feels premium and disciplined, with account state, capture progress, notification controls, payout links, and referral tracking.
Style/medium: monochrome editorial iOS design, restrained, clean, minimal, quietly luxurious.
Composition/framing: a board of multiple device screens; one should show the profile overview, one should show settings with grouped controls, one should show an edit profile form, and one should show a refined referral dashboard.
Lighting/mood: calm, sharp, utility-first, premium.
Text (verbatim): "Profile" "My Account" "Settings" "Edit Profile" "Affiliate Center" "Share & Earn 10%" "Manage your account and preferences"
Constraints: settings should look clear and modern rather than default-iOS-generic; referral should feel like a secondary utility, not the product story.
Avoid: gamified badges everywhere, colorful growth hacks, creator-influencer aesthetics, cluttered form styling.

## Direction Summary

The visual direction for all boards is:

- monochrome documentary iOS
- exact-site and evidence-first
- minimal but not sterile
- camera, map, route, and proof modules instead of dashboard chrome
- native-feeling interaction patterns with editorial restraint

If a later implementation phase needs desktop handoff boards, Android adaptations, or component-level prompt breakdowns, derive them from these six board prompts rather than starting over.
