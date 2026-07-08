# Family video call app � design doc

## 1. Goal

A video calling app to stay in touch with parents in Russia, resilient to the government blocking or throttling mainstream apps (WhatsApp, Telegram calls, etc.). Single Flutter app, Android-first, used by both sides � "host" and "joiner" are roles within the same app, not separate apps.

## 2. Threat model / constraints

- Mainstream apps may be blocked at the domain/app-store level, and calls specifically are increasingly throttled or blocked via **deep packet inspection (DPI)** that recognizes VoIP/RTP traffic patterns � not just app-specific blocking. This means "no central server" alone doesn't guarantee the call survives; traffic *pattern* matters as much as traffic *destination*.
- WebRTC media is encrypted by default (DTLS-SRTP), so passive interception of call content isn't the primary risk � blocking/throttling is.
- No willingness to run a persistent signaling server. Signaling (the offer/answer exchange) is done **manually**, via QR code images shared through whatever messaging channel currently works (Telegram, SMS, email, etc.).
- A lightweight, non-signaling piece of infrastructure (STUN/TURN) is acceptable, since it never sees call content or call setup metadata � it only helps with NAT traversal and relays already-encrypted media as a fallback.

## 3. High-level architecture

Three logical components, no signaling server:

- **STUN + TURN relay** � used by both phones for NAT traversal (STUN) and as a fallback relay if a direct peer-to-peer path can't be established (TURN). Free tiers (Open Relay Project, Metered.ca) are sufficient for development and likely for this app's actual low-volume usage; self-hosting `coturn` on a cheap VPS is a fallback if more control or bandwidth is needed later.
- **Your phone (host role)** � starts the call, generates the offer.
- **Parents' phone (joiner role)** � receives the offer via QR/file, generates the answer.

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

## 9. Implementation status (as of 2026-07-08)

Flutter project scaffolded, Android-only, package `v_call_me`, org `com.example` (placeholder). See `AGENTS.md` for the target code architecture and dev environment notes.

**Dependencies wired in** (`pubspec.yaml`): `flutter_webrtc`, `qr_flutter`, `mobile_scanner`, `permission_handler`, `share_plus`, `image_picker`.

**Android manifest** (`android/app/src/main/AndroidManifest.xml`): camera, microphone, internet, network-state, and Bluetooth permissions declared, plus camera/microphone `<uses-feature>` entries.

**Toolchain**: Flutter 3.44.5 (stable), AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14.5. `compileSdk`/`minSdk`/NDK are left as Flutter's own defaults (currently 36 / 24 / 28.2.13676358) rather than hardcoded, so they track future Flutter upgrades automatically.

**Code** (all under `lib/`, flat structure so far - screens + one service):
- `main.dart` - app entry point (`VCallMeApp`), routes to `HomeScreen`.
- `screens/home_screen.dart` - "Start a call" / "Join a call" buttons; navigates to `QrDisplayScreen` / `QrImportScreen`. Also defines the shared `CallRole` enum (host/joiner).
- `screens/qr_display_screen.dart` - placeholder screen; takes a `CallRole` and optional payload string, but doesn't render a QR code yet (`qr_flutter` not wired in).
- `screens/qr_import_screen.dart` - placeholder screen; no camera scan or gallery import wired in yet (`mobile_scanner` / `image_picker` not wired in).
- `screens/in_call_screen.dart` - placeholder screen; not yet reachable from navigation.
- `services/call_session.dart` - `CallSession` class and `CallState` enum matching the state machine in section 5; `createOffer()`, `acceptOfferAndCreateAnswer()`, `applyRemoteAnswer()` all currently throw `UnimplementedError()`. No `flutter_webrtc` `RTCPeerConnection` wiring yet.

**Not implemented yet**: SDP compact-payload encode/decode (section 4), actual `RTCPeerConnection`/ICE gathering logic, QR generation/scanning, TURN/STUN credential configuration, navigation from the QR screens through to `InCallScreen`, release signing config.

**Verified working**: `flutter analyze` and `flutter test` pass on the current stub code; `flutter build apk --debug` succeeds end-to-end on Android (produces a working `app-debug.apk`).

## 10. Open questions / next steps

- SDP reconstruction template - building a valid offer/answer string from the compact schema fields, and wiring `CallSession` to `flutter_webrtc`'s `RTCPeerConnection`.
- QR generation/scanning implementation using the already-added `qr_flutter` / `mobile_scanner` packages.
- TURN/STUN server credentials and configuration (free tier vs. self-hosted `coturn`).
- Real application ID / namespace (currently placeholder `com.example.v_call_me`).
- Release signing configuration (release builds are currently debug-signed).
- Distribution plan for the parents' side given potential Play Store restrictions (sideloaded APK vs. store listing).