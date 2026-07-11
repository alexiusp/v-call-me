# Family video call app � design doc

## 1. Goal

A video calling app for staying in touch with family or friends in regions where mainstream apps are blocked or throttled (WhatsApp, Telegram calls, etc.). Single Flutter app, Android-first, used by both sides � "host" and "joiner" are roles within the same app, not separate apps.

## 2. Threat model / constraints

- Mainstream apps may be blocked at the domain/app-store level, and calls specifically are increasingly throttled or blocked via **deep packet inspection (DPI)** that recognizes VoIP/RTP traffic patterns � not just app-specific blocking. This means "no central server" alone doesn't guarantee the call survives; traffic *pattern* matters as much as traffic *destination*.
- WebRTC media is encrypted by default (DTLS-SRTP), so passive interception of call content isn't the primary risk � blocking/throttling is.
- No willingness to run a persistent signaling server. Signaling (the offer/answer exchange) is done **manually**, via QR code images shared through whatever messaging channel currently works (Telegram, SMS, email, etc.).
- A lightweight, non-signaling piece of infrastructure (STUN/TURN) is acceptable, since it never sees call content or call setup metadata � it only helps with NAT traversal and relays already-encrypted media as a fallback.

## 3. High-level architecture

Three logical components, no signaling server:

- **STUN + TURN relay** � used by both phones for NAT traversal (STUN) and as a fallback relay if a direct peer-to-peer path can't be established (TURN). Free tiers (Open Relay Project, Metered.ca) are sufficient for development and likely for this app's actual low-volume usage; self-hosting `coturn` on a cheap VPS is a fallback if more control or bandwidth is needed later.
- **One side's phone (host role)** � starts the call, generates the offer.
- **The other side's phone (joiner role)** � receives the offer via QR/file, generates the answer.

Between the two phones there are two distinct connections:
1. **Manual QR/file exchange** � carries the offer, then the answer. Out-of-band, via any messaging app that still works. Not part of the app's network layer at all � it's just an image file the user shares manually.
2. **Encrypted media (P2P, TURN fallback)** � the actual call, established once both sides have exchanged offer/answer and ICE connectivity checks succeed.

## 4. Why not raw SDP in the QR code

Raw WebRTC SDP (offer/answer text) typically runs 2�5 KB once codec negotiation lines and multiple ICE candidates are included � technically fits in a QR code but produces a dense, fragile one, especially after messaging apps recompress the image.

**Approach:** don't transmit raw SDP. Extract only the fields that vary per call into a compact custom binary format, and reconstruct a full valid SDP locally from a fixed template on the receiving end.

### Compact payload schema (draft)

```
[1B]  schema version
[1B]  flags (bit0: audio present, bit1: video present, bit2: offer=0/answer=1)
[6B]  session id (random � sanity-check that answer matches the offer it's replying to)
[1B]  ICE ufrag length, then ufrag bytes (~4-8B)
[1B]  ICE password length, then password bytes (~22-24B)
[32B] DTLS fingerprint (raw bytes, sha-256 � not hex text)
[1B]  candidate count (N)
N � 8B candidates: 1B type (host/srflx/relay) + 1B transport (udp/tcp) + 4B IPv4 + 2B port
```

Typical total: **~90�150 bytes** for 3 candidates (local, STUN-reflexive, TURN relay). This is small enough for a low-density QR code (version ~5�8) at **error-correction level H (30% redundancy)**, which scans reliably and tolerates the lossy recompression some messaging apps apply to shared photos.

Notes:
- Codec choice is not negotiated dynamically for v1 � hardcode Opus (audio) and VP8 (video) to avoid transmitting codec lists at all.
- Candidate foundation/priority fields (required by the ICE spec but not essential to transmit) should be regenerated locally using standard formulas rather than sent over the wire, to keep the payload minimal.
- If a future version needs a larger payload (e.g. more redundant candidates, IPv6), fall back to a short animated sequence of 2-3 QR frames rather than growing a single dense code.

