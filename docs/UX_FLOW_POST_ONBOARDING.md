# Blueprint Capture: Complete UX Flow Documentation
## From Post-Onboarding to Video Upload (Cloud GPU Pipeline Input)

---

## Overview

After onboarding completion (marked by `com.blueprint.isOnboarded = true` in UserDefaults), the app presents a tab-based navigation interface with three main sections: **Nearby Targets**, **Glasses Capture**, and **Settings**. The primary capture flow focuses on discovering nearby targets, reserving them, capturing video with ARKit data, and uploading to Firebase Storage.

---

## PHASE 1: ENTRY POINT & NAVIGATION STRUCTURE

### 1.1 App Entry Point
**File:** `BlueprintCaptureApp.swift:4-15`

```swift
@main struct BlueprintCaptureApp: App {
    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false

    var body: some Scene {
        WindowGroup {
            if isOnboarded {
                MainTabView()  // ← Entry after onboarding
            } else {
                OnboardingFlowView()
            }
        }
    }
}
```

### 1.2 Main Tab Navigation
**File:** `MainTabView.swift:3-26`

| Tab | View | Icon | Purpose |
|-----|------|------|---------|
| 1 (Default) | `NearbyTargetsView` | `mappin.and.ellipse` | Discover & reserve nearby capture targets |
| 2 | `GlassesCaptureView` | `eyeglasses` | Meta glasses capture mode |
| 3 | `SettingsView` | `person.circle.fill` | User settings & profile |

---

## PHASE 2: NEARBY TARGETS DISCOVERY & RESERVATION

### 2.1 View Initialization Sequence
**File:** `NearbyTargetsView.swift:5-95`

1. `@StateObject` creates `NearbyTargetsViewModel`
2. `.task` modifier calls `viewModel.onAppear()`
3. ViewModel initializes:
   - `LocationService` - GPS coordinates
   - `TargetsAPI` - Backend target fetching
   - `PricingAPI` - Payout calculations
   - `NearbySeedsStore` - Prefetched cache

### 2.2 Location & Target Loading
**File:** `NearbyTargetsViewModel.swift:102-149`

```
User opens app
    ↓
LocationService.requestWhenInUseAuthorization()
    ↓
didUpdateLocations callback triggers
    ↓
Check NearbySeedsStore for prefetched targets
    ↓
If cache exists → Display immediately
    ↓
Call refresh() → TargetsAPI.fetchNearby(lat, lon, radius, limit, sort)
    ↓
Update @Published items: [NearbyItem]
```

### 2.3 Nearby Targets List UI
**File:** `NearbyTargetsView.swift:40-230`

**Display Components:**
- **Address Chip** (Line 44-46): Current user location (tappable for address search)
- **FilterBar** (Line 48-50): Radius (0.5-10 mi), Limit (10-25), Sort (payout/distance/demand)
- **Meta Bar** (Line 59-60): Result count + last update timestamp
- **Reservation Banner** (Line 62-65): Shows active reservation countdown
- **Target List** (Line 171-223): Scrollable list of `TargetRow` components

**Each TargetRow displays:**
- Street view thumbnail
- Business name & address
- Distance from user
- Payout amount
- Demand indicator

### 2.4 Address Search Modal
**File:** `NearbyTargetsView.swift:356-556`

**Flow:**
1. User taps address chip → Opens address search sheet
2. Recent searches displayed (Line 372-386)
3. Quick filters: Coffee, Gas, Groceries, etc. (Line 388-403)
4. Real-time search with 350ms debounce (Line 463-465)
5. Google Places Autocomplete with session token
6. Falls back to MapKit if Places fails
7. Selection updates search center & refreshes targets

### 2.5 Target Selection & Action Sheet
**File:** `NearbyTargetsView.swift:710-850`

**User taps target row → Action sheet appears with:**

