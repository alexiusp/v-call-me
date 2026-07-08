/// Coarse connection status, decoupled from `flutter_webrtc`'s
/// `RTCPeerConnectionState` so domain/service code never has to import it.
enum PeerConnectionStatus { connecting, connected, disconnected, failed, closed }

/// Abstraction over a single WebRTC peer connection's signaling lifecycle,
/// so `CallSession` (services/call_session.dart) can be unit-tested without
/// a real `flutter_webrtc` `RTCPeerConnection` (which needs a device/
/// emulator to run at all). The only implementation is
/// `data/webrtc/webrtc_peer_connection_gateway.dart`.
///
/// Every method here does non-trickle ICE gathering internally (DESIGN.md
/// section 5): the offer/answer SDP returned already has all local
/// candidates embedded, gathered to completion (or timeout) before
/// returning.
abstract class PeerConnectionGateway {
  /// Must be called once, before any other method.
  Future<void> open({required List<Map<String, dynamic>> iceServers});

  /// Acquires local audio/video, creates and sets the local offer, waits for
  /// ICE gathering, and returns the final local SDP text.
  Future<String> createLocalOffer();

  /// Sets [remoteOfferSdp] as the remote description, acquires local
  /// audio/video, creates and sets the local answer, waits for ICE
  /// gathering, and returns the final local SDP text.
  Future<String> createLocalAnswer(String remoteOfferSdp);

  /// Sets [remoteAnswerSdp] as the remote description, completing the
  /// offer/answer exchange.
  Future<void> applyRemoteAnswer(String remoteAnswerSdp);

  /// Emits whenever the underlying peer connection's state changes.
  Stream<PeerConnectionStatus> get connectionState;

  Future<void> dispose();
}
