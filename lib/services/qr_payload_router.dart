import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../screens/in_call_screen.dart';
import '../screens/qr_display_screen.dart';
import '../screens/home_screen.dart';
import 'call_session.dart';
import 'pending_host_session.dart';

/// Applies a decoded offer/answer payload and navigates to the next screen.
///
/// Shared by [QrImportScreen] (in-app camera scan / gallery import) and the
/// Android share-target listener, so both entry points funnel through the
/// same offer-vs-answer branching in [DESIGN.md] section 5 instead of
/// duplicating it.
///
/// If [hostSession] is supplied, [bytes] is treated as an answer completing
/// that call; otherwise [bytes] is treated as a fresh offer starting a new
/// joiner session.
Future<void> handleDecodedQrPayload(
  BuildContext context,
  Uint8List bytes, {
  CallSession? hostSession,
}) async {
  if (hostSession != null) {
    await hostSession.applyRemoteAnswer(bytes);
    if (PendingHostSession.current == hostSession) {
      PendingHostSession.current = null;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InCallScreen(session: hostSession),
    ));
  } else {
    final joinerSession = CallSession();
    final answerBytes = await joinerSession.acceptOfferAndCreateAnswer(bytes);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QrDisplayScreen(
        role: CallRole.joiner,
        payload: answerBytes,
        session: joinerSession,
      ),
    ));
  }
}