| Button | Condition | Action |
|--------|-----------|--------|
| "Reserve for 1 hour" | Not reserved | `viewModel.reserveTarget()` |
| "Check in & start mapping" | On-site (≤150m) | `viewModel.checkIn()` → Navigate to capture |
| "Get directions" | Off-site | Opens Maps app |
| "Cancel reservation" | Reserved by me | `viewModel.cancelReservation()` |

### 2.6 Reservation Logic
**File:** `NearbyTargetsViewModel.swift:200-232`

```
attemptReserve(target)
    ↓
Check distance ≤ maxReservationDriveMinutes (45 min default)
    ↓
Calculate driving ETA (or fall back to air miles)
    ↓
targetStateService.reserve(targetId, duration: 3600s)
    ↓
If fails → reservationService.reserve() as fallback
    ↓
Emit .reserved(until: Date) event
    ↓
Schedule expiry notification
```

### 2.7 On-Site Check
**File:** `NearbyTargetsViewModel.swift:177-181`

```swift
func isOnSite(_ target: NearbyItem) -> Bool {
    guard let userLocation = currentLocation else { return false }
    let distance = userLocation.distance(from: target.location)
    return distance <= 150  // meters
}
```

### 2.8 Check-In Flow
**File:** `NearbyTargetsView.swift:757-804` & `NearbyTargetsViewModel.swift:258-265`

```
User taps "Check in & start mapping"
    ↓
isOnSite(target) == true?
    ↓ YES                              ↓ NO
viewModel.checkIn(target)      → Show guidance alert
    ↓                               "Please move closer"
targetStateService.checkIn()
    ↓
captureFlow.step = .readyToCapture
    ↓
captureManager.configureSession()
    ↓
captureManager.startSession()
    ↓
navigateToCapture = true
```

---

## PHASE 3: CAPTURE SESSION INITIALIZATION

### 3.1 Capture Session View
**File:** `CaptureSessionView.swift:5-77`

**View receives:**
- `viewModel`: CaptureFlowViewModel
- `captureManager`: VideoCaptureManager
- `targetId`: String? (from Nearby Targets)
- `reservationId`: String? (from reservation)

**UI Layout:**
```
┌─────────────────────────────────────┐
│  [Upload Status List]    (top-left) │
│                                     │
│                                     │
│       LIVE CAMERA PREVIEW           │
│       (AVCaptureVideoPreviewLayer)  │
│                                     │
│                                     │
│                    [End Session]    │
│                    (bottom-right)   │
└─────────────────────────────────────┘
```

### 3.2 Auto-Start Recording
**File:** `CaptureSessionView.swift:119-137`

```swift
func autoStartRecordingIfNeeded() {
    // Wait for AVCaptureSession to be configured
    guard captureManager.session.isRunning else { return }

    // 200ms delay for stability
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        captureManager.startRecording()
    }
}
```

---

## PHASE 4: VIDEO & SENSOR DATA CAPTURE

### 4.1 Session Configuration
**File:** `VideoCaptureManager.swift:229-287`

```
configureSession()
    ↓
session.sessionPreset = .high
    ↓
Add back camera input (AVCaptureDeviceInput)
    ↓
Add microphone input (AVCaptureDeviceInput)
    ↓
Add movie output (AVCaptureMovieFileOutput)
    ↓
startSession() on background queue
```

### 4.2 Recording Artifacts Structure
**File:** `VideoCaptureManager.swift:727-758`

```
/tmp/walkthrough-{UUID}/
├── walkthrough.mov          # Main video file
├── motion.jsonl             # IMU data (60 Hz)
├── manifest.json            # Capture metadata
└── arkit/                   # ARKit data (if LiDAR available)
    ├── frames.jsonl         # Frame timestamps & transforms
    ├── poses.jsonl          # Camera pose per frame
    ├── intrinsics.json      # Camera intrinsics (once)
    ├── depth/               # Depth maps
    │   ├── 000001.png
    │   ├── smoothed-000001.png
    │   └── ...
    ├── confidence/          # Confidence maps
    │   ├── 000001.png
    │   └── ...
    ├── meshes/              # Mesh anchors (OBJ format)
    │   └── ...
    └── objects/             # Point clouds
        ├── index.json
        └── ...
```

