import 'dart:convert';
import 'dart:typed_data';

import 'ice_candidate.dart';
import 'signaling_payload.dart';

/// Binary encode/decode for the compact payload schema in DESIGN.md
/// section 4:
///
/// ```
/// [1B]  schema version
/// [1B]  flags (bit0: audio, bit1: video, bit2: offer=0/answer=1)
/// [6B]  session id
/// [1B]  ICE ufrag length, then ufrag bytes
/// [1B]  ICE password length, then password bytes
/// [32B] DTLS fingerprint (raw sha-256 bytes)
/// [1B]  candidate count (N)
/// N x 8B candidates: 1B type + 1B transport + 4B IPv4 + 2B port
/// ```
const signalingSchemaVersion = 1;

Uint8List encodeSignalingPayload(SignalingPayload payload) {
  final ufragBytes = ascii.encode(payload.iceUfrag);
  final pwdBytes = ascii.encode(payload.icePwd);
  if (ufragBytes.length > 255) {
    throw ArgumentError(
        'iceUfrag too long to encode (${ufragBytes.length} bytes)');
  }
  if (pwdBytes.length > 255) {
    throw ArgumentError(
        'icePwd too long to encode (${pwdBytes.length} bytes)');
  }
  if (payload.candidates.length > 255) {
    throw ArgumentError(
        'too many candidates to encode (${payload.candidates.length})');
  }

  final builder = BytesBuilder();
  builder.addByte(payload.schemaVersion);
  builder.addByte(
    (payload.hasAudio ? 0x01 : 0) |
        (payload.hasVideo ? 0x02 : 0) |
        (payload.isAnswer ? 0x04 : 0),
  );
  builder.add(payload.sessionId);
  builder.addByte(ufragBytes.length);
  builder.add(ufragBytes);
  builder.addByte(pwdBytes.length);
  builder.add(pwdBytes);
  builder.add(payload.dtlsFingerprint);
  builder.addByte(payload.candidates.length);
  for (final candidate in payload.candidates) {
    builder.addByte(_candidateTypeCode(candidate.type));
    builder.addByte(_candidateTransportCode(candidate.transport));
    builder.add(_ipv4ToBytes(candidate.ip));
    builder.addByte((candidate.port >> 8) & 0xFF);
    builder.addByte(candidate.port & 0xFF);
  }
  return builder.toBytes();
}

SignalingPayload decodeSignalingPayload(Uint8List bytes) {
  final reader = _ByteReader(bytes);
  final schemaVersion = reader.readByte();
  if (schemaVersion != signalingSchemaVersion) {
    throw FormatException('Unsupported schema version: $schemaVersion');
  }
  final flags = reader.readByte();
  final sessionId = reader.readBytes(6);
  final ufragLen = reader.readByte();
  final iceUfrag = ascii.decode(reader.readBytes(ufragLen));
  final pwdLen = reader.readByte();
  final icePwd = ascii.decode(reader.readBytes(pwdLen));
  final dtlsFingerprint = reader.readBytes(32);
  final candidateCount = reader.readByte();
  final candidates = <IceCandidateInfo>[];
  for (var i = 0; i < candidateCount; i++) {
    final type = _candidateTypeFromCode(reader.readByte());
    final transport = _candidateTransportFromCode(reader.readByte());
    final ip = _ipv4FromBytes(reader.readBytes(4));
    final port = (reader.readByte() << 8) | reader.readByte();
    candidates.add(IceCandidateInfo(
      type: type,
      transport: transport,
      ip: ip,
      port: port,
    ));
  }
  reader.expectExhausted();

  return SignalingPayload(
    schemaVersion: schemaVersion,
    hasAudio: flags & 0x01 != 0,
    hasVideo: flags & 0x02 != 0,
    isAnswer: flags & 0x04 != 0,
    sessionId: sessionId,
    iceUfrag: iceUfrag,
    icePwd: icePwd,
    dtlsFingerprint: dtlsFingerprint,
    candidates: candidates,
  );
}

class _ByteReader {
  _ByteReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int readByte() {
    if (_offset >= _bytes.length) {
      throw const FormatException('Unexpected end of signaling payload');
    }
    return _bytes[_offset++];
  }

  Uint8List readBytes(int count) {
    if (_offset + count > _bytes.length) {
      throw const FormatException('Unexpected end of signaling payload');
    }
    final result = _bytes.sublist(_offset, _offset + count);
    _offset += count;
    return result;
  }

  void expectExhausted() {
    if (_offset != _bytes.length) {
      throw FormatException(
          'Trailing bytes in signaling payload (${_bytes.length - _offset} unread)');
    }
  }
}

int _candidateTypeCode(CandidateType type) => switch (type) {
      CandidateType.host => 0,
      CandidateType.srflx => 1,
      CandidateType.relay => 2,
    };

CandidateType _candidateTypeFromCode(int code) => switch (code) {
      0 => CandidateType.host,
      1 => CandidateType.srflx,
      2 => CandidateType.relay,
      _ => throw FormatException('Unknown candidate type code: $code'),
    };

int _candidateTransportCode(CandidateTransport transport) =>
    switch (transport) {
      CandidateTransport.udp => 0,
      CandidateTransport.tcp => 1,
    };

CandidateTransport _candidateTransportFromCode(int code) => switch (code) {
      0 => CandidateTransport.udp,
      1 => CandidateTransport.tcp,
      _ => throw FormatException('Unknown candidate transport code: $code'),
    };

Uint8List _ipv4ToBytes(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) {
    throw ArgumentError('Not a dotted-quad IPv4 address: $ip');
  }
  final bytes = Uint8List(4);
  for (var i = 0; i < 4; i++) {
    final octet = int.tryParse(parts[i]);
    if (octet == null || octet < 0 || octet > 255) {
      throw ArgumentError('Not a dotted-quad IPv4 address: $ip');
    }
    bytes[i] = octet;
  }
  return bytes;
}

String _ipv4FromBytes(Uint8List bytes) => bytes.join('.');
