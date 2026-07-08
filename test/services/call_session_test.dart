import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:v_call_me/data/turn/turn_credentials_service.dart';
import 'package:v_call_me/domain/signaling/ice_candidate.dart';
import 'package:v_call_me/domain/signaling/peer_connection_gateway.dart';
import 'package:v_call_me/domain/signaling/sdp_codec.dart';
import 'package:v_call_me/domain/signaling/signaling_codec.dart';
import 'package:v_call_me/domain/signaling/signaling_payload.dart';
import 'package:v_call_me/services/call_session.dart';

class _FakeGateway implements PeerConnectionGateway {
  _FakeGateway({required this.localOfferSdp, required this.localAnswerSdp});

  final String localOfferSdp;
  final String localAnswerSdp;

  List<Map<String, dynamic>>? openedWithIceServers;
  String? appliedRemoteAnswerSdp;
  bool disposed = false;

  final _controller = StreamController<PeerConnectionStatus>.broadcast();

  @override
  Stream<PeerConnectionStatus> get connectionState => _controller.stream;

  @override
  Future<void> open({required List<Map<String, dynamic>> iceServers}) async {
    openedWithIceServers = iceServers;
  }

  @override
  Future<String> createLocalOffer() async => localOfferSdp;

  @override
  Future<String> createLocalAnswer(String remoteOfferSdp) async => localAnswerSdp;

  @override
  Future<void> applyRemoteAnswer(String remoteAnswerSdp) async {
    appliedRemoteAnswerSdp = remoteAnswerSdp;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }

  void emitStatus(PeerConnectionStatus status) => _controller.add(status);
}

class _FakeTurnCredentialsService extends TurnCredentialsService {
  _FakeTurnCredentialsService({this.servers = const [], this.errorToThrow})
      : super(apiKey: 'unused');

  final List<Map<String, dynamic>> servers;
  final Object? errorToThrow;

  @override
  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    if (errorToThrow != null) throw errorToThrow!;
    return servers;
  }
}

String _sdpFixture({required bool isAnswer, required String ufrag}) {
  return buildSdp(SignalingPayload(
    schemaVersion: signalingSchemaVersion,
    hasAudio: true,
    hasVideo: true,
    isAnswer: isAnswer,
    sessionId: Uint8List(6),
    iceUfrag: ufrag,
    icePwd: 'somesecretpassword12345',
    dtlsFingerprint: Uint8List.fromList(List.generate(32, (i) => i)),
    candidates: const [
      IceCandidateInfo(
        type: CandidateType.host,
        transport: CandidateTransport.udp,
        ip: '10.0.0.2',
        port: 5000,
      ),
    ],
  ));
}

CallSession _session({
  required String localOfferSdp,
  required String localAnswerSdp,
  List<Map<String, dynamic>> iceServers = const [
    {'urls': 'stun:stun.relay.metered.ca:80'},
  ],
}) {
  return CallSession(
    gateway: _FakeGateway(localOfferSdp: localOfferSdp, localAnswerSdp: localAnswerSdp),
    turnCredentials: _FakeTurnCredentialsService(servers: iceServers),
  );
}

