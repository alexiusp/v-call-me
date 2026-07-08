import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../domain/signaling/signaling_codec.dart';
import '../domain/signaling/signaling_payload.dart';

/// Camera scanner and/or gallery image picker for an offer/answer QR code,
/// reused for both roles per DESIGN.md section 6.
class QrImportScreen extends StatefulWidget {
  const QrImportScreen({super.key});

  @override
  State<QrImportScreen> createState() => _QrImportScreenState();
}

class _QrImportScreenState extends State<QrImportScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handling = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePayload(Uint8List bytes) {
    if (_handling) return;
    _handling = true;
    try {
      final payload = decodeSignalingPayload(bytes);
      _onDecoded(payload);
    } on FormatException catch (e) {
      setState(() => _error = 'Could not read QR code: ${e.message}');
      _handling = false;
    } catch (e) {
      setState(() => _error = 'Could not read QR code: $e');
      _handling = false;
    }
  }

  void _onDecoded(SignalingPayload payload) {
    final kind = payload.isAnswer ? 'answer' : 'offer';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Decoded $kind QR code successfully.')),
    );
    setState(() => _error = null);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final bytes = barcode.rawBytes;
      if (bytes != null) {
        _handlePayload(bytes);
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
        _handlePayload(bytes);
        return;
      }
    }
    setState(() => _error = 'QR code found, but its content could not be read.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan or import QR')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),
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
              onPressed: _pickFromGallery,
              icon: const Icon(Icons.photo_library),
              label: const Text('Load from device'),
            ),
          ),
        ],
      ),
    );
  }
}