### 4.3 Start Recording Sequence
**File:** `VideoCaptureManager.swift:306-370`

```
startRecording()
    ↓
Create RecordingArtifacts (temp directory + file URLs)
    ↓
prepareMotionLog() → Open FileHandle for motion.jsonl
    ↓
prepareARKitLoggingIfNeeded() → Open handles for AR files
    ↓
startMotionUpdates() → CMMotionManager at 60 Hz
    ↓
startExposureLogging() → Timer every 0.5s
    ↓
movieOutput.startRecording(to: videoURL)
    ↓
captureState = .recording(artifacts)
```

### 4.4 Motion Data Logging (60 Hz)
**File:** `VideoCaptureManager.swift:933-966`

**motion.jsonl format (one JSON object per line):**
```json
{
  "timestamp": 12345.678,
  "wallTime": "2024-12-09T15:30:45.123Z",
  "attitude": {
    "roll": 0.123,
    "pitch": -0.456,
    "yaw": 1.789,
    "quaternion": {"x": 0.1, "y": 0.2, "z": 0.3, "w": 0.9}
  },
  "rotationRate": {"x": 0.01, "y": 0.02, "z": 0.03},
  "gravity": {"x": 0.0, "y": -1.0, "z": 0.0},
  "userAcceleration": {"x": 0.1, "y": 0.05, "z": -0.02}
}
```

### 4.5 ARKit Integration
**File:** `VideoCaptureManager.swift:838-1083`

**Triggered when video recording starts:**
```
fileOutput(didStartRecordingTo:)
    ↓
startARSessionIfAvailable()
    ↓
Configure ARWorldTrackingConfiguration:
  - sceneDepth: true
  - smoothedSceneDepth: true
  - sceneReconstruction: .mesh
    ↓
arSession.run(config, options: [.resetTracking])
```

**Per-frame ARKit data capture:**
```
ARSessionDelegate.session(didUpdate: frame)
    ↓
writeARFrame(frame)
    ↓
├── Append to frames.jsonl (timestamp, transform, resolution)
├── Save depth map → depth/000001.png
├── Save smoothed depth → depth/smoothed-000001.png
├── Save confidence map → confidence/000001.png
└── Append to poses.jsonl (4x4 camera transform)
```

**frames.jsonl format:**
```json
{
  "frameIndex": 1,
  "timestamp": 12345.678,
  "cameraTransform": [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],
  "imageResolution": {"width": 1920, "height": 1440}
}
```

**poses.jsonl format:**
```json
{
  "frameIndex": 1,
  "timestamp": 12345.678,
  "transform": [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]
}
```

### 4.6 Exposure Logging (0.5 Hz)
**File:** `VideoCaptureManager.swift:1098-1125`

**Captured every 0.5 seconds:**
- ISO value
- Exposure duration
- Exposure target bias
- White balance gains (R, G, B)

**Stored in `exposureSamples` array, written to manifest.json at end.**

### 4.7 Mesh Anchor Export
**File:** `VideoCaptureManager.swift:1085-1096`

**ARMeshAnchor exported as OBJ format:**
- Vertices with applied anchor transform
- Triangle indices
- Per-vertex normals (if available)

---

## PHASE 5: RECORDING COMPLETION & PACKAGING

### 5.1 User Ends Session
**File:** `CaptureSessionView.swift:176-191`

```swift
func endSession() {
    isEnding = true
    shouldDismissOnCompletion = true
    captureManager.stopRecording()
    captureManager.stopSession()
}
```

### 5.2 Recording Completion Handler
**File:** `VideoCaptureManager.swift:637-712`

