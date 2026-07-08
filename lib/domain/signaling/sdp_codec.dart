import 'dart:typed_data';

import 'ice_candidate.dart';
import 'signaling_codec.dart' show signalingSchemaVersion;
import 'signaling_payload.dart';

/// Converts between a [SignalingPayload] and full SDP offer/answer text.
///
/// Per DESIGN.md section 4, codecs are hardcoded (Opus for audio, VP8 for
/// video) rather than negotiated, so [buildSdp] only ever needs to emit a
/// fixed template with the per-call fields (ICE credentials, DTLS
/// fingerprint, candidates) substituted in. [extractFromSdp] is the reverse:
/// pulling those same per-call fields back out of a real SDP that
/// `flutter_webrtc` generated locally, ready to be encoded into the compact
/// binary payload by `signaling_codec.dart`.
const _audioPayloadType = 111;
const _videoPayloadType = 96;

enum _MediaKind { audio, video }

/// Builds a full SDP offer (or answer) string that a real `RTCPeerConnection`
/// will accept via `setRemoteDescription`, reconstructed from the compact
/// fields DESIGN.md section 4 actually transmits.
String buildSdp(SignalingPayload payload) {
  final sections = [
    if (payload.hasAudio) _MediaKind.audio,
    if (payload.hasVideo) _MediaKind.video,
  ];
  if (sections.isEmpty) {
    throw ArgumentError('SignalingPayload has neither audio nor video');
  }

  // The offerer always proposes actpass; a real answerer always resolves
  // that to active (becomes the DTLS client) - this mirrors libwebrtc's own
  // convention, since the payload we reconstruct here always stands in for
  // *someone else's* real SDP.
  final setupRole = payload.isAnswer ? 'active' : 'actpass';
  final fingerprintHex = payload.dtlsFingerprint
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
  // Session id in the o= line doesn't need to be globally unique (we never
  // renegotiate), just present; derive it from the session id bytes so it's
  // at least call-specific rather than a constant.
  final originId = payload.sessionId.fold<int>(0, (acc, b) => acc * 256 + b);

  final lines = <String>[
    'v=0',
    'o=- $originId 2 IN IP4 127.0.0.1',
    's=-',
    't=0 0',
    'a=group:BUNDLE ${List.generate(sections.length, (i) => i).join(' ')}',
    'a=msid-semantic: WMS *',
  ];

  for (var i = 0; i < sections.length; i++) {
    final kind = sections[i];
    final payloadType =
        kind == _MediaKind.audio ? _audioPayloadType : _videoPayloadType;
    lines.addAll([
      kind == _MediaKind.audio
          ? 'm=audio 9 UDP/TLS/RTP/SAVPF $payloadType'
          : 'm=video 9 UDP/TLS/RTP/SAVPF $payloadType',
      'c=IN IP4 0.0.0.0',
      'a=rtcp:9 IN IP4 0.0.0.0',
      'a=ice-ufrag:${payload.iceUfrag}',
      'a=ice-pwd:${payload.icePwd}',
      'a=fingerprint:sha-256 $fingerprintHex',
      'a=setup:$setupRole',
      'a=mid:$i',
      'a=sendrecv',
      'a=rtcp-mux',
      kind == _MediaKind.audio
          ? 'a=rtpmap:$payloadType opus/48000/2'
          : 'a=rtpmap:$payloadType VP8/90000',
      if (kind == _MediaKind.audio)
        'a=fmtp:$payloadType minptime=10;useinbandfec=1',
      if (kind == _MediaKind.video) 'a=rtcp-fb:$payloadType goog-remb',
      if (kind == _MediaKind.video) 'a=rtcp-fb:$payloadType nack',
      ..._candidateLines(payload.candidates),
      'a=end-of-candidates',
    ]);
  }

  return '${lines.join('\r\n')}\r\n';
}

List<String> _candidateLines(List<IceCandidateInfo> candidates) {
  final seenOfType = <CandidateType, int>{};
  final lines = <String>[];
  for (final candidate in candidates) {
    final localPreference = 65535 - (seenOfType[candidate.type] ?? 0);
    seenOfType[candidate.type] = (seenOfType[candidate.type] ?? 0) + 1;

    // RFC 8445 recommended priority formula; foundation/priority are
    // regenerated locally rather than transmitted, per DESIGN.md section 4.
    final typePreference = switch (candidate.type) {
      CandidateType.host => 126,
      CandidateType.srflx => 100,
      CandidateType.relay => 0,
    };
    const component = 1; // rtcp-mux is always on in our template.
    final priority =
        (typePreference << 24) | (localPreference << 8) | (256 - component);
    final transport =
        candidate.transport == CandidateTransport.udp ? 'udp' : 'tcp';
    final typeStr = switch (candidate.type) {
      CandidateType.host => 'host',
      CandidateType.srflx => 'srflx',
      CandidateType.relay => 'relay',
    };
    final foundation = '$typeStr${candidate.transport.name}${lines.length}';
    lines.add(
      'a=candidate:$foundation $component $transport $priority '
      '${candidate.ip} ${candidate.port} typ $typeStr generation 0',
    );
  }
  return lines;
}

