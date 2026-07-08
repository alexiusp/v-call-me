import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:v_call_me/domain/signaling/ice_candidate.dart';
import 'package:v_call_me/domain/signaling/sdp_codec.dart';
import 'package:v_call_me/domain/signaling/signaling_codec.dart';
import 'package:v_call_me/domain/signaling/signaling_payload.dart';

SignalingPayload _samplePayload({bool isAnswer = false}) {
  return SignalingPayload(
    schemaVersion: signalingSchemaVersion,
    hasAudio: true,
    hasVideo: true,
    isAnswer: isAnswer,
    sessionId: Uint8List.fromList([9, 8, 7, 6, 5, 4]),
    iceUfrag: 'a1b2',
    icePwd: 'thisisasecretpassword12',
    dtlsFingerprint: Uint8List.fromList(List.generate(32, (i) => (i * 11 + 3) % 256)),
    candidates: const [
      IceCandidateInfo(
        type: CandidateType.host,
        transport: CandidateTransport.udp,
        ip: '192.168.1.5',
        port: 54321,
      ),
      IceCandidateInfo(
        type: CandidateType.srflx,
        transport: CandidateTransport.udp,
        ip: '203.0.113.7',
        port: 40000,
      ),
      IceCandidateInfo(
        type: CandidateType.relay,
        transport: CandidateTransport.tcp,
        ip: '198.51.100.42',
        port: 443,
      ),
    ],
  );
}

