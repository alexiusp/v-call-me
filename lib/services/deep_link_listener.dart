import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../main.dart' show rootScaffoldMessengerKey;
import 'pending_host_session.dart';
import 'qr_link_codec.dart';
import 'qr_payload_router.dart';

/// Wraps the app's home screen and watches for a `vcallme://call?d=...` link
/// tapped in another app (the link `QrDisplayScreen`'s "Share" button sends
/// as plain text) - the fastest way to hand off an offer/answer, since
/// tapping opens straight into the right screen with no scanning, gallery
/// picking, or share-sheet app-picker step at all. Requires the `vcallme`
/// scheme intent-filter declared in AndroidManifest.xml.
class DeepLinkListener extends StatefulWidget {
  const DeepLinkListener({super.key, required this.child});

  final Widget child;

  @override
  State<DeepLinkListener> createState() => _DeepLinkListenerState();
}

class _DeepLinkListenerState extends State<DeepLinkListener> {
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    // uriLinkStream delivers both the cold-start link (if any) and every
    // subsequent one through a single subscription.
    _sub = AppLinks().uriLinkStream.listen(_handleUri);
  }

  Future<void> _handleUri(Uri uri) async {
    final bytes = decodeShareLink(uri);
    if (bytes == null) return;
    if (!mounted) return;

    try {
      await handleDecodedQrPayload(
        context,
        bytes,
        hostSession: PendingHostSession.current,
      );
    } catch (_) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Could not open that call link.')),
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