void main() {
  test('host + joiner exchange offer/answer through the real codecs and connect', () async {
    final hostOfferSdp = _sdpFixture(isAnswer: false, ufrag: 'hostufrg');
    final host = _session(
      localOfferSdp: hostOfferSdp,
      localAnswerSdp: '', // host never creates an answer
    );

    final offerBytes = await host.createOffer();
    expect(host.state, CallState.awaitingRemoteAnswer);

    final joinerAnswerSdp = _sdpFixture(isAnswer: true, ufrag: 'joinufrg');
    final joiner = _session(
      localOfferSdp: '', // joiner never creates an offer
      localAnswerSdp: joinerAnswerSdp,
    );

    final answerBytes = await joiner.acceptOfferAndCreateAnswer(offerBytes);
    expect(joiner.state, CallState.connecting);

    await host.applyRemoteAnswer(answerBytes);
    expect(host.state, CallState.connecting);
  });

  test('createOffer fetches TURN credentials and opens the gateway with them', () async {
    final iceServers = [
      {'urls': 'turn:global.relay.metered.ca:80', 'username': 'u', 'credential': 'c'},
    ];
    final gateway = _FakeGateway(
      localOfferSdp: _sdpFixture(isAnswer: false, ufrag: 'abcd'),
      localAnswerSdp: '',
    );
    final session = CallSession(
      gateway: gateway,
      turnCredentials: _FakeTurnCredentialsService(servers: iceServers),
    );

    await session.createOffer();

    expect(gateway.openedWithIceServers, iceServers);
  });

  test('propagates a TURN credentials fetch failure', () async {
    final session = CallSession(
      gateway: _FakeGateway(localOfferSdp: '', localAnswerSdp: ''),
      turnCredentials: _FakeTurnCredentialsService(errorToThrow: Exception('offline')),
    );

    expect(session.createOffer(), throwsException);
  });

  test('acceptOfferAndCreateAnswer rejects a payload already flagged as an answer', () async {
    final session = _session(localOfferSdp: '', localAnswerSdp: '');
    final answerLikePayload = encodeSignalingPayload(SignalingPayload(
      schemaVersion: signalingSchemaVersion,
      hasAudio: true,
      hasVideo: true,
      isAnswer: true,
      sessionId: Uint8List(6),
      iceUfrag: 'x',
      icePwd: 'y',
      dtlsFingerprint: Uint8List(32),
      candidates: const [],
    ));

    expect(
      session.acceptOfferAndCreateAnswer(answerLikePayload),
      throwsFormatException,
    );
  });

  test('applyRemoteAnswer rejects a payload still flagged as an offer', () async {
    final session = _session(
      localOfferSdp: _sdpFixture(isAnswer: false, ufrag: 'abcd'),
      localAnswerSdp: '',
    );
    await session.createOffer();

    final offerLikePayload = encodeSignalingPayload(SignalingPayload(
      schemaVersion: signalingSchemaVersion,
      hasAudio: true,
      hasVideo: true,
      isAnswer: false,
      sessionId: Uint8List(6),
      iceUfrag: 'x',
      icePwd: 'y',
      dtlsFingerprint: Uint8List(32),
      candidates: const [],
    ));

    expect(
      session.applyRemoteAnswer(offerLikePayload),
      throwsFormatException,
    );
  });

  test('applyRemoteAnswer throws if called before createOffer', () async {
    final session = _session(localOfferSdp: '', localAnswerSdp: '');
    final somePayload = encodeSignalingPayload(SignalingPayload(
      schemaVersion: signalingSchemaVersion,
      hasAudio: true,
      hasVideo: true,
      isAnswer: true,
      sessionId: Uint8List(6),
      iceUfrag: 'x',
      icePwd: 'y',
      dtlsFingerprint: Uint8List(32),
      candidates: const [],
    ));

    expect(session.applyRemoteAnswer(somePayload), throwsStateError);
  });

  test("applyRemoteAnswer throws when the session id doesn't match the offer's", () async {
    final host = _session(
      localOfferSdp: _sdpFixture(isAnswer: false, ufrag: 'abcd'),
      localAnswerSdp: '',
    );
    await host.createOffer();

    final rogueAnswer = encodeSignalingPayload(SignalingPayload(
      schemaVersion: signalingSchemaVersion,
      hasAudio: true,
      hasVideo: true,
      isAnswer: true,
      sessionId: Uint8List.fromList([9, 9, 9, 9, 9, 9]), // not the offer's session id
      iceUfrag: 'x',
      icePwd: 'y',
      dtlsFingerprint: Uint8List(32),
      candidates: const [],
    ));

    expect(host.applyRemoteAnswer(rogueAnswer), throwsStateError);
  });

  test('forwards gateway connection status to state and onConnected/onDisconnected', () async {
    final gateway = _FakeGateway(
      localOfferSdp: _sdpFixture(isAnswer: false, ufrag: 'abcd'),
      localAnswerSdp: '',
    );
    final session = CallSession(
      gateway: gateway,
      turnCredentials: _FakeTurnCredentialsService(),
    );
    var connectedCalls = 0;
    var disconnectedCalls = 0;
    session.onConnected = () => connectedCalls++;
    session.onDisconnected = () => disconnectedCalls++;

    await session.createOffer();

    gateway.emitStatus(PeerConnectionStatus.connected);
    await Future<void>.delayed(Duration.zero);
    expect(session.state, CallState.connected);
    expect(connectedCalls, 1);

    gateway.emitStatus(PeerConnectionStatus.failed);
    await Future<void>.delayed(Duration.zero);
    expect(session.state, CallState.ended);
    expect(disconnectedCalls, 1);
  });

  test('dispose() tears down the gateway and TURN client', () async {
    final gateway = _FakeGateway(localOfferSdp: '', localAnswerSdp: '');
    final session = CallSession(
      gateway: gateway,
      turnCredentials: _FakeTurnCredentialsService(),
    );

    await session.dispose();

    expect(gateway.disposed, isTrue);
  });
}