void main() {
  group('buildSdp', () {
    test('produces a valid-looking offer SDP with both m-lines', () {
      final sdp = buildSdp(_samplePayload());

      expect(sdp, contains('a=group:BUNDLE 0 1'));
      expect(sdp, contains('m=audio 9 UDP/TLS/RTP/SAVPF 111'));
      expect(sdp, contains('m=video 9 UDP/TLS/RTP/SAVPF 96'));
      expect(sdp, contains('a=rtpmap:111 opus/48000/2'));
      expect(sdp, contains('a=rtpmap:96 VP8/90000'));
      expect(sdp, contains('a=ice-ufrag:a1b2'));
      expect(sdp, contains('a=ice-pwd:thisisasecretpassword12'));
      expect(sdp, contains('a=setup:actpass'));
      expect(sdp, contains('a=candidate:'));
      expect(sdp, contains('typ host'));
      expect(sdp, contains('typ srflx'));
      expect(sdp, contains('typ relay'));
      expect(sdp.endsWith('\r\n'), isTrue);
    });

    test('uses setup:active for an answer', () {
      final sdp = buildSdp(_samplePayload(isAnswer: true));
      expect(sdp, contains('a=setup:active'));
      expect(sdp, isNot(contains('a=setup:actpass')));
    });

    test('emits only the audio m-line when video is absent', () {
      final payload = SignalingPayload(
        schemaVersion: signalingSchemaVersion,
        hasAudio: true,
        hasVideo: false,
        isAnswer: false,
        sessionId: Uint8List(6),
        iceUfrag: 'x',
        icePwd: 'y',
        dtlsFingerprint: Uint8List(32),
        candidates: const [],
      );
      final sdp = buildSdp(payload);
      expect(sdp, contains('m=audio'));
      expect(sdp, isNot(contains('m=video')));
      expect(sdp, contains('a=group:BUNDLE 0'));
    });

    test('throws when neither audio nor video is present', () {
      final payload = SignalingPayload(
        schemaVersion: signalingSchemaVersion,
        hasAudio: false,
        hasVideo: false,
        isAnswer: false,
        sessionId: Uint8List(6),
        iceUfrag: 'x',
        icePwd: 'y',
        dtlsFingerprint: Uint8List(32),
        candidates: const [],
      );
      expect(() => buildSdp(payload), throwsArgumentError);
    });
  });

  group('extractFromSdp', () {
    test('recovers ufrag/pwd/fingerprint/candidates from its own buildSdp output', () {
      final original = _samplePayload();
      final sdp = buildSdp(original);
      final sessionId = Uint8List.fromList([1, 1, 1, 1, 1, 1]);

      final extracted = extractFromSdp(sdp, isAnswer: false, sessionId: sessionId);

      expect(extracted.iceUfrag, original.iceUfrag);
      expect(extracted.icePwd, original.icePwd);
      expect(extracted.dtlsFingerprint, original.dtlsFingerprint);
      expect(extracted.hasAudio, isTrue);
      expect(extracted.hasVideo, isTrue);
      expect(extracted.isAnswer, isFalse);
      expect(extracted.sessionId, sessionId);
      expect(extracted.candidates.toSet(), original.candidates.toSet());
    });

    test('parses a realistic libwebrtc-style bundled offer, dedupes repeated candidates, '
        'and skips mDNS/IPv6/loopback candidates', () {
      const sdp = 'v=0\r\n'
          'o=- 4611731400430051336 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'a=group:BUNDLE 0 1\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=rtcp:9 IN IP4 0.0.0.0\r\n'
          'a=ice-ufrag:4ZcD\r\n'
          'a=ice-pwd:2/1muCWoOi3uLifh0NuRlDNj\r\n'
          'a=fingerprint:sha-256 4A:AD:B9:B1:3F:82:18:3B:54:02:12:DF:3E:5D:49:6B:'
          '19:E5:7C:AB:3A:47:99:19:5B:D0:81:CE:E4:1D:5B:5A\r\n'
          'a=setup:actpass\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'a=rtcp-mux\r\n'
          'a=rtpmap:111 opus/48000/2\r\n'
          'a=candidate:1 1 udp 2122260223 192.168.1.5 54321 typ host generation 0\r\n'
          'a=candidate:2 1 udp 1685987071 203.0.113.7 54321 typ srflx raddr 192.168.1.5 rport 54321 generation 0\r\n'
          'a=candidate:3 1 tcp 1518280447 198.51.100.42 443 typ relay raddr 0.0.0.0 rport 0 generation 0\r\n'
          'a=candidate:4 1 udp 2122129151 8f2e1a3c-1234-4a5b-9c6d-abcdef012345.local 54322 typ host generation 0\r\n'
          'a=candidate:5 1 udp 2122129150 2001:db8::1 54323 typ host generation 0\r\n'
          'a=candidate:6 1 tcp 2105524479 127.0.0.1 54324 typ host tcptype active generation 0\r\n'
          'a=end-of-candidates\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'c=IN IP4 0.0.0.0\r\n'
          'a=rtcp:9 IN IP4 0.0.0.0\r\n'
          'a=ice-ufrag:4ZcD\r\n'
          'a=ice-pwd:2/1muCWoOi3uLifh0NuRlDNj\r\n'
          'a=fingerprint:sha-256 4A:AD:B9:B1:3F:82:18:3B:54:02:12:DF:3E:5D:49:6B:'
          '19:E5:7C:AB:3A:47:99:19:5B:D0:81:CE:E4:1D:5B:5A\r\n'
          'a=setup:actpass\r\n'
          'a=mid:1\r\n'
          'a=sendrecv\r\n'
          'a=rtcp-mux\r\n'
          'a=rtpmap:96 VP8/90000\r\n'
          // Same host/srflx/relay candidates repeated for the bundled video m-line.
          'a=candidate:1 1 udp 2122260223 192.168.1.5 54321 typ host generation 0\r\n'
          'a=candidate:2 1 udp 1685987071 203.0.113.7 54321 typ srflx raddr 192.168.1.5 rport 54321 generation 0\r\n'
          'a=candidate:3 1 tcp 1518280447 198.51.100.42 443 typ relay raddr 0.0.0.0 rport 0 generation 0\r\n'
          'a=end-of-candidates\r\n';

      final sessionId = Uint8List.fromList([2, 2, 2, 2, 2, 2]);
      final payload = extractFromSdp(sdp, isAnswer: false, sessionId: sessionId);

      expect(payload.iceUfrag, '4ZcD');
      expect(payload.icePwd, '2/1muCWoOi3uLifh0NuRlDNj');
      expect(payload.dtlsFingerprint.length, 32);
      expect(payload.hasAudio, isTrue);
      expect(payload.hasVideo, isTrue);

      // Deduped down to 3 (host/srflx/relay); mDNS host, IPv6, and loopback
      // candidates skipped.
      expect(payload.candidates.length, 3);
      expect(payload.candidates.map((c) => c.type).toSet(),
          {CandidateType.host, CandidateType.srflx, CandidateType.relay});
      expect(payload.candidates.any((c) => c.ip == '127.0.0.1'), isFalse);
    });

    test('skips a loopback host candidate even when no other host candidate exists', () {
      const sdp = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'a=group:BUNDLE 0\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=ice-ufrag:abcd\r\n'
          'a=ice-pwd:0123456789abcdef01234567\r\n'
          'a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:'
          '00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00\r\n'
          'a=candidate:1 1 tcp 2105524479 127.0.0.1 54324 typ host tcptype active generation 0\r\n'
          'a=candidate:2 1 udp 1685987071 203.0.113.7 54321 typ srflx raddr 192.168.1.5 rport 54321 generation 0\r\n'
          'a=end-of-candidates\r\n';

      final payload = extractFromSdp(sdp, isAnswer: false, sessionId: Uint8List(6));
      expect(payload.candidates.length, 1);
      expect(payload.candidates.single.type, CandidateType.srflx);
    });

    test('treats a rejected (port 0) m-line as absent', () {
      const sdp = 'v=0\r\n'
          'o=- 1 2 IN IP4 127.0.0.1\r\n'
          's=-\r\n'
          't=0 0\r\n'
          'a=group:BUNDLE 0\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=ice-ufrag:abcd\r\n'
          'a=ice-pwd:0123456789abcdef01234567\r\n'
          'a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:'
          '00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00\r\n'
          'm=video 0 UDP/TLS/RTP/SAVPF 96\r\n';

      final payload = extractFromSdp(sdp, isAnswer: false, sessionId: Uint8List(6));
      expect(payload.hasAudio, isTrue);
      expect(payload.hasVideo, isFalse);
    });

    test('throws FormatException when ice-ufrag/pwd/fingerprint are missing', () {
      const sdp = 'v=0\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n';
      expect(
        () => extractFromSdp(sdp, isAnswer: false, sessionId: Uint8List(6)),
        throwsFormatException,
      );
    });
  });
}
