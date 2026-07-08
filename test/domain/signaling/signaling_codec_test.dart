import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:v_call_me/domain/signaling/ice_candidate.dart';
import 'package:v_call_me/domain/signaling/signaling_codec.dart';
import 'package:v_call_me/domain/signaling/signaling_payload.dart';

SignalingPayload _samplePayload({bool isAnswer = false}) {
  return SignalingPayload(
    schemaVersion: signalingSchemaVersion,
    hasAudio: true,
    hasVideo: true,
    isAnswer: isAnswer,
    sessionId: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
    iceUfrag: 'a1b2c3',
    icePwd: 'thisisasecretpassword123',
    dtlsFingerprint: Uint8List.fromList(List.generate(32, (i) => i * 7 % 256)),
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
  test('round-trips an offer payload through encode/decode', () {
    final payload = _samplePayload();
    final decoded = decodeSignalingPayload(encodeSignalingPayload(payload));
    expect(decoded, payload);
  });

  test('round-trips an answer payload through encode/decode', () {
    final payload = _samplePayload(isAnswer: true);
    final decoded = decodeSignalingPayload(encodeSignalingPayload(payload));
    expect(decoded, payload);
    expect(decoded.isAnswer, isTrue);
  });

  test('round-trips a payload with no candidates', () {
    final payload = SignalingPayload(
      schemaVersion: signalingSchemaVersion,
      hasAudio: true,
      hasVideo: false,
      isAnswer: false,
      sessionId: Uint8List.fromList([0, 0, 0, 0, 0, 0]),
      iceUfrag: 'x',
      icePwd: 'y',
      dtlsFingerprint: Uint8List(32),
      candidates: const [],
    );
    final decoded = decodeSignalingPayload(encodeSignalingPayload(payload));
    expect(decoded, payload);
  });

  test('stays within the ~90-150 byte budget from DESIGN.md for 3 candidates', () {
    final bytes = encodeSignalingPayload(_samplePayload());
    expect(bytes.length, lessThan(160));
  });

  test('throws FormatException on truncated bytes', () {
    final bytes = encodeSignalingPayload(_samplePayload());
    final truncated = bytes.sublist(0, bytes.length - 10);
    expect(() => decodeSignalingPayload(truncated), throwsFormatException);
  });

  test('throws FormatException on trailing garbage bytes', () {
    final bytes = encodeSignalingPayload(_samplePayload());
    final withGarbage = Uint8List.fromList([...bytes, 0xFF, 0xFF]);
    expect(() => decodeSignalingPayload(withGarbage), throwsFormatException);
  });

  test('throws FormatException on an unsupported schema version', () {
    final bytes = encodeSignalingPayload(_samplePayload());
    bytes[0] = 99;
    expect(() => decodeSignalingPayload(bytes), throwsFormatException);
  });

  test('rejects a non-dotted-quad IPv4 address', () {
    final payload = SignalingPayload(
      schemaVersion: signalingSchemaVersion,
      hasAudio: true,
      hasVideo: true,
      isAnswer: false,
      sessionId: Uint8List(6),
      iceUfrag: 'a',
      icePwd: 'b',
      dtlsFingerprint: Uint8List(32),
      candidates: const [
        IceCandidateInfo(
          type: CandidateType.host,
          transport: CandidateTransport.udp,
          ip: 'not-an-ip',
          port: 1,
        ),
      ],
    );
    expect(() => encodeSignalingPayload(payload), throwsArgumentError);
  });
}
