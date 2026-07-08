import 'dart:typed_data';

import 'ice_candidate.dart';

/// The compact payload schema from DESIGN.md section 4, as plain Dart
/// fields. This is what gets encoded to/from the bytes that actually travel
/// through the QR code (see `signaling_codec.dart`), and to/from a
/// reconstructed SDP offer/answer (see `sdp_codec.dart`).
class SignalingPayload {
  const SignalingPayload({
    required this.schemaVersion,
    required this.hasAudio,
    required this.hasVideo,
    required this.isAnswer,
    required this.sessionId,
    required this.iceUfrag,
    required this.icePwd,
    required this.dtlsFingerprint,
    required this.candidates,
  })  : assert(sessionId.length == 6, 'sessionId must be 6 bytes'),
        assert(
          dtlsFingerprint.length == 32,
          'dtlsFingerprint must be 32 bytes (sha-256)',
        );

  final int schemaVersion;
  final bool hasAudio;
  final bool hasVideo;
  final bool isAnswer;

  /// 6 random bytes. The host generates this when creating an offer; the
  /// joiner's answer echoes it back so the host can sanity-check the answer
  /// actually replies to the offer it sent.
  final Uint8List sessionId;

  final String iceUfrag;
  final String icePwd;

  /// Raw sha-256 DTLS certificate fingerprint (32 bytes), not hex text.
  final Uint8List dtlsFingerprint;

  final List<IceCandidateInfo> candidates;

  @override
  bool operator ==(Object other) =>
      other is SignalingPayload &&
      other.schemaVersion == schemaVersion &&
      other.hasAudio == hasAudio &&
      other.hasVideo == hasVideo &&
      other.isAnswer == isAnswer &&
      _bytesEqual(other.sessionId, sessionId) &&
      other.iceUfrag == iceUfrag &&
      other.icePwd == icePwd &&
      _bytesEqual(other.dtlsFingerprint, dtlsFingerprint) &&
      _candidatesEqual(other.candidates, candidates);

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        hasAudio,
        hasVideo,
        isAnswer,
        iceUfrag,
        icePwd,
        candidates.length,
      );

  @override
  String toString() =>
      'SignalingPayload(schemaVersion: $schemaVersion, hasAudio: $hasAudio, '
      'hasVideo: $hasVideo, isAnswer: $isAnswer, iceUfrag: $iceUfrag, '
      'candidates: $candidates)';
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _candidatesEqual(List<IceCandidateInfo> a, List<IceCandidateInfo> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