```
AVCaptureFileOutputRecordingDelegate.fileOutput(didFinishRecordingTo:)
    ↓
handleRecordingCompletion(error:, durationSeconds:)
    ↓
Stop motion updates → Close motion.jsonl FileHandle
    ↓
Stop exposure logging → Stop timer
    ↓
Stop AR session → arSession.pause()
    ↓
persistManifest(duration:) → Write manifest.json
    ↓
packageArtifacts() → Create ZIP or leave as directory
    ↓
captureState = .finished(artifacts)
```

### 5.3 Manifest.json Structure
**File:** `VideoCaptureManager.swift:1396-1446`

```json
{
  "scene_id": "",
  "video_uri": "",
  "device_model": "iPhone 15 Pro",
  "os_version": "17.2",
  "fps_source": 30.0,
  "width": 1920,
  "height": 1440,
  "capture_start_epoch_ms": 1702137045123,
  "has_lidar": true,
  "scale_hint_m_per_unit": 1.0,
  "intended_space_type": "home",
  "object_point_cloud_index": "arkit/objects/index.json",
  "object_point_cloud_count": 5,
  "exposure_samples": [
    {"timestamp": 0.5, "iso": 100, "exposureDuration": 0.033, ...},
    ...
  ]
}
```

### 5.4 Artifact Packaging
**File:** `VideoCaptureManager.swift:1707-1722`

```
packageArtifacts(artifacts)
    ↓
If ZIPFoundation available:
    Create /tmp/walkthrough-{UUID}.zip
    ↓
    Contains entire recording directory
Else:
    Upload directory recursively (fallback)
```

---

## PHASE 6: UPLOAD TO FIREBASE STORAGE

### 6.1 Upload Initialization
**File:** `CaptureFlowViewModel.swift:339-355`

```
handleRecordingFinished(artifacts:, targetId:, reservationId:)
    ↓
Create CaptureUploadMetadata:
    - id: UUID()
    - targetId: from Nearby Targets
    - reservationId: from reservation
    - jobId: reservationId ?? targetId ?? UUID
    - creatorId: profile.id.uuidString
    - capturedAt: Date()
    - captureSource: .iphoneVideo
    ↓
Create CaptureUploadRequest(packageURL, metadata)
    ↓
uploadService.enqueue(request)
```

### 6.2 Upload Service Queue
**File:** `CaptureUploadService.swift:78-116`

```swift
func enqueue(_ request: CaptureUploadRequest) {
    queue.async {
        self.storeAndBeginUpload(request)
    }
}

func storeAndBeginUpload(_ request: CaptureUploadRequest) {
    uploads[request.id] = request
    emit(.queued(request))

    Task {
        await performUpload(for: request.id)
    }
}
```

### 6.3 Firebase Storage Path Structure
**File:** `CaptureUploadService.swift:381-393`

```
gs://blueprint-8c1ca.appspot.com/
└── scenes/
    └── {sceneId}/                    # targetId or reservationId or jobId
        └── {source}/                 # "iphone" or "glasses"
            └── {timestamp}-{uuid}/   # ISO8601 + UUID folder
                └── raw/
                    ├── walkthrough.mov
                    ├── motion.jsonl
                    ├── manifest.json
                    └── arkit/
                        ├── frames.jsonl
                        ├── poses.jsonl
                        ├── intrinsics.json
                        ├── depth/
                        │   ├── 000001.png
                        │   └── ...
                        ├── confidence/
                        │   └── ...
                        └── meshes/
                            └── ...
```

### 6.4 Upload Execution
**File:** `CaptureUploadService.swift:118-229`

**For ZIP file:**
```
performUpload(for: id)
    ↓
Check packageURL exists
    ↓
storageRef = storage.reference().child(remotePath)
    ↓
uploadTask = storageRef.putFile(from: packageURL, metadata: metadata)
    ↓
Observe progress: uploadTask.observe(.progress) { snapshot in
    let progress = Double(snapshot.progress!.completedUnitCount) /
                   Double(snapshot.progress!.totalUnitCount)
    emit(.progress(id, progress))
}
    ↓
Wait for completion or failure
    ↓
emit(.completed(id)) or emit(.failed(id, error))
```

