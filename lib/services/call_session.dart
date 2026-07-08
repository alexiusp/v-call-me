import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../data/turn/turn_credentials_service.dart';
import '../data/webrtc/webrtc_peer_connection_gateway.dart';
import '../domain/signaling/peer_connection_gateway.dart';
import '../domain/signaling/sdp_codec.dart';
import '../domain/signaling/signaling_codec.dart';
import '../domain/signaling/signaling_payload.dart';

enum CallState {
  idle,
  creatingOffer,
  gatheringIce,
  awaitingRemoteAnswer,
  creatingAnswer,
  connecting,
  connected,
  ended,
}

/// Role-agnostic wrapper around a [PeerConnectionGateway], per DESIGN.md
/// section 6.
///
/// Both host and joiner drive the same state machine through this class;
/// only the first couple of steps differ by role (who calls createOffer vs.
/// acceptOfferAndCreateAnswer). Orchestrates three pieces that are each
/// independently unit-testable: TURN credentials (data/turn), the
/// SDP/binary codecs (domain/signaling), and the peer connection gateway
/// (domain interface, flutter_webrtc implementation in data/webrtc).
class CallSession {
  CallSession({PeerConnectionGateway? gateway, TurnCredentialsService? turnCredentials})
      : _gateway = gateway ?? WebrtcPeerConnectionGateway(),
        _turnCredentials = turnCredentials ?? TurnCredentialsService();

  final PeerConnectionGateway _gateway;
  final TurnCredentialsService _turnCredentials;

  CallState state = CallState.idle;

  void Function()? onConnected;
  void Function()? onDisconnected;

  bool _gatewayOpened = false;
  StreamSubscription<PeerConnectionStatus>? _connectionSub;

  /// Session id generated when this side created an offer, so a later
  /// [applyRemoteAnswer] can sanity-check the answer actually replies to it
  /// (DESIGN.md section 4).
  Uint8List? _pendingOfferSessionId;

  /// This side's own signaling payload (decoded, not raw bytes) - the offer
  /// if this is the host, the answer if this is the joiner. Exposed for
  /// diagnostics/debugging (see the host's debug panel on the call screen).
  SignalingPayload? localPayload;

  /// The last signaling payload received from the other side (decoded, not
  /// raw bytes) - e.g. on the host, this is the joiner's answer. Exposed for
  /// diagnostics/debugging (see the host's debug panel on the call screen).
  SignalingPayload? remotePayload;

  /// The last status the gateway reported, so a UI that starts observing
  /// [connectionStatus] late (e.g. after an `await` lets an earlier one-shot
  /// event go by) can still learn the current state instead of being stuck
  /// waiting for the next transition, which may never come.
  PeerConnectionStatus currentConnectionStatus = PeerConnectionStatus.connecting;

  MediaStream? get localStream => _gateway.localStream;
  Stream<MediaStream> get remoteStream => _gateway.remoteStream;
  MediaStream? get currentRemoteStream => _gateway.currentRemoteStream;
  Stream<PeerConnectionStatus> get connectionStatus => _gateway.connectionState;

  Future<Uint8List> createOffer() async {
    state = CallState.creatingOffer;
    await _ensureGatewayOpen();

    state = CallState.gatheringIce;
    final offerSdp = await _gateway.createLocalOffer();

    final sessionId = _generateSessionId();
    _pendingOfferSessionId = sessionId;
    final payload = extractFromSdp(offerSdp, isAnswer: false, sessionId: sessionId);
    localPayload = payload;

    state = CallState.awaitingRemoteAnswer;
    return encodeSignalingPayload(payload);
  }

  Future<Uint8List> acceptOfferAndCreateAnswer(Uint8List offerPayload) async {
    final decodedOffer = decodeSignalingPayload(offerPayload);
    if (decodedOffer.isAnswer) {
      throw const FormatException('Expected an offer payload, got an answer');
    }
    remotePayload = decodedOffer;

    state = CallState.creatingAnswer;
    await _ensureGatewayOpen();

    state = CallState.gatheringIce;
    final offerSdp = buildSdp(decodedOffer);
    final answerSdp = await _gateway.createLocalAnswer(offerSdp);

    final answerPayload = extractFromSdp(
      answerSdp,
      isAnswer: true,
      sessionId: decodedOffer.sessionId,
    );
    localPayload = answerPayload;

    // Both descriptions are already set at this point (offer via
    // setRemoteDescription inside createLocalAnswer, answer via
    // setLocalDescription), so ICE connectivity checks start automatically.
    state = CallState.connecting;
    return encodeSignalingPayload(answerPayload);
  }

  Future<void> applyRemoteAnswer(Uint8List answerPayload) async {
    final decodedAnswer = decodeSignalingPayload(answerPayload);
    if (!decodedAnswer.isAnswer) {
      throw const FormatException('Expected an answer payload, got an offer');
    }

    final expectedSessionId = _pendingOfferSessionId;
    if (expectedSessionId == null) {
      throw StateError('applyRemoteAnswer() called before createOffer()');
    }
    if (!_bytesEqual(decodedAnswer.sessionId, expectedSessionId)) {
      throw StateError(
          "Answer's session id doesn't match the offer's - it may be a reply to a different call");
    }
    remotePayload = decodedAnswer;

    await _gateway.applyRemoteAnswer(buildSdp(decodedAnswer));
    state = CallState.connecting;
  }

  Future<void> _ensureGatewayOpen() async {
    if (_gatewayOpened) return;
    final iceServers = await _turnCredentials.fetchIceServers();
    await _gateway.open(iceServers: iceServers);
    _gatewayOpened = true;
    _connectionSub = _gateway.connectionState.listen(_handleConnectionStatus);
  }

  void _handleConnectionStatus(PeerConnectionStatus status) {
    currentConnectionStatus = status;
    switch (status) {
      case PeerConnectionStatus.connected:
        state = CallState.connected;
        onConnected?.call();
      case PeerConnectionStatus.disconnected:
      case PeerConnectionStatus.failed:
      case PeerConnectionStatus.closed:
        state = CallState.ended;
        onDisconnected?.call();
      case PeerConnectionStatus.connecting:
        break;
    }
  }

  Future<void> dispose() async {
    await _connectionSub?.cancel();
    await _gateway.dispose();
    _turnCredentials.dispose();
  }
}

Uint8List _generateSessionId() {
  final random = Random.secure();
  return Uint8List.fromList(List<int>.generate(6, (_) => random.nextInt(256)));
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
