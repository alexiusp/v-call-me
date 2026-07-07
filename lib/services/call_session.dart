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

/// Role-agnostic wrapper around an `RTCPeerConnection`, per DESIGN.md section 6.
///
/// Both host and joiner drive the same state machine through this class;
/// only the first couple of steps differ by role (who calls createOffer vs.
/// acceptOfferAndCreateAnswer).
class CallSession {
  CallState state = CallState.idle;

  void Function()? onConnected;
  void Function()? onDisconnected;

  Future<String> createOffer() {
    throw UnimplementedError();
  }

  Future<String> acceptOfferAndCreateAnswer(String offerPayload) {
    throw UnimplementedError();
  }

  Future<void> applyRemoteAnswer(String answerPayload) {
    throw UnimplementedError();
  }

  Future<void> dispose() async {}
}