**For Directory (non-ZIP):**
```
uploadDirectory(localDirectory:, remoteBasePath:)
    ↓
Enumerate all files in directory
    ↓
Calculate total bytes for progress
    ↓
For each file:
    ├── Create relative path
    ├── Construct remote path
    ├── Special handling for manifest.json:
    │   - Patch scene_id field
    │   - Patch video_uri field
    └── putFile() with metadata
    ↓
Track cumulative progress
    ↓
emit(.completed(id))
```

### 6.5 Custom Metadata
**File:** `CaptureUploadService.swift:158-167`

**Attached to each uploaded file:**
```json
{
  "jobId": "abc-123-def",
  "creatorId": "user-uuid-here",
  "capturedAt": "2024-12-09T15:30:45Z",
  "captureSource": "iphoneVideo",
  "targetId": "target-12345",
  "reservationId": "reservation-67890"
}
```

### 6.6 Upload Status UI
**File:** `CaptureSessionView.swift:30-33, 242-323`

**States displayed to user:**
| State | Display |
|-------|---------|
| Queued | "Waiting to upload…" |
| Uploading | Progress bar + percentage |
| Completed | Green checkmark + timestamp |
| Failed | Red X + error message + retry button |

---

## PHASE 7: POST-UPLOAD STATE MANAGEMENT

### 7.1 Target Completion
**File:** `CaptureFlowViewModel.swift:385-398`

```
handleUpload(.completed(id))
    ↓
If targetId exists and not empty:
    targetStateService.complete(targetId)
    ↓
    Firestore document updated
    ↓
    Target removed from "Nearby Targets" list
```

### 7.2 Return to Main UI
**File:** `CaptureSessionView.swift:95-99`

```
captureState == .finished(artifacts)
    ↓
If shouldDismissOnCompletion:
    viewModel.step = .confirmLocation
    dismiss()
    ↓
User returns to MainTabView
Upload continues in background
Status visible in overlay
```

---

## DATA STRUCTURES REFERENCE

### CaptureUploadMetadata
```swift
struct CaptureUploadMetadata: Codable {
    let id: UUID                      // Unique upload identifier
    let targetId: String?             // Target being mapped
    let reservationId: String?        // Reservation ID if applicable
    let jobId: String                 // Fallback identifier
    let creatorId: String             // User UUID
    let capturedAt: Date              // When capture started
    var uploadedAt: Date?             // When upload completed
    let captureSource: CaptureSource  // .iphoneVideo or .metaGlasses
}
```

### RecordingArtifacts
```swift
struct RecordingArtifacts {
    let baseFilename: String          // "walkthrough-{UUID}"
    let directoryURL: URL             // /tmp/walkthrough-{UUID}/
    let videoURL: URL                 // walkthrough.mov
    let motionLogURL: URL             // motion.jsonl
    let manifestURL: URL              // manifest.json
    let arKit: ARKitArtifacts?        // AR data (optional)
    let packageURL: URL               // .zip or directory
    let startedAt: Date
}
```

### ARKitArtifacts
```swift
struct ARKitArtifacts {
    let rootDirectoryURL: URL         // arkit/
    let frameLogURL: URL              // frames.jsonl
    let depthDirectoryURL: URL?       // depth/
    let confidenceDirectoryURL: URL?  // confidence/
    let meshDirectoryURL: URL?        // meshes/
    let posesLogURL: URL              // poses.jsonl
    let intrinsicsURL: URL            // intrinsics.json
    let objectDirectoryURL: URL?      // objects/
    let objectIndexURL: URL?          // objects/index.json
}
```

---

## COMPLETE USER JOURNEY FLOWCHART

