import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/l10n.dart';
import '../services/call_session.dart';
import '../services/qr_payload_router.dart';
import '../widgets/settings_button.dart';

/// Camera scanner and/or gallery image picker for an offer/answer QR code,
/// reused for both roles per DESIGN.md section 6.
///
/// If [hostSession] is supplied, this screen is the host's second step:
/// it's scanning the joiner's answer QR to complete an already-started call,
/// so a decoded payload is fed into [CallSession.applyRemoteAnswer] and the
/// call moves on to [InCallScreen]. Otherwise this is the joiner's first
/// step: a decoded offer starts a brand new [CallSession] via
/// [CallSession.acceptOfferAndCreateAnswer], and the resulting answer is
/// shown on [QrDisplayScreen] for the host to scan back.
class QrImportScreen extends StatefulWidget {
  const QrImportScreen({super.key, this.hostSession});

  final CallSession? hostSession;

  @override
  State<QrImportScreen> createState() => _QrImportScreenState();
}

class _QrImportScreenState extends State<QrImportScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handlePayload(Uint8List bytes) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await handleDecodedQrPayload(
        context,
        bytes,
        hostSession: widget.hostSession,
      );
    } on FormatException catch (e) {
      setState(() {
        _error = context.l10n.couldNotReadQrCode(e.message);
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = context.l10n.couldNotCompleteConnection('$e');
        _busy = false;
      });
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final bytes = barcode.rawBytes;
      if (bytes != null) {
        await _handlePayload(bytes);
        return;
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final capture = await _controller.analyzeImage(file.path);
    if (capture == null || capture.barcodes.isEmpty) {
      setState(() => _error = context.l10n.noQrCodeFound);
      return;
    }

    for (final barcode in capture.barcodes) {
      final bytes = barcode.rawBytes;
      if (bytes != null) {
        await _handlePayload(bytes);
        return;
      }
    }
    setState(() => _error = context.l10n.qrCodeFoundButUnreadable);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.hostSession != null ? context.l10n.scanJoinerAnswerTitle : context.l10n.scanOrImportTitle,
        ),
        actions: const [SettingsButton()],
      ),
      // SafeArea + a guaranteed-share bottom section (rather than an
      // Expanded camera view eating all remaining space down to the
      // system nav bar) so "Load from device" stays comfortably visible
      // and reachable on every device, not squeezed against the edge.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                  if (_busy)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              context.l10n.connectingEllipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: Text(context.l10n.loadFromDevice),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
