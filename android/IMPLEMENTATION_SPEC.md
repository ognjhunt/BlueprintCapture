# Android Feature Parity: Implementation Spec
*Three remaining gaps to iOS parity — prioritised by implementation effort*

---

## Gap 1 — Contributor Profile: Remove DemoData Fallbacks
**Effort: Small (~1 hour) · Risk: Low · File: `ContributorProfileRepository.kt`**

### What's wrong

`observeProfile()` returns fake data in two situations:

```kotlin
// BUG 1: On Firestore error → full fake profile shown as if real
if (error != null) {
    trySend(DemoData.contributorProfile.copy(uid = uid))  // ← wrong
    return@addSnapshotListener
}

// BUG 2: Document doesn't exist yet → fake profile instead of null
val profile = snapshot?.toContributorProfile(uid)
    ?: DemoData.contributorProfile.copy(uid = uid)        // ← wrong
trySend(profile)

// BUG 3: Individual missing fields silently replaced with demo values
name = data["name"] as? String ?: DemoData.contributorProfile.name   // ← wrong
email = data["email"] as? String ?: DemoData.contributorProfile.email // ← wrong
```

This means a user who never saved a name would see "Alex Rivera" instead of a blank,
and a Firestore outage would surface convincing-looking fake data as real.

### What to change

**`ContributorProfileRepository.kt` — `observeProfile()`:**

| Location | Current | Change to |
|---|---|---|
| `if (error != null)` branch | `trySend(DemoData....)` | `trySend(null)` |
| Null fallback after `toContributorProfile` | `?: DemoData.contributorProfile.copy(uid)` | `?: null` — emit null for "document not yet created" |
| `toContributorProfile` — `name` field | `?: DemoData.contributorProfile.name` | `?: ""` |
| `toContributorProfile` — `email` field | `?: DemoData.contributorProfile.email` | `?: ""` |

**After the change** the flow contract is:
- `null` = not authenticated / Firestore error / document not yet bootstrapped
- Real `ContributorProfile` with empty-string fields = authenticated but profile data missing

No UI changes are needed — `WalletViewModel` and `ScanViewModel` already null-check the profile via
`.orEmpty()` / `?.let { }`.

### Acceptance test
1. Sign in with a brand-new account (no prior Firestore `users` doc).
2. Wallet screen should show `$0.00` and zero captures — not "Alex Rivera's" balances.
3. Kill network. Pull-to-refresh. Balance card should stay at last-known value (Firestore offline
   cache) — not silently switch to demo values.

---

## Gap 2 — Wallet Ledger Tabs: Real Data
**Effort: Medium (~4-6 hours) · Risk: Low · Files: `WalletScreen.kt`, `WalletViewModel.kt`, `CaptureHistoryRepository.kt`**

### What's wrong

The three ledger tabs — **Payouts**, **Cashouts**, **History** — are permanently hardcoded empty:

```kotlin
// WalletScreen.kt — WalletLedgerContent()
val (title, subtitle) = when (selectedTab) {
    WalletLedgerTab.Payouts  -> "No payouts yet"  to "Approved captures will appear here."
    WalletLedgerTab.Cashouts -> "No cashouts yet" to "Cashouts will appear here once processed."
    WalletLedgerTab.History  -> "No history yet"  to "Wallet activity will appear here."
}
// Always shows the empty-state box regardless of actual data
```

Additionally, `WalletViewModel.refresh()` does `delay(900)` and nothing else. The balance stats
(`totalEarnings`, `availableBalance`, etc.) are already live from Firestore via `observeProfile()` —
the fake refresh is pointless noise but doesn't break anything.

### Data sources

`CaptureHistoryRepository` (already implemented) queries `capture_submissions` ordered by
`submitted_at DESC`. Its `CaptureHistoryEntry` has:

```kotlin
data class CaptureHistoryEntry(
    val id: String,
    val jobTitle: String,
    val submittedAt: Date?,
    val payoutCents: Int,
    val stage: CaptureSubmissionStage,   // InReview | NeedsRecapture | Paid
    val jobId: String?,
)
```

