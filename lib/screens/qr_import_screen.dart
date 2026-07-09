import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/call_session.dart';
import '../services/qr_payload_router.dart';

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
  const QrImportScreen({super.key, this.hostSession, this.showDebugPanel = false});

  final CallSession? hostSession;
  final bool showDebugPanel;

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
        showDebugPanel: widget.showDebugPanel,
      );
    } on FormatException catch (e) {
      setState(() {
        _error = 'Could not read QR code: ${e.message}';
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not complete the connection: $e';
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
      setState(() => _error = 'No QR code found in the selected image.');
      return;
    }

    for (final barcode in capture.barcodes) {
      final bytes = barcode.rawBytes;
      if (bytes != null) {
        await _handlePayload(bytes);
        return;
      }
    }
    setState(() => _error = 'QR code found, but its content could not be read.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.hostSession != null ? "Scan the joiner's answer" : 'Scan or import QR'),
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
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              'Connecting…',
                              style: TextStyle(color: Colors.white),
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
                      label: const Text('Load from device'),
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
