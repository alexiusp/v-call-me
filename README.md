# v_call_me

**A serverless, block-resistant video calling app to stay in touch with family or friends — built for reaching loved ones in regions where mainstream apps get throttled or blocked.**

![Platform](https://img.shields.io/badge/platform-Android-3DDC84)
![Flutter](https://img.shields.io/badge/Flutter-3.44.5-02569B)
![Status](https://img.shields.io/badge/status-early%20development-orange)

A single Flutter app where both participants use the same build — one takes the **host** role, the other the **joiner** role, chosen at runtime. There is **no signaling server**: the call is set up by exchanging QR codes manually through whatever messaging channel still works (Telegram, SMS, email, …), and the media itself flows peer-to-peer over WebRTC.

> ℹ️ This is a personal project under active development. The full call flow works end-to-end and has been exercised on an emulator + a real device, but it has **not yet been verified between two real devices on their own separate networks** - that's the last step before sharing this with family. See [Status](#status) before relying on it.

---

## Table of contents

- [Why this exists](#why-this-exists)
- [How it works](#how-it-works)
- [Status](#status)
- [Tech stack](#tech-stack)
- [Getting started](#getting-started)
- [Project structure](#project-structure)
- [Development](#development)
- [Security](#security)
- [Documentation](#documentation)

---

## Why this exists

Mainstream calling apps (WhatsApp, Telegram calls, etc.) are increasingly throttled or blocked in some regions — not just at the app-store or domain level, but via **deep packet inspection (DPI)** that recognizes VoIP/RTP traffic patterns. The goal of this app is a call that survives that environment:

- **No central signaling server** to block or subpoena. Call setup happens out-of-band via QR images the users share themselves.
- **Peer-to-peer media** by default, with a TURN relay only as a fallback for difficult NATs — the relay never sees call content or setup metadata.
- **End-to-end encrypted media** by default (WebRTC's DTLS-SRTP), so passive interception of call content is not the primary risk — blocking and throttling are.

The full threat model and design rationale live in [`DESIGN.md`](DESIGN.md).

## How it works

Setting up a call is a two-message handshake carried entirely by QR codes:

```
        Host phone                                 Joiner phone
     (starts the call)                          (answers the call)
            |                                           |
            | 1. createOffer()                          |
            |    gather ICE (STUN / TURN)               |
            |                                           |
            |  ==== offer QR — shared via any app ===>  |
            |                                           | 2. scan / import offer
            |                                           |    create answer + gather ICE
            |  <=== answer QR — shared back ==========  |
            | 3. applyRemoteAnswer()                    |
            |                                           |
            |====== encrypted WebRTC media (P2P) =======|
                     (TURN relay only if direct P2P fails)
```

A few design choices make the single-QR-per-step handshake possible:

- **Compact binary payload, not raw SDP.** Raw WebRTC SDP is 2–5 KB and produces a dense, fragile QR code that messaging-app recompression can break. Instead, only the fields that vary per call (ICE credentials, DTLS fingerprint, a handful of candidates) are packed into a ~90–150 byte custom binary format, and a full valid SDP is reconstructed from a fixed template on the receiving side. This keeps the QR at a low density with 30% error-correction redundancy. See [`DESIGN.md` §4](DESIGN.md).
- **Non-trickle ICE.** Each side waits for full ICE gathering (including a pre-allocated TURN relay candidate) *before* generating its QR, so the whole offer or answer collapses into one static code instead of a live back-and-forth.
- **Hardcoded codecs** (Opus audio / VP8 video) so no codec lists need to be transmitted at all.

The only always-on infrastructure is a **STUN/TURN server** for NAT traversal and media relay fallback — currently a free [Metered / Open Relay](https://www.metered.ca/tools/openrelay/) tier, with self-hosting `coturn` as a documented fallback.

## Status

Early development, **Android-only**, but functionally complete: the signaling core, QR scan/display, in-call UI, and disconnect handling are all wired end-to-end and have been manually exercised on an emulator + a real Pixel device. The one thing still outstanding is a genuine two-real-device call — once that's verified, this is ready for real use.

**Implemented**
- ✅ Compact binary signaling codec (offer/answer encode/decode) — unit-tested
- ✅ Template-based SDP ⟷ payload conversion (hardcoded Opus/VP8) — unit-tested
- ✅ `CallSession` state machine for both host and joiner roles — unit-tested against a fake gateway, including a full host↔joiner round trip
- ✅ WebRTC adapter (`flutter_webrtc`) with camera/mic permission handling and non-trickle ICE gathering (with timeout)
- ✅ TURN credentials service (fetches Metered / Open Relay `iceServers`)
- ✅ QR **display + "share as file"** (raw byte-mode QR at error-correction level H)
- ✅ QR **scanning / import** (camera + gallery via `mobile_scanner`/`image_picker`), wired to `CallSession.acceptOfferAndCreateAnswer()` / `applyRemoteAnswer()`, with a layout that keeps "Load from device" comfortably visible on every device
- ✅ Full navigation from Home through QR display/import to the in-call screen, for both roles
- ✅ In-call screen: local/remote video (`RTCVideoRenderer`), connecting/connected/failed states, hang-up button
- ✅ Automatic return to Home with an explanatory message if the other side disconnects, fails, or closes the connection mid-call
- ✅ Host-only debug panel (toggled via a checkbox on the offer QR screen) showing live connection status and the host's/joiner's IP addresses (from each side's decoded QR payload)
- ✅ Android manifest, permissions, and toolchain fully wired; `flutter build apk --debug` succeeds
- ✅ Store-prep: application ID `dev.podgaev.v_call_me`, custom launcher icon, and release signing (upload keystore via gitignored `key.properties`) — `flutter build appbundle --release` produces a signed AAB

**Not yet implemented / verified**
- ⏳ **Two real devices on their own separate networks, end-to-end** — the highest-priority remaining step. Exercised so far on an emulator + one real device on the same network; a genuine two-phone test (ideally with one on cellular data) is what's left before relying on it for real calls.

See [`DESIGN.md` §9–10](DESIGN.md) for the detailed implementation snapshot and open questions.

## Tech stack

| Area | Choice |
| --- | --- |
| Framework | Flutter 3.44.5 (stable) / Dart |
| Real-time media | [`flutter_webrtc`](https://pub.dev/packages/flutter_webrtc) |
| QR generation | [`qr_flutter`](https://pub.dev/packages/qr_flutter) |
| QR / camera scanning | [`mobile_scanner`](https://pub.dev/packages/mobile_scanner) |
| Permissions | [`permission_handler`](https://pub.dev/packages/permission_handler) |
| Sharing / image picking | [`share_plus`](https://pub.dev/packages/share_plus), [`image_picker`](https://pub.dev/packages/image_picker) |
| TURN credentials | [`http`](https://pub.dev/packages/http) |
| NAT traversal / relay | STUN + TURN (Metered / Open Relay; `coturn` self-host as fallback) |

## Getting started

### Prerequisites

- **Flutter 3.44.5 (stable)** or newer — `flutter --version` to check, `flutter upgrade` if stale.
- **Android SDK** with an emulator or a physical device (resolves to compileSdk 36, minSdk 24, NDK 28.2.13676358 via Flutter defaults).
- A free **Metered / Open Relay API key** from <https://www.metered.ca/tools/openrelay/>.

### Setup

```bash
git clone <repo-url>
cd v-call-me

# Provide your TURN credentials (turn_config.dart is gitignored)
cp lib/config/turn_config.example.dart lib/config/turn_config.dart
# then edit lib/config/turn_config.dart and paste your Metered API key
#   (on Windows PowerShell: Copy-Item lib/config/turn_config.example.dart lib/config/turn_config.dart)

flutter pub get
```

### Run

```bash
flutter run -d <device-id>     # e.g. flutter run -d emulator-5554
```

To try the full handshake you currently need **two** running instances (two devices/emulators) taking the host and joiner roles — though end-to-end connection is not yet verified (see [Status](#status)).

## Project structure

The code follows a light clean-architecture split (see [`AGENTS.md`](AGENTS.md) for the rationale and conventions):

```
lib/
├── main.dart                     # App entry point (VCallMeApp) -> HomeScreen
├── config/
│   ├── turn_config.example.dart  # Template — copy to turn_config.dart (gitignored)
│   └── turn_config.dart          # Your real Metered API key (not committed)
├── domain/signaling/             # Plain Dart, no Flutter imports, fully unit-tested
│   ├── signaling_payload.dart    #   the DESIGN §4 compact schema as Dart fields
│   ├── ice_candidate.dart
│   ├── signaling_codec.dart      #   binary encode/decode
│   ├── sdp_codec.dart            #   template-based SDP <-> payload (Opus/VP8)
│   └── peer_connection_gateway.dart  # abstraction so flutter_webrtc stays out of domain
├── data/
│   ├── webrtc/                   # flutter_webrtc adapter (the only gateway impl)
│   └── turn/                     # Metered / Open Relay credentials service
├── services/
│   ├── call_session.dart         # CallSession orchestrator + CallState machine
│   └── qr_export.dart            # payload bytes -> PNG for sharing
└── screens/
    ├── home_screen.dart          # "Start a call" / "Join a call" + CallRole enum
    ├── qr_display_screen.dart    # renders + shares the offer/answer QR; host debug-panel checkbox
    ├── qr_import_screen.dart     # camera/gallery scan -> CallSession -> next screen
    └── in_call_screen.dart       # video renderers, controls, host-only debug panel

test/                             # Unit + widget tests mirroring lib/
```

## Development

```bash
flutter pub get
flutter analyze                   # keep clean (flutter_lints)
flutter test                      # unit + widget tests
flutter build apk --debug         # full Android build
```

`flutter analyze` and `flutter test` alone won't catch Gradle-level SDK/NDK/manifest mismatches — run an actual `flutter build apk --debug` for anything touching Android build config. Toolchain pins (AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14.5) and Windows-specific build gotchas are documented in [`AGENTS.md`](AGENTS.md).

## Security

- **Media is end-to-end encrypted** via WebRTC's built-in DTLS-SRTP — this is default behavior, not something bolted on.
- **The QR payload does not need to be secret** for call confidentiality; it can be sent in the clear over any channel. Its only sensitivity is that whoever holds it can attempt to join that specific call.
- The TURN relay only forwards already-encrypted media and never sees call setup metadata.

More detail — including optional DTLS-fingerprint verification — in [`DESIGN.md` §8](DESIGN.md).

## Documentation

- **[`DESIGN.md`](DESIGN.md)** — product goal, threat model, QR payload schema, call state machine, and implementation status. Start here to understand *why* the app is built this way.
- **[`AGENTS.md`](AGENTS.md)** — code organization, Dart/Flutter conventions, toolchain versions, and dev-environment gotchas. Start here before contributing code.
