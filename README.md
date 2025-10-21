# BlueprintCapture

A SwiftUI-based iOS app for capturing AR walkthroughs. This app allows users to record video of spaces with motion data for AI analysis.

## Project Structure

### App Entry Points
- **BlueprintCaptureApp.swift** - Main SwiftUI app entry point with scene setup
- **ContentView.swift** - Navigation flow container with state management
- **AppDelegate.swift** - App lifecycle management

### Views
- **ProfileReviewView.swift** - User profile information screen
- **LocationConfirmationView.swift** - Location selection and confirmation
- **PermissionRequestView.swift** - Camera/microphone permission requests
- **CaptureSessionView.swift** - Main video capture interface with preview

### Data & Logic
- **CaptureFlowViewModel.swift** - Main state management for capture flow
- **VideoCaptureManager.swift** - AVFoundation-based video capture manager
- **UserProfile.swift** - User data model

### Configuration
- **Info.plist** - App configuration and privacy permissions
- **Assets.xcassets** - App icons and colors

## Features

- SwiftUI-based interface using functional components and Tailwind-like styling
- AVFoundation video capture with motion tracking
- Location-based capture anchoring
- Camera and microphone access with permission handling

## Requirements

- iOS 15.0+
- SwiftUI 2.0+
- Xcode 13+

## Building & Running

```bash
# Open the project in Xcode
open BlueprintCapture.xcodeproj

# Build for iOS device or simulator
xcodebuild -project BlueprintCapture.xcodeproj -scheme BlueprintCapture
```

## Architecture Notes

- Uses MVVM pattern with SwiftUI
- SwiftUI views for all UI (no UIKit storyboards)
- AVFoundation for video capture instead of Metal/ARKit
- Reactive state management with @Published properties