```
┌─────────────────────────────────────────────────────────────────┐
│                     APP OPENS (POST-ONBOARDING)                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         MAIN TAB VIEW                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Nearby    │  │   Glasses   │  │  Settings   │              │
│  │   Targets   │  │   Capture   │  │             │              │
│  │  (Default)  │  │             │  │             │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    NEARBY TARGETS VIEW                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ [📍 Current Location Chip]           [🔄 Refresh]        │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │ Radius: [0.5-10 mi]  Limit: [10-25]  Sort: [▼]           │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │ 15 results • Updated 2 min ago                           │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │ ┌────────────────────────────────────────────────────┐   │   │
│  │ │ [StreetView] Coffee Shop           0.3 mi   $45    │   │   │
│  │ │              123 Main St           ●●●○○ demand    │   │   │
│  │ └────────────────────────────────────────────────────┘   │   │
│  │ ┌────────────────────────────────────────────────────┐   │   │
│  │ │ [StreetView] Gas Station           0.5 mi   $35    │   │   │
│  │ │              456 Oak Ave           ●●○○○ demand    │   │   │
│  │ └────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                │
                         User taps target
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ACTION SHEET                               │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Coffee Shop                                              │   │
│  │ 123 Main St                                              │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │ [🔒 Reserve for 1 hour]                                  │   │
│  │ [📍 Check in & start mapping]  ← Blue if on-site         │   │
│  │ [🗺️ Get directions]            ← If off-site             │   │
│  │ [❌ Cancel reservation]         ← If reserved by me      │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                │
                    User on-site, taps "Check in"
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CHECK-IN FLOW                                │
│                                                                 │
│  1. Reserve target implicitly (1 hour)                          │
│  2. Call targetStateService.checkIn()                           │
│  3. Configure AVCaptureSession                                  │
│  4. Start camera session                                        │
│  5. Navigate to CaptureSessionView                              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   CAPTURE SESSION VIEW                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ [Upload Status]                                          │   │
│  │ ┌────────────┐                                           │   │
│  │ │ ████░░ 65% │                                           │   │
│  │ └────────────┘                                           │   │
│  │                                                          │   │
│  │                                                          │   │
│  │              LIVE CAMERA PREVIEW                         │   │
│  │                                                          │   │
│  │                                                          │   │
│  │                                                          │   │
│  │                                    ┌─────────────────┐   │   │
│  │                                    │  End Session    │   │   │
│  │                                    └─────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                │
                   (Recording auto-starts after 200ms)
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DURING RECORDING                             │
│                                                                 │
│  Parallel data capture:                                         │
│  ├── Video: AVCaptureMovieFileOutput → walkthrough.mov          │
│  ├── Audio: Microphone input → embedded in video                │
│  ├── Motion: CMMotionManager @ 60Hz → motion.jsonl              │
│  ├── Exposure: Timer @ 0.5Hz → manifest.json                    │
│  └── ARKit (if LiDAR):                                          │
│      ├── Frames: → frames.jsonl                                 │
│      ├── Poses: → poses.jsonl                                   │
│      ├── Depth: → depth/*.png                                   │
│      ├── Confidence: → confidence/*.png                         │
│      ├── Intrinsics: → intrinsics.json (once)                   │
│      └── Meshes: → meshes/*.obj                                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                    User taps "End Session"
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    RECORDING COMPLETION                         │
│                                                                 │
│  1. Stop video recording                                        │
│  2. Stop motion updates, close file handle                      │
│  3. Stop exposure logging, stop timer                           │
│  4. Stop ARKit session                                          │
│  5. Write manifest.json with all metadata                       │
│  6. Package artifacts (ZIP or directory)                        │
│  7. captureState = .finished(artifacts)                         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    UPLOAD INITIALIZATION                        │
│                                                                 │
│  1. Create CaptureUploadMetadata                                │
│     - targetId, reservationId, jobId                            │
│     - creatorId, capturedAt, captureSource                      │
│  2. Create CaptureUploadRequest                                 │
│  3. Enqueue to CaptureUploadService                             │
│  4. Dismiss capture view                                        │
│  5. Return to MainTabView                                       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    BACKGROUND UPLOAD                            │
│                                                                 │
│  Firebase Storage path:                                         │
│  gs://blueprint-8c1ca.appspot.com/                              │
│    scenes/{sceneId}/iphone/{timestamp}-{uuid}/raw/              │
│                                                                 │
│  Upload all files with custom metadata:                         │
│  - jobId, creatorId, capturedAt, captureSource                  │
│  - targetId, reservationId                                      │
│                                                                 │
│  Progress events emitted: .queued → .progress(0.0-1.0) → .completed │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    POST-UPLOAD                                  │
│                                                                 │
│  1. Mark target as completed in Firestore                       │
│  2. Target removed from Nearby Targets list                     │
│  3. User can capture another target                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## KEY FILE REFERENCE MAP

| Component | Primary File | Line References |
|-----------|-------------|-----------------|
| App Entry | `BlueprintCaptureApp.swift` | 4-15 |
| Main Navigation | `MainTabView.swift` | 3-26 |
| Target Discovery | `NearbyTargetsView.swift` | 5-230 |
| Target ViewModel | `NearbyTargetsViewModel.swift` | 10-265 |
| Address Search | `NearbyTargetsView.swift` | 356-556 |
| Action Sheet | `NearbyTargetsView.swift` | 710-850 |
| Reservation | `NearbyTargetsViewModel.swift` | 200-232 |
| Check-In | `NearbyTargetsViewModel.swift` | 258-265 |
| Capture Session UI | `CaptureSessionView.swift` | 5-191 |
| Video Capture | `VideoCaptureManager.swift` | 229-370 |
| Motion Logging | `VideoCaptureManager.swift` | 908-966 |
| ARKit Integration | `VideoCaptureManager.swift` | 838-1083 |
| Recording Completion | `VideoCaptureManager.swift` | 637-712 |
| Manifest Creation | `VideoCaptureManager.swift` | 1396-1446 |
| Upload Service | `CaptureUploadService.swift` | 38-393 |
| Upload Events | `CaptureFlowViewModel.swift` | 366-408 |

---

## OUTPUT FILES FOR CLOUD GPU PIPELINE

### Primary Video
- **Path:** `raw/walkthrough.mov`
- **Format:** H.264/H.265 in MOV container
- **Resolution:** Device native (typically 1920x1440 or 4K)
- **Audio:** AAC embedded

### Motion Data
- **Path:** `raw/motion.jsonl`
- **Format:** JSONL (one JSON object per line)
- **Rate:** 60 Hz
- **Fields:** timestamp, wallTime, attitude (quaternion), rotationRate, gravity, userAcceleration

### Camera Poses
- **Path:** `raw/arkit/poses.jsonl`
- **Format:** JSONL
- **Rate:** ~30-60 Hz (ARKit frame rate)
- **Fields:** frameIndex, timestamp, transform (4x4 matrix)

### Depth Maps
- **Path:** `raw/arkit/depth/*.png`
- **Format:** 16-bit grayscale PNG
- **Resolution:** Varies (typically 256x192)
- **Naming:** `000001.png`, `smoothed-000001.png`, etc.

### Camera Intrinsics
- **Path:** `raw/arkit/intrinsics.json`
- **Format:** JSON
- **Fields:** fx, fy, cx, cy, width, height

### Mesh Data
- **Path:** `raw/arkit/meshes/*.obj`
- **Format:** Wavefront OBJ
- **Contents:** Vertices, triangle indices, normals

### Manifest
- **Path:** `raw/manifest.json`
- **Format:** JSON
- **Contents:** Device info, capture metadata, exposure samples

---

*Generated for Cloud GPU Pipeline integration - December 2024*