/// Extracts the compact-payload fields out of a real local SDP (offer or
/// answer) that `flutter_webrtc` generated, once ICE gathering is complete.
///
/// [sessionId] is supplied by the caller ([CallSession]) rather than parsed
/// from the SDP - it isn't an SDP concept at all, it's this app's own
/// out-of-band correlation id (DESIGN.md section 4).
///
/// Known limitation: modern Android WebRTC hides host candidates behind
/// mDNS `.local` hostnames by default for privacy. Those (and any IPv6
/// candidates) don't fit the 4-byte IPv4 candidate slot and are silently
/// skipped here - connectivity falls back to the srflx/relay candidates.
SignalingPayload extractFromSdp(
  String sdp, {
  required bool isAnswer,
  required Uint8List sessionId,
}) {
  final ufragMatch = RegExp(r'^a=ice-ufrag:(.+)$', multiLine: true).firstMatch(sdp);
  final pwdMatch = RegExp(r'^a=ice-pwd:(.+)$', multiLine: true).firstMatch(sdp);
  final fingerprintMatch =
      RegExp(r'^a=fingerprint:sha-256 (.+)$', multiLine: true).firstMatch(sdp);
  if (ufragMatch == null || pwdMatch == null || fingerprintMatch == null) {
    throw const FormatException(
        'SDP is missing a=ice-ufrag / a=ice-pwd / a=fingerprint:sha-256');
  }

  final iceUfrag = ufragMatch.group(1)!.trim();
  final icePwd = pwdMatch.group(1)!.trim();
  final fingerprintHex = fingerprintMatch.group(1)!.trim();
  final dtlsFingerprint = Uint8List.fromList(
    fingerprintHex.split(':').map((h) => int.parse(h, radix: 16)).toList(),
  );
  if (dtlsFingerprint.length != 32) {
    throw FormatException(
        'Expected a 32-byte sha-256 fingerprint, got ${dtlsFingerprint.length} bytes');
  }

  return SignalingPayload(
    schemaVersion: signalingSchemaVersion,
    hasAudio: _mLineActive(sdp, 'audio'),
    hasVideo: _mLineActive(sdp, 'video'),
    isAnswer: isAnswer,
    sessionId: sessionId,
    iceUfrag: iceUfrag,
    icePwd: icePwd,
    dtlsFingerprint: dtlsFingerprint,
    candidates: _extractCandidates(sdp),
  );
}

bool _mLineActive(String sdp, String kind) {
  final match = RegExp('^m=$kind\\s+(\\d+)', multiLine: true).firstMatch(sdp);
  if (match == null) return false;
  return match.group(1) != '0';
}

final _candidateLineRegex = RegExp(
  r'^a=candidate:\S+ (\d+) (udp|tcp) \d+ (\S+) (\d+) typ (host|srflx|relay)',
  multiLine: true,
  caseSensitive: false,
);

final _ipv4Regex = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

List<IceCandidateInfo> _extractCandidates(String sdp) {
  final seen = <String>{};
  final result = <IceCandidateInfo>[];
  for (final match in _candidateLineRegex.allMatches(sdp)) {
    if (match.group(1) != '1') continue; // RTP component only (rtcp-mux).

    final ip = match.group(3)!;
    if (!_isIpv4(ip)) continue; // mDNS hostname or IPv6 - see doc comment.

    final type = switch (match.group(5)!.toLowerCase()) {
      'host' => CandidateType.host,
      'srflx' => CandidateType.srflx,
      'relay' => CandidateType.relay,
      _ => null,
    };
    if (type == null) continue;
    final transport =
        match.group(2)!.toLowerCase() == 'udp' ? CandidateTransport.udp : CandidateTransport.tcp;
    final port = int.parse(match.group(4)!);

    final key = '$type|$transport|$ip|$port';
    if (!seen.add(key)) continue; // dedupe candidates repeated per bundled m= line.

    result.add(IceCandidateInfo(type: type, transport: transport, ip: ip, port: port));
  }
  return result;
}

bool _isIpv4(String value) {
  final match = _ipv4Regex.firstMatch(value);
  if (match == null) return false;
  for (var i = 1; i <= 4; i++) {
    if (int.parse(match.group(i)!) > 255) return false;
  }
  return true;
}