This is sufficient to drive all three tabs:
- **History** tab → all entries, sorted by `submittedAt DESC`
- **Payouts** tab → entries where `stage == Paid`
- **Cashouts** tab → requires a separate `payouts` or `cashout_requests` Firestore collection
  (iOS reads from a `payouts` subcollection under `users/{uid}/payouts`). If this collection doesn't
  exist in the current Firestore schema, show an empty state with accurate copy ("No cashouts yet").

### Implementation plan

#### Step 1 — Expose history in `WalletViewModel`

Add `CaptureHistoryRepository` injection and a `_history` StateFlow:

```kotlin
// In WalletViewModel
private val _history = MutableStateFlow<List<CaptureHistoryEntry>>(emptyList())
private val _historyLoading = MutableStateFlow(false)
```

Combine into `WalletUiState`:
```kotlin
data class WalletUiState(
    // ... existing fields ...
    val payoutEntries: List<CaptureHistoryEntry> = emptyList(),  // stage == Paid
    val historyEntries: List<CaptureHistoryEntry> = emptyList(), // all entries
    val isLedgerLoading: Boolean = false,
)
```

Load on init and on `refresh()`:
```kotlin
fun refresh() {
    if (isRefreshing.value) return
    viewModelScope.launch {
        isRefreshing.value = true
        _historyLoading.value = true
        val entries = historyRepository.fetchHistory()
        _history.value = entries
        _historyLoading.value = false
        isRefreshing.value = false
    }
}
```

Replace the fake `delay(900)` with this real call. The Firestore profile listener already
auto-updates the balance card, so no additional fetch is needed for stats.

#### Step 2 — Replace `WalletLedgerContent` with real rows

```
WalletLedgerContent(
    selectedTab,
    payoutEntries  = state.payoutEntries,
    historyEntries = state.historyEntries,
    isLoading      = state.isLedgerLoading,
)
```

Each row should show:
- Job title
- Submitted date (formatted, e.g. "Mar 18")
- Payout amount in dollars
- Stage badge: teal chip for "Paid", muted for "In Review", amber for "Needs Recapture"

Loading state: show `CircularProgressIndicator` centred while `isLedgerLoading == true`.

Empty state (keep existing empty-state composable, just conditionally shown).

#### Step 3 — Cashouts tab

Check if your Firestore schema has a `users/{uid}/payouts` or `cashout_requests` collection.
- **If yes**: add `fetchCashouts()` to `CaptureHistoryRepository` querying that collection.
- **If no**: leave the tab as an empty state with copy "No cashouts yet — cashouts processed through
  your connected payout method will appear here." (already accurate).

### Acceptance test
1. Submit 2+ captures. Approve one in the admin console (set `status = "paid"`).
2. Open Wallet → History tab: both captures visible.
3. Open Payouts tab: only the approved/paid one visible.
4. Tap refresh — spinner appears, data reloads from Firestore, spinner stops.
5. New account with no submissions: all tabs show empty states with correct copy.

---

## Gap 3 — Meta Glasses Capture Pipeline (MWDAT SDK)
**Effort: Large (~2-3 days) · Risk: High (SDK availability unknown) · Files: `GlassesViewModel.kt`, new `GlassesCaptureManager.kt`, `CaptureSessionViewModel.kt`**

### What's wrong

`connect()` fakes a connection with `delay(1500)`. There is no capture lifecycle at all — no
`startCapture()`, no `stopCapture()`, no artifact handoff to the upload pipeline:

```kotlin
fun connect(device: GlassesDevice) {
    _state.value = GlassesConnectionState.Connecting(device)
    viewModelScope.launch {
        delay(1500)                                              // ← fake
        _state.value = GlassesConnectionState.Connected(device.name)
    }
}
// startCapture() — does not exist
// stopCapture()  — does not exist
// CaptureArtifacts handoff — does not exist
```

### iOS reference architecture

iOS `GlassesCaptureManager.swift` has:

