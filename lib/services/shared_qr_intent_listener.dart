import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_handler/share_handler.dart';

import '../l10n/l10n.dart';
import '../main.dart' show rootScaffoldMessengerKey;
import 'pending_host_session.dart';
import 'qr_payload_router.dart';

/// Wraps the app's home screen and watches for a QR image shared in from
/// another app's share sheet (tapping "Share" on the offer/answer photo
/// received in a messaging app and picking this app), so completing a call
/// doesn't require saving the image to the gallery first and hunting for it
/// in [QrImportScreen]'s picker - the Android counterpart to that screen's
/// "Load from device" button. Requires the `ACTION_SEND` intent-filters
/// declared in AndroidManifest.xml to receive anything at all.
class SharedQrIntentListener extends StatefulWidget {
  const SharedQrIntentListener({super.key, required this.child});

  final Widget child;

  @override
  State<SharedQrIntentListener> createState() => _SharedQrIntentListenerState();
}

class _SharedQrIntentListenerState extends State<SharedQrIntentListener> {
  final MobileScannerController _scanner = MobileScannerController();
  StreamSubscription<SharedMedia>? _sub;

  @override
  void initState() {
    super.initState();
    // share_handler only implements Android/iOS share intents; on web its
    // platform channel is missing, so wiring it up throws MissingPluginException.
    // There's no share sheet to receive from on web anyway, so skip it there.
    if (kIsWeb) return;
    final handler = ShareHandlerPlatform.instance;
    handler.getInitialSharedMedia().then((media) {
      handler.resetInitialSharedMedia();
      if (media != null) _handleShared(media);
    });
    _sub = handler.sharedMediaStream.listen(_handleShared);
  }

  Future<void> _handleShared(SharedMedia media) async {
    for (final attachment in media.attachments ?? const []) {
      if (attachment == null || attachment.type != SharedAttachmentType.image) {
        continue;
      }

      final capture = await _scanner.analyzeImage(attachment.path);
      Uint8List? bytes;
      for (final barcode in capture?.barcodes ?? const []) {
        if (barcode.rawBytes != null) {
          bytes = barcode.rawBytes;
          break;
        }
      }
      if (bytes == null) continue;
      if (!mounted) return;

      try {
        await handleDecodedQrPayload(
          context,
          bytes,
          hostSession: PendingHostSession.current,
        );
      } catch (_) {
        if (!mounted) return;
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotReadSharedQrCode)),
        );
      }
      return;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
