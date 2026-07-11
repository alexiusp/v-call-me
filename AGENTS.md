# AGENTS.md

Context file for AI coding agents (Claude Code, Cursor, etc.) working in this repo. Read `DESIGN.md` first for the product/protocol design (threat model, QR payload schema, call state machine). This file is about *how the code is organized and how to work in this repo* - check section 9 of `DESIGN.md` for a snapshot of what's actually implemented before assuming a feature exists.

## Project

Single Flutter app, targeting **Android and Web**, package `v_call_me`, application ID `dev.podgaev.v_call_me`. Both call participants ("host" and "joiner") use the same app; role is chosen at runtime, not at build time.

## Architecture direction

The codebase is currently a small flat scaffold (`lib/screens/`, `lib/services/`) with placeholder screens and a stub `CallSession`. As real functionality lands (SDP encode/decode, WebRTC wiring, QR generation/scanning), organize new code along clean-architecture lines rather than letting it all pile into screen widgets:

- **`domain/`** - plain Dart, no Flutter/package imports where avoidable: the `CallSession` state machine, the compact SDP payload encode/decode, entities (offer/answer payload, ICE candidate, etc.), and repository *interfaces* (e.g. a `SignalingCodec` or `PeerConnectionGateway` abstraction so `flutter_webrtc` isn't imported directly into domain code).
- **`data/`** - concrete implementations of those interfaces: the `flutter_webrtc` adapter, QR encode/decode via `qr_flutter`/`mobile_scanner`, permission handling.
- **`presentation/`** (or keep `screens/` - naming isn't sacred) - widgets only. Screens should call into domain/data through a thin controller/notifier, not construct `RTCPeerConnection`s or touch SDP directly.

Don't force this split prematurely on something that's still a one-line stub - a `throw UnimplementedError()` method doesn't need three layers. Apply the layering as real logic actually lands in a piece of code, not before. Avoid over-engineering: no repository interface for something with exactly one implementation and no plausible second one.

## Dart/Flutter conventions

- Follow standard `flutter_lints` (already enabled in `analysis_options.yaml`); keep `flutter analyze` clean.
- No doc comments on obvious code; a comment is only worth it when it explains a non-obvious *why* (see the concurrency note in the original `SurfaceTextureRenderer`-style code we've hit in `flutter_webrtc` for what that looks like).
- Prefer `const` constructors and widgets where possible.
- Keep screens dumb: navigation + layout only. Business logic (state machine transitions, encode/decode) belongs in `domain`/`data`, unit-testable without pumping a widget tree.
- New non-trivial logic (SDP codec, `CallSession` transitions) should get plain `package:test`/`flutter_test` unit tests, not just widget smoke tests.
- Global app state (locale, debug-panel toggle) lives in Riverpod `Notifier`/`Provider`s in `lib/state/`, not `StatefulWidget` fields - see `settings.dart`. Anything that needs to persist across launches reads/writes through `sharedPreferencesProvider`, overridden once in `main()` with the instance loaded before `runApp`.
- No hardcoded UI strings - route every user-facing string through `context.l10n` (the `AppLocalizations` extension in `lib/l10n/l10n.dart`). Add new strings to `lib/l10n/app_en.arb` first (source of truth) and `app_ru.arb`, then regenerate with `flutter gen-l10n` (or just `flutter pub get`/`flutter run`, which triggers it automatically since `generate: true` is set in `pubspec.yaml`).
- This app targets **Android and Web**; guard any plugin call that lacks a web implementation with `kIsWeb` (from `package:flutter/foundation.dart`) rather than letting it throw `MissingPluginException` at runtime - see `shared_qr_intent_listener.dart` (`share_handler` has no web impl) and `qr_import_screen.dart` (`mobile_scanner`'s gallery `analyzeImage` has no web impl). QR codes are encoded as `vcallme://call?d=...` link *text* (`QrCode.fromData`, decoded back via `qr_link_codec.dart`'s `decodeQrText`) rather than raw byte-mode (`QrCode.fromUint8List`/`barcode.rawBytes`), because byte-mode payloads aren't recoverable through `mobile_scanner`'s web scanner - keep using the text-link path for any new QR-carrying code rather than reverting to raw bytes.

## Dev commands

```
flutter pub get
flutter analyze
flutter test
flutter build apk --debug      # full Android build, see gotchas below
flutter run -d <device-id>     # e.g. the emulator-5554 AVD, or `chrome` for web
flutter build web              # full web build
```

## Toolchain versions (keep these in sync, don't let them drift apart)

- Flutter: 3.44.5 stable (upgrade with `flutter upgrade` if it goes stale - this project was bumped from 3.27.1 once already because `flutter_webrtc` 1.5.2+ requires a newer engine `TextureRegistry.SurfaceProducer.Callback` API than 3.27.1 shipped).
- AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14.5 (`android/settings.gradle`, `android/gradle/wrapper/gradle-wrapper.properties`) - these are the minimums Flutter 3.44.x's own build-dependency-validation demands. If `flutter build` warns about outdated Gradle/AGP/Kotlin, that warning is accurate; bump them rather than suppressing it.
- `compileSdk` / `minSdk` / `ndkVersion` in `android/app/build.gradle` are deliberately left as `flutter.compileSdkVersion` / `flutter.minSdkVersion` / `flutter.ndkVersion` (not hardcoded) so they move automatically with Flutter upgrades. They currently resolve to compileSdk 36, minSdk 24, NDK 28.2.13676358 - high enough to satisfy `flutter_webrtc` and `mobile_scanner`'s own requirements (compileSdk >= 36, NDK >= 27.0.12077973, and `androidx.camera:camera-core` needing minSdk >= 23). If you add a plugin that needs something higher than the current Flutter defaults provide, hardcode *only* the field that needs bumping and prefer the flutter default otherwise.

## Environment gotchas (Windows dev machine)

- The Android SDK's `cmdline-tools` package is not installed by Android Studio automatically; it was manually unzipped from Google's `commandlinetools-win` distribution into `%LOCALAPPDATA%\Android\sdk\cmdline-tools\latest`. If `flutter doctor` complains about missing cmdline-tools again (e.g. after an SDK reset), redo that rather than assuming Android Studio's SDK Manager checkbox will get clicked.
- Gradle/Kotlin daemons are memory-hungry (multi-GB each) and persist after the invoking `flutter build`/shell process is killed - killing your wrapper process does **not** kill the daemon. If a build seems to hang with zero output, check for an orphaned daemon before assuming the build itself is stuck: it may well have already finished (check `build/app/outputs/flutter-apk/app-debug.apk`'s mtime).
- To stop this project's Gradle daemons cleanly: `cd android && JAVA_HOME="C:/programs/AndroidStudio/jbr" ./gradlew.bat --stop` (plain `./gradlew --stop` fails if the shell's `JAVA_HOME` points at a stale JRE).
- `tasklist`/`wmic` invoked from the Bash tool can hang for minutes on this machine even when the system is otherwise responsive (unclear root cause - possibly a Bash-tool/Windows interaction, not confirmed to be real memory pressure every time). Prefer the PowerShell tool with `Get-Process` for checking running processes; it's been reliable where `tasklist`/`wmic` were not.
- A full Gradle build after a toolchain version bump (new AGP/Kotlin/Gradle/NDK) is memory-intensive and can be slow or crash with a native `mmap`/"paging file too small" error if other heavy apps (IDEs, browsers) are competing for RAM. Closing other apps before a first cold build after a toolchain bump is reasonable advice to give the user, not just a one-off workaround.
- Never force-kill `java.exe` system-wide - Android Studio runs its own JVM and would die with it. Scope any process cleanup to the specific PID or use the Gradle wrapper's own `--stop`.

## Testing expectations

Before calling a change done: `flutter analyze` clean, `flutter test` passing, and for anything touching Android build config, an actual `flutter build apk --debug` (analyze/test alone won't catch Gradle-level SDK/NDK/manifest mismatches - see DESIGN.md section 9 for the class of issues that only show up there).