```swift
enum GlassesCaptureState { idle, preparing, streaming, paused, finished, error(String) }

struct StreamingInfo { let fps: Double; let framesReceived: Int; let durationSec: Double }
struct CaptureArtifacts { let videoUrl: URL; let framesDirectory: URL; let metadataUrl: URL }

class GlassesCaptureManager: ObservableObject {
    @Published var captureState: GlassesCaptureState = .idle
    @Published var streamingInfo: StreamingInfo?
    @Published var lastArtifacts: CaptureArtifacts?

    func connect(device: DiscoveredDevice) async throws
    func startCapture(outputDirectory: URL) async throws
    func pauseCapture()
    func resumeCapture()
    func stopCapture() async throws -> CaptureArtifacts
}
```

### Prerequisite — MWDAT Android SDK

Before writing any code, confirm:

1. **Does an Android MWDAT SDK exist?** The iOS SDK is from Meta/Luxottica's internal MWDAT
   programme. As of early 2026, only an iOS SDK is publicly documented. Check with your Meta
   partnership contact for an Android equivalent (AAR or Maven artifact).
2. **If the SDK exists** — get the AAR and add it to `android/app/libs/`. Then add to
   `app/build.gradle.kts`:
   ```kotlin
   dependencies {
       implementation(files("libs/mwdat-sdk.aar"))
   }
   ```
3. **If no Android SDK exists** — see "Fallback approach" below.

### Implementation plan (assuming SDK exists)

#### New file: `GlassesCaptureManager.kt`

Mirrors iOS `GlassesCaptureManager`. Owns the SDK session lifecycle, independent of the ViewModel:

```kotlin
sealed class GlassesCaptureState {
    object Idle : GlassesCaptureState()
    object Preparing : GlassesCaptureState()
    data class Streaming(val fps: Double, val framesReceived: Int, val durationSec: Double)
        : GlassesCaptureState()
    object Paused : GlassesCaptureState()
    data class Finished(val artifacts: GlassesCaptureArtifacts) : GlassesCaptureState()
    data class Error(val message: String) : GlassesCaptureState()
}

data class GlassesCaptureArtifacts(
    val videoFile: File,
    val framesDirectory: File,
    val metadataFile: File,
)

@Singleton
class GlassesCaptureManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    val captureState: StateFlow<GlassesCaptureState>

    suspend fun connect(deviceAddress: String)          // replaces fake delay(1500)
    suspend fun startCapture(outputDir: File)
    fun pauseCapture()
    fun resumeCapture()
    suspend fun stopCapture(): GlassesCaptureArtifacts
    fun disconnect()
}
```

Key implementation notes for each method:
- **`connect()`**: Call `MWDATSession.connect(address)` (or equivalent SDK entry point). Emit
  `Preparing` immediately, `Streaming` on success, `Error` on timeout/failure.
- **`startCapture(outputDir)`**: Call `session.startRecording(outputDir)`. SDK streams frames to
  `outputDir/frames/` and writes metadata JSON.
- **`stopCapture()`**: Call `session.stopRecording()`. SDK returns artifact paths. Wrap into
  `GlassesCaptureArtifacts` and emit `Finished(artifacts)`.
- **`pauseCapture()` / `resumeCapture()`**: Maps to SDK pause/resume if supported, else no-op.

#### Modify `GlassesViewModel.kt`

Inject `GlassesCaptureManager`:
```kotlin
class GlassesViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val captureManager: GlassesCaptureManager,  // ← add
) : ViewModel()
```

Replace `connect()`:
```kotlin
fun connect(device: GlassesDevice) {
    _state.value = GlassesConnectionState.Connecting(device)
    viewModelScope.launch {
        runCatching { captureManager.connect(device.id) }
            .onSuccess { _state.value = GlassesConnectionState.Connected(device.name) }
            .onFailure { _state.value = GlassesConnectionState.Error(it.message ?: "Connection failed") }
    }
}
```

Add capture controls exposed to the UI:
```kotlin
val captureState: StateFlow<GlassesCaptureState> = captureManager.captureState

fun startCapture(outputDir: File) {
    viewModelScope.launch { runCatching { captureManager.startCapture(outputDir) } }
}

fun stopCaptureAndGetArtifacts(): Flow<GlassesCaptureArtifacts?> = flow {
    emit(runCatching { captureManager.stopCapture() }.getOrNull())
}
```