### Practical QR/sharing notes

- Prefer "send as file/document" over "send as photo" in the share sheet where the target app supports it (e.g. Telegram) � file sends are typically lossless; photo sends are often JPEG-recompressed and can degrade the code.
- Use error-correction level H regardless, as a safety margin.
- The QR encodes the payload as `vcallme://call?d=<base64url>` link **text** (`QrCode.fromData`), not raw byte-mode bytes (`QrCode.fromUint8List`) � text round-trips through a scanner's `rawValue` on every platform, whereas byte-mode `rawBytes` isn't recoverable through `mobile_scanner`'s web implementation. This also means the QR image and the "Share" link button now carry byte-for-byte the same content, just two different transports for it.

## 5. Call flow / state machine

Both roles funnel through a shared `CallSession` manager wrapping `RTCPeerConnection` (via the `flutter_webrtc` package). Only the first couple of steps differ by role.

**Host:**
```
Idle -> Creating offer -> Gathering ICE (STUN/TURN) -> Show offer QR -> Waiting for answer import -> Connecting (ICE checks) -> Connected -> Ended
```

**Joiner:**
```
Idle -> Scan/import offer QR -> Creating answer -> Gathering ICE (STUN/TURN) -> Show answer QR -> Connecting (ICE checks) -> Connected -> Ended
```

ICE gathering is **non-trickle** (wait for full candidate gathering, including a pre-allocated TURN relay candidate, before generating the QR) � this is what allows the whole offer or answer to collapse into a single static code instead of a live back-and-forth.

Once both descriptions are set on both sides, ICE connectivity checks run automatically: direct P2P is tried first, falling back to the TURN relay candidate only if no direct pair succeeds. This happens inside the WebRTC stack � no app-level logic needed.

## 6. App structure (single Flutter app, two roles)

- **Home screen** � "Start a call" / "Join a call" buttons.
- **Shared `CallSession` manager class** � exposes the same API regardless of role: `createOffer()`, `acceptOfferAndCreateAnswer()`, `applyRemoteAnswer()`, `onConnected`, `onDisconnected`.
- **QR display screen** � renders the QR code for the current payload (offer or answer) + Android share sheet integration. Reused for both offer and answer.
- **QR import screen** � camera scanner and/or gallery image picker (for QR images received via a messenger, not necessarily scanned live). Reused for both offer and answer.
- **In-call screen** � shared regardless of role, since the session is symmetric once connected.

## 7. TURN/STUN infrastructure

- **Dev phase:** free hosted TURN � Open Relay Project or Metered.ca (~20 GB/month free), plus Google's public STUN server. No setup beyond grabbing credentials.
- **Self-hosting (if/when needed):** `coturn` on a small VPS (Hetzner/DigitalOcean/Oracle free tier). Basic working setup ~1-2 hours; hardened version with TLS on port 443 (to blend in with ordinary HTTPS and resist DPI-based throttling) ~half a day.
- Bandwidth math: a fully-relayed video call costs roughly 300 MB�900 MB/hour. Given this app's low call volume (family use), free tiers may be sufficient indefinitely if most calls connect directly P2P.

## 8. Security notes

- Call media is encrypted end-to-end via WebRTC's built-in DTLS-SRTP � this isn't something to add, it's default behavior.
- The QR payload doesn't need to be kept secret for call confidentiality � it can be sent in the clear over any channel. Its main sensitivity is that possessing it lets someone attempt to join that specific call.
- Optional hardening: display the connected peer's DTLS fingerprint (short hex string) on the in-call screen so it could be manually cross-checked if desired � not required for MVP, but cheap to add.

## 9. Implementation status (as of 2026-07-11)

Flutter project scaffolded, targeting **Android and Web**, package `v_call_me`, application ID `dev.podgaev.v_call_me`. See `AGENTS.md` for the target code architecture and dev environment notes.

