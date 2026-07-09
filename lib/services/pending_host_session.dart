import 'call_session.dart';

/// The host's [CallSession] currently awaiting an answer QR, if any.
///
/// Lets the share-target listener (see `shared_qr_intent_listener.dart`)
/// distinguish an incoming shared QR image that's an answer to *this* call
/// from one that's a fresh offer starting a new call - a raw decoded payload
/// on its own doesn't carry which host session it replies to, so the host's
/// [QrDisplayScreen] records itself here while it's the one waiting.
class PendingHostSession {
  PendingHostSession._();

  static CallSession? current;
}
