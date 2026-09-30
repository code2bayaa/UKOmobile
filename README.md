# uko_mobile

UKO mobile (Flutter port)

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## iOS

The `ios/` folder was generated with `flutter create --platforms=ios` (2026-09-29). Building needs a Mac with Xcode and CocoaPods:

```bash
flutter build ios --release --dart-define-from-file=<same defines as Android>
```

- Bundle id `ke.co.uko.uko-movies` (iOS ids cannot contain `_`; Android uses `ke.co.uko.uko_movies`); set the signing team in Xcode.
- Minimum iOS 15.0.
- AdMob: `ADMOB_APP_ID` in `ios/Flutter/Debug.xcconfig` / `Release.xcconfig` is Google's test id; put the real iOS app id in `Release.xcconfig` before shipping.
- Info.plist declares camera (QR buy), microphone (watch party), location (region check), local network (phone-to-phone sale server) and allows plain http.
- Android-only path: the `/storage/emulated/0/Download` fallback in signup. On iOS the app uses the Documents folder, which shows up in the Files app.