**Dependencies wired in** (`pubspec.yaml`): `flutter_webrtc`, `qr_flutter`, `mobile_scanner`, `permission_handler`, `share_plus`, `image_picker`, `http`, `share_handler`, `app_links`, `flutter_riverpod` (state management), `flutter_localizations`/`intl` (generated `AppLocalizations`), `shared_preferences` (persisted settings).

**Android manifest** (`android/app/src/main/AndroidManifest.xml`): camera, microphone, internet, network-state, and Bluetooth permissions declared, plus camera/microphone `<uses-feature>` entries. Also `ACTION_SEND`/`ACTION_SEND_MULTIPLE` intent-filters for `image/*` on `MainActivity`, so a QR image received in another app (Telegram, SMS, etc.) can be sent straight to this app via the OS share sheet instead of being saved to the gallery first (see `services/shared_qr_intent_listener.dart` below). `READ_EXTERNAL_STORAGE` is declared with `maxSdkVersion="28"` for this - `content://` URIs from the share sheet resolve fine without it on API 29+ scoped storage. Also a custom-scheme `VIEW`/`BROWSABLE` intent-filter for `vcallme://call`, so tapping a shared link (see `services/qr_link_codec.dart`/`services/deep_link_listener.dart` below) opens the app directly.

**Toolchain**: Flutter 3.44.5 (stable), AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14.5. `compileSdk`/`minSdk`/NDK are left as Flutter's own defaults (currently 36 / 24 / 28.2.13676358) rather than hardcoded, so they track future Flutter upgrades automatically.

