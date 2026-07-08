import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/signaling/peer_connection_gateway.dart';

/// How long to wait for non-trickle ICE gathering to finish before giving up
/// and proceeding with whatever candidates have been gathered so far - a
/// dead/unreachable TURN server shouldn't be able to hang the UI forever.
const _iceGatheringTimeout = Duration(seconds: 15);

class WebrtcPeerConnectionGateway implements PeerConnectionGateway {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final _connectionStateController =
      StreamController<PeerConnectionStatus>.broadcast();

  @override
  Stream<PeerConnectionStatus> get connectionState =>
      _connectionStateController.stream;

  @override
  Future<void> open({required List<Map<String, dynamic>> iceServers}) async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    pc.onConnectionState = (state) {
      _connectionStateController.add(_mapConnectionState(state));
    };
    _pc = pc;
  }

  @override
  Future<String> createLocalOffer() async {
    final pc = _requirePc();
    await _ensureLocalMedia(pc);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _waitForIceGatheringComplete(pc);
    return _requireLocalSdp(pc);
  }

  @override
  Future<String> createLocalAnswer(String remoteOfferSdp) async {
    final pc = _requirePc();
    await pc.setRemoteDescription(RTCSessionDescription(remoteOfferSdp, 'offer'));
    await _ensureLocalMedia(pc);
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await _waitForIceGatheringComplete(pc);
    return _requireLocalSdp(pc);
  }

  @override
  Future<void> applyRemoteAnswer(String remoteAnswerSdp) async {
    final pc = _requirePc();
    await pc.setRemoteDescription(RTCSessionDescription(remoteAnswerSdp, 'answer'));
  }

  Future<void> _ensureLocalMedia(RTCPeerConnection pc) async {
    if (_localStream != null) return;

    final statuses =
        await [Permission.camera, Permission.microphone].request();
    final granted = statuses.values.every((status) => status.isGranted);
    if (!granted) {
      throw StateError(
          'Camera and microphone permissions are required to start a call');
    }

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'},
    });
    _localStream = stream;
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }
  }

  Future<void> _waitForIceGatheringComplete(RTCPeerConnection pc) async {
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final completer = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };
    await completer.future.timeout(_iceGatheringTimeout, onTimeout: () {});
  }

  Future<String> _requireLocalSdp(RTCPeerConnection pc) async {
    final local = await pc.getLocalDescription();
    final sdp = local?.sdp;
    if (sdp == null) {
      throw StateError('RTCPeerConnection has no local description');
    }
    return sdp;
  }

  RTCPeerConnection _requirePc() {
    final pc = _pc;
    if (pc == null) {
      throw StateError('WebrtcPeerConnectionGateway.open() must be called first');
    }
    return pc;
  }

  PeerConnectionStatus _mapConnectionState(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return PeerConnectionStatus.connected;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return PeerConnectionStatus.disconnected;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return PeerConnectionStatus.failed;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return PeerConnectionStatus.closed;
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return PeerConnectionStatus.connecting;
    }
  }

  @override
  Future<void> dispose() async {
    for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    await _pc?.close();
    await _pc?.dispose();
    await _connectionStateController.close();
  }
}