#### Handoff to upload pipeline

When `stopCapture()` returns `GlassesCaptureArtifacts`, the flow mirrors phone-camera capture:

1. Build an `AndroidCaptureBundleRequest` with `captureSource = AndroidCaptureSource.MetaGlasses`
2. Pass `artifacts.videoFile` as the video input to `AndroidCaptureBundleBuilder.writeBundle()`
3. Enqueue via `CaptureUploadRepository.enqueueBundleUpload()`

`AndroidCaptureBundleRequest` already has `captureSource: AndroidCaptureSource` with
`MetaGlasses` as a defined enum value — no model changes needed.

#### Modify `GlassesConnectionSheet.kt`

The `Connected` state card needs "Start Capture" / "Stop Capture" buttons wired to
`viewModel.startCapture()` / `viewModel.stopCaptureAndGetArtifacts()`. The existing card only
shows a disconnect link — extend it:

```kotlin
is GlassesConnectionState.Connected -> {
    ConnectedCard(
        deviceName = s.deviceName,
        captureState = captureState,
        onStartCapture = { viewModel.startCapture(outputDir) },
        onStopCapture  = { viewModel.stopCaptureAndGetArtifacts() },
        onDisconnect   = viewModel::disconnect,
    )
}
```

### Fallback approach (if no Android MWDAT SDK)

If Meta has no Android SDK, the realistic fallback is to make the connection *honest* rather than
fake, and surface a clear message:

1. **Real BLE GATT connection**: `GlassesViewModel` already scans for real devices. Extend
   `connect()` to open a real BLE GATT connection using `device.connectGatt()`. Expose actual
   connection state (connecting → connected → disconnected) driven by `BluetoothGattCallback`.
2. **Honest capture UI**: When connected, show a card that reads "Video capture from Meta Glasses
   requires the MWDAT SDK — currently unavailable on Android. Audio annotation mode only." then
   offer to record an audio note via the phone mic and submit it as `captureSource = "android_phone"`.
3. **Remove mock injection**: Delete `injectMock()` and the emulator fake. Either find a real device
   or show a "No glasses found" empty state honestly.

This is the minimum to remove the lie from the UI without requiring an SDK that may not exist.

### Acceptance test (SDK path)
1. Launch app, open Glasses sheet, scan, select real Ray-Ban Meta device.
2. BLE connection completes — state shows "Connected" with real GATT (no `delay()`).
3. Tap "Start Capture" — frames begin streaming, streaming info updates (FPS counter).
4. Tap "Stop Capture" — artifacts returned, upload enqueued, appears in upload queue overlay.
5. Admin console shows `capture_source: "meta_glasses"` on the submission document.

---

## Implementation Order

| # | Gap | Why this order |
|---|---|---|
| 1 | ContributorProfile DemoData | 15-minute fix, unblocks accurate data everywhere |
| 2 | Wallet Ledger real data | Medium effort, completely self-contained, high user-visible value |
| 3 | Meta Glasses pipeline | Blocked on MWDAT SDK availability — confirm first, then implement |

---

## Files Changed Per Gap

### Gap 1 — ContributorProfile
- `data/profile/ContributorProfileRepository.kt` — 4 line changes

### Gap 2 — Wallet Ledger
- `ui/screens/WalletViewModel.kt` — inject `CaptureHistoryRepository`, real `refresh()`
- `ui/screens/WalletScreen.kt` — replace `WalletLedgerContent` with real row list
- `data/capture/CaptureHistoryRepository.kt` — already implemented, no changes needed
  (optionally: add `fetchCashouts()` if `users/{uid}/payouts` collection exists)

### Gap 3 — Meta Glasses
- **New**: `data/glasses/GlassesCaptureManager.kt` — SDK session lifecycle
- `ui/screens/GlassesViewModel.kt` — inject manager, real `connect()`, add capture controls
- `ui/screens/GlassesConnectionSheet.kt` — add Start/Stop Capture buttons to Connected card
- `di/AppModule.kt` — no changes (Hilt picks up `@Singleton` via `@Inject constructor`)