**TURN/STUN credentials**: a Metered ("Open Relay Project") API key, read from `lib/config/turn_config.dart` (gitignored - copy `turn_config.example.dart` to `turn_config.dart` and fill in a real key from https://www.metered.ca/tools/openrelay/ to build). The endpoint returns a JSON array already shaped like WebRTC's `iceServers` config, so `data/turn/turn_credentials_service.dart` passes it straight through with no reshaping.

**Code** (`lib/`, now split along the domain/data/services lines AGENTS.md describes, now that real logic has landed rather than stubs):
- `main.dart` - app entry point (`VCallMeApp`), routes to `HomeScreen`. Also defines `rootScaffoldMessengerKey`, an app-wide `GlobalKey<ScaffoldMessengerState>` attached to `MaterialApp` so a screen can show a message that survives navigating away and being disposed (used by `InCallScreen` below).
- `screens/home_screen.dart` - "Start a call" / "Join a call" buttons; navigates to `QrDisplayScreen` / `QrImportScreen`. Also defines the shared `CallRole` enum (host/joiner).
- `screens/qr_display_screen.dart` - renders the current payload as a QR code carrying the same `vcallme://call?d=...` link text the Share button uses (`QrCode.fromData`/`QrImageView.withQr`, error-correction level H per section 4 - see the QR-encoding note in section 4 for why text rather than raw byte-mode). The primary "Share" button (`share_plus`) shares that link as plain text - tapping it on the other side opens straight into the right screen with no scanning or gallery step (see `services/deep_link_listener.dart`). A secondary, lower-emphasis "Share as image instead" button falls back to a QR PNG file share (via `services/qr_export.dart`, deliberately sent with no `subject` - see known limitations) for a channel that mangles custom-scheme links. For the host role, if no payload is passed in it drives `CallSession.createOffer()` itself and shows a loading state while awaiting it; it also shows a button to move on to `QrImportScreen` to scan the joiner's answer, always visible (not gated behind tapping Share first - a host who shares the QR by screenshot or screen-share, rather than the in-app Share button, would otherwise have no way to proceed). The debug-panel toggle lives in `SettingsScreen` now, not on this screen. For the joiner role, it shows the already-generated answer payload and auto-navigates to `InCallScreen` once `CallSession.connectionStatus` reports `connected`.
- `services/qr_export.dart` - renders QR payload bytes to PNG (`QrPainter.withQr` + `QrCode.fromData`, same link-text encoding as the display screen) for the display screen's "Share as image" button.
- `screens/qr_import_screen.dart` - camera scanner (`mobile_scanner`) and gallery import (`image_picker`, hidden on web via `kIsWeb` since `mobile_scanner`'s `analyzeImage` has no web implementation), fully wired to `CallSession`: with no `hostSession` passed in, a decoded offer starts a new `CallSession.acceptOfferAndCreateAnswer()` and navigates to `QrDisplayScreen` (joiner role) with the resulting answer; with a `hostSession` passed in (the host's second step), a decoded answer is fed into `CallSession.applyRemoteAnswer()` and navigates straight to `InCallScreen`. Decodes a detected barcode's `rawValue` text via `qr_link_codec.dart`'s `decodeQrText()` rather than `rawBytes`, for the same cross-platform reason as the display screen. Body is wrapped in `SafeArea` with a fixed 5:2 flex split between the camera preview and the bottom controls, so "Load from device" always gets a guaranteed, comfortable share of the screen instead of being squeezed against the system nav bar.
- `screens/settings_screen.dart` - language picker (system default / English / Русский, via `RadioGroup<AppLocale>`) and the debug-panel toggle (`CheckboxListTile`), both backed by Riverpod providers in `state/settings.dart`. Opened from `widgets/settings_button.dart`, a gear-icon `IconButton` placed in the `AppBar.actions` of every top-level screen.
- `state/settings.dart` - `sharedPreferencesProvider` (the `SharedPreferences` instance loaded in `main()` before `runApp`, injected via `ProviderScope(overrides: …)`), `showDebugPanelProvider` (in-memory only), and `appLocaleProvider`/`AppLocaleNotifier` (persists the chosen `AppLocale` to `shared_preferences` under `app_locale`, restored on the next launch; `AppLocale.system` lets Flutter resolve the device locale itself via `locale => null`).
- `l10n/` - `app_en.arb`/`app_ru.arb` source strings (English is the template `AppLocalizations` is generated from), `l10n.dart` exporting the generated `AppLocalizations` plus a `context.l10n` `BuildContext` extension used throughout instead of hardcoded strings. Generation is driven by `l10n.yaml` and `generate: true` in `pubspec.yaml`, so it runs automatically on `flutter pub get`/`flutter run`.
- `screens/in_call_screen.dart` - local/remote video via `RTCVideoRenderer`/`RTCVideoView`, a connecting/connected/failed status view, a hang-up button (pops back to `HomeScreen`), and an optional debug panel showing live connection status plus the host's and joiner's IP addresses (deduped, from each side's decoded `SignalingPayload` candidates) - controlled by `showDebugPanelProvider`, toggled in `SettingsScreen`. Also watches `connectionStatus` for `disconnected`/`failed`/`closed`: the first time it sees one, it pops back to `HomeScreen` and shows a message via `rootScaffoldMessengerKey` explaining the call ended, rather than leaving the user stranded on a frozen call screen.
- `services/call_session.dart` - `CallSession` class and `CallState` enum matching the state machine in section 5. Fully implemented: orchestrates TURN credentials, the SDP/binary codecs, and the peer connection gateway (see below) through `createOffer()`/`acceptOfferAndCreateAnswer()`/`applyRemoteAnswer()`, all now returning/accepting `Uint8List` (the raw compact payload) instead of `String`. Also checks that a received answer's session id matches the offer it replied to (section 4). Exposes `localStream`/`remoteStream`/`connectionStatus` for the in-call screen, plus `currentConnectionStatus`/`currentRemoteStream` snapshots of the latest known value (see known limitations below for why), and `localPayload`/`remotePayload` (this side's and the other side's decoded signaling payload) for the debug panel.
- `domain/signaling/` - plain-Dart aside from the `MediaStream`/`PeerConnectionStatus` types needed for rendering, fully unit-tested: `signaling_payload.dart` (the section-4 schema as Dart fields), `ice_candidate.dart`, `signaling_codec.dart` (binary encode/decode), `sdp_codec.dart` (hand-written, targeted - not a generic library - SDP ⟷ `SignalingPayload` conversion; hardcodes Opus/VP8 per section 4), `peer_connection_gateway.dart` (the `PeerConnectionGateway` abstraction AGENTS.md names, so `flutter_webrtc`'s `RTCPeerConnection` never has to be imported into domain/service code - only the `MediaStream` data type is referenced, for the video renderers).
- `data/turn/turn_credentials_service.dart` - fetches/decodes the Metered endpoint via `package:http` (injectable `http.Client` for tests).
- `data/webrtc/webrtc_peer_connection_gateway.dart` - the only `PeerConnectionGateway` implementation: wraps `flutter_webrtc`'s `RTCPeerConnection`, requests camera/mic permissions before `getUserMedia`, drives non-trickle ICE gathering (waits for `RTCIceGatheringStateComplete`, with a 15s timeout so a dead TURN server can't hang the UI), and exposes the local stream plus a broadcast stream of the remote track's `MediaStream` (via `onTrack`) alongside a `currentRemoteStream` getter holding the latest one received.
- `services/qr_payload_router.dart` - `handleDecodedQrPayload()`, the offer-vs-answer branching from section 5 (start a new joiner `CallSession` for an offer, or `applyRemoteAnswer()` on a supplied host session for an answer) extracted so both `QrImportScreen`'s in-app scanner/gallery import and the share-target listener below funnel through the same logic instead of duplicating it.
- `services/pending_host_session.dart` - `PendingHostSession.current`, a single nullable static reference to whichever host `CallSession` is currently waiting on an answer QR (set/cleared by `QrDisplayScreen`). A raw decoded payload doesn't carry which call it replies to, so the share-target listener needs this to tell "this shared image is the answer to the call I have open" apart from "this shared image is a fresh offer."
- `services/shared_qr_intent_listener.dart` - wraps `HomeScreen` in `main.dart`; via `share_handler`, listens for a QR image shared in from another app's share sheet (`getInitialSharedMedia()` for a cold start, `sharedMediaStream` while running), decodes it with a `MobileScannerController.analyzeImage()` static analysis pass (same decode path as `QrImportScreen`'s gallery import), and routes it through `qr_payload_router.dart`.
- `services/qr_link_codec.dart` - `buildShareLink()`/`decodeShareLink()`, converting a payload to/from a `vcallme://call?d=<base64url>` `Uri` - the same bytes the QR code carries, just base64url-in-a-URI instead of pixels. Unit-tested (`test/services/qr_link_codec_test.dart`).
- `services/deep_link_listener.dart` - wraps `HomeScreen` in `main.dart` (nested inside `shared_qr_intent_listener.dart`'s wrapper); via `app_links`' `AppLinks().uriLinkStream` (delivers both the cold-start link and every subsequent one through one subscription), decodes any `vcallme://call` link with `qr_link_codec.dart` and routes it through `qr_payload_router.dart` - no scanning, gallery picking, or share-sheet app-picker step at all.

**Known limitations of the current implementation**:
- Modern Android WebRTC hides host ICE candidates behind mDNS `.local` hostnames by default; `sdp_codec.dart`'s `extractFromSdp` skips any candidate whose address isn't a literal IPv4 dotted-quad (so mDNS host candidates, and any IPv6 candidates, are silently dropped - connectivity falls back to the srflx/relay candidates, which are unaffected). It also skips any `127.0.0.0/8` loopback host candidate (libwebrtc sometimes enumerates one), since a loopback address is only ever meaningful to whichever device it came from and is never useful to send to the other side.
- `connectionStatus`/`remoteStream` are broadcast streams with no replay of past events. A screen that subscribes late (e.g. after an `await`) could otherwise miss an event that already fired - notably the very "connected" transition that triggered its own navigation - and get stuck showing "Connecting…" forever even once actually connected. Fixed by seeding from `currentConnectionStatus`/`currentRemoteStream` synchronously before subscribing, rather than relying solely on the next stream event.
- Android's `ACTION_SEND` `EXTRA_SUBJECT` (`ShareParams.subject`) is meant as an email-style subject line, but some share targets - notably Google Drive's "Save to Drive" - use it as the saved file's name instead of the file's actual name when saving directly from the share sheet. `qr_display_screen.dart`'s share button no longer sets a subject, so shared QR images keep their intended filename (`call-offer.png` / `call-answer.png`) everywhere.
- Navigation is a plain forward `Navigator.push` chain with no `WillPopScope` guard, so backing out mid-call lands on the previous QR screen rather than confirming an intentional hang-up; the hang-up button itself correctly pops back to `HomeScreen`.
- The share-target listener (`shared_qr_intent_listener.dart`) only tracks one pending host session at a time via `PendingHostSession.current`; if a user somehow has two host `QrDisplayScreen`s open at once (not reachable through normal navigation today), a shared answer image would be applied to whichever one is currently on top.

**Store-prep done**: release signing (upload keystore + gitignored `android/key.properties`), custom launcher icon, real application ID/namespace `dev.podgaev.v_call_me`, and store listing assets (`store/feature_graphic.png`, `store/screenshots/`).

**Verified working**: `flutter analyze` and `flutter test` pass (unit tests for the binary/SDP codecs, the TURN credentials service against a mocked HTTP client, `CallSession`'s state machine against a fake gateway - including a full host↔joiner offer/answer round trip through the real codecs - the `QrDisplayScreen` widget tests, and the `qr_link_codec.dart` round-trip tests covering the QR's `rawValue` text decoding); `flutter build apk --debug` succeeds end-to-end on Android. Manually exercised on an emulator + a real Pixel 6 Pro over wireless `adb`: offer/answer QR generation and scanning, the debug panel, the disconnect-handling message, and the QR-import layout fix all behave as intended.

**Not yet manually verified**: the web build (`flutter build web` / `flutter run -d chrome`) in an actual browser - `flutter analyze`/`flutter test` pass with the web platform enabled and the `kIsWeb` gates in place, but it hasn't been exercised end-to-end in a browser yet (camera QR scanning, the `vcallme://` link, and the settings screen in particular).

## 10. Open questions / next steps

- **Manually verify two real peers connect over their own separate networks (not just emulator + one phone on the same LAN)** - this is the last step before the app is ready for real use. Everything else (signaling, QR handshake, in-call UI, disconnect handling) is implemented and has been exercised on an emulator and a real device; what's unverified is a genuine two-real-device call end-to-end, ideally with the two phones on different networks (e.g. one on cellular) so a same-NAT hairpin quirk can't mask a real P2P/TURN problem.
- **Manually verify the share-target flow on a real device** - `flutter analyze`/`flutter test`/`flutter build apk --debug` all pass with `share_handler` wired in, but the actual "share a QR photo from Telegram/SMS and pick this app" path hasn't been exercised on a real device yet.
- **Manually verify the `vcallme://` link flow on a real device** - same caveat as above for `app_links`: analyze/test/build all pass, but tapping a `vcallme://call?d=...` link from inside a real messaging app (cold start and warm start) hasn't been exercised on a real device yet.
- **Manually verify the web build in a real browser** - `flutter build web`/`flutter run -d chrome` are wired in and analyze/test pass, but camera QR scanning, the `vcallme://` link (which has no OS-level handler on web - it'd need to be opened by pasting/navigating to it directly, or a future web-specific share flow), and the settings screen haven't been exercised in an actual browser yet.
- Application ID / namespace: **done** — set to `dev.podgaev.v_call_me` (matches the Google Play Console listing).
- Release signing: **done** — upload keystore wired via gitignored `android/key.properties`; `flutter build appbundle --release` yields an AAB signed with the upload key.
- Distribution plan for the other side given potential Play Store restrictions (sideloaded APK vs. store listing).