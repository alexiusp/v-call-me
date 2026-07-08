import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../services/call_session.dart';
import '../services/qr_export.dart';
import 'home_screen.dart';

/// Renders the current payload (offer or answer) as a QR code, reused for
/// both roles per DESIGN.md section 6.
///
/// If [payload] isn't supplied (the host's "Start a call" flow), the screen
/// generates it itself by driving [session] through the state machine in
/// DESIGN.md section 5, showing a loading state while ICE gathering happens.
class QrDisplayScreen extends StatefulWidget {
  QrDisplayScreen({super.key, required this.role, this.payload, CallSession? session})
      : session = session ?? CallSession();

  final CallRole role;
  final Uint8List? payload;
  final CallSession session;

  @override
  State<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends State<QrDisplayScreen> {
  late final Future<Uint8List> _payloadFuture =
      widget.payload != null ? Future.value(widget.payload) : _generatePayload();

  Future<Uint8List> _generatePayload() async {
    switch (widget.role) {
      case CallRole.host:
        return widget.session.createOffer();
      case CallRole.joiner:
        throw StateError('QrDisplayScreen requires a payload for the joiner role');
    }
  }

  @override
  void dispose() {
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.role == CallRole.host ? 'Offer QR' : 'Answer QR'),
      ),
      body: FutureBuilder<Uint8List>(
        future: _payloadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Gathering connection info…'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not generate QR code: ${snapshot.error}'),
              ),
            );
          }
          return _QrContent(
            data: snapshot.data!,
            role: widget.role,
          );
        },
      ),
    );
  }
}

class _QrContent extends StatelessWidget {
  const _QrContent({required this.data, required this.role});

  final Uint8List data;
  final CallRole role;

  Future<void> _share(BuildContext context) async {
    final pngBytes = await renderQrPng(data);
    if (pngBytes == null) return;
    final fileName = role == CallRole.host ? 'call-offer.png' : 'call-answer.png';
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName)],
        subject: role == CallRole.host ? 'Call offer' : 'Call answer',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qrCode = QrCode.fromUint8List(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.H,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView.withQr(
                qr: qrCode,
                size: 280,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              role == CallRole.host
                  ? 'Send this to the other side, then wait for their answer QR.'
                  : 'Send this back to the host to complete the connection.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _share(context),
              icon: const Icon(Icons.share),
              label: const Text('Share as file'),
            ),
          ],
        ),
      ),
    );
  }
}
