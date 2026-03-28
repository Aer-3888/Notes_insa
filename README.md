# Notes INSA

Android app for INSA students to view grades, track averages, and receive notifications on grade updates.

## Features

- Fetch grades via secure native library (inscore)
- Biometric authentication
- Background fetch with push notifications on grade changes
- QR code scanner for Google Authenticator migration (TOTP secret import)
- Offline access with encrypted local storage

## Requirements

- Flutter SDK `^3.10.4`
- Android SDK (minSdk 21)
- Node.js (for pre-commit hooks)

## Installation

```bash
# Install Flutter dependencies
flutter pub get

# Install JS tooling (husky + prettier)
npm install

# Run on device
flutter run
```

## Build

```bash
flutter build apk --release
```

## Project structure

```
lib/
  screens/       # UI screens
  components/    # Reusable widgets
  providers/     # Riverpod state management
  services/      # Native bridge, auth, notifications
  models.dart    # Data models
  data.dart      # JSON parser
android/
  app/libs/      # inscore.aar native grades library
```
