import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/signaling/peer_connection_gateway.dart';
import '../services/call_session.dart';
import '../services/qr_export.dart';
import 'home_screen.dart';
import 'in_call_screen.dart';
import 'qr_import_screen.dart';

/// Renders the current payload (offer or answer) as a QR code, reused for
/// both roles per DESIGN.md section 6.
///
/// If [payload] isn't supplied (the host's "Start a call" flow), the screen
/// generates it itself by driving [session] through the state machine in
/// DESIGN.md section 5, showing a loading state while ICE gathering happens.
///
/// The host also gets a "show debug panel" checkbox here (state carried
/// forward through [QrImportScreen] to [InCallScreen]) and a button to move
/// on to scanning the joiner's answer QR. The joiner has neither: once its
/// answer QR is shown, this screen just waits for the connection to
/// complete and moves on to [InCallScreen] automatically.
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

  bool _showDebugPanel = false;
  StreamSubscription<PeerConnectionStatus>? _connectionSub;

  Future<Uint8List> _generatePayload() async {
    switch (widget.role) {
      case CallRole.host:
        return widget.session.createOffer();
      case CallRole.joiner:
        throw StateError('QrDisplayScreen requires a payload for the joiner role');
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.role == CallRole.joiner) {
      // The joiner has no further manual step: once the host scans this
      // answer QR and ICE connects, move straight on to the call screen.
      _connectionSub = widget.session.connectionStatus.listen((status) {
        if (status == PeerConnectionStatus.connected && mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => InCallScreen(session: widget.session, showDebugPanel: false),
          ));
        }
      });
    }
  }

  void _scanJoinerAnswer() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QrImportScreen(
        hostSession: widget.session,
        showDebugPanel: _showDebugPanel,
      ),
    ));
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
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
            showDebugPanel: _showDebugPanel,
            onShowDebugPanelChanged: widget.role == CallRole.host
                ? (value) => setState(() => _showDebugPanel = value)
                : null,
            onScanAnswer: widget.role == CallRole.host ? _scanJoinerAnswer : null,
          );
        },
      ),
    );
  }
}

class _QrContent extends StatelessWidget {
  const _QrContent({
    required this.data,
    required this.role,
    required this.showDebugPanel,
    required this.onShowDebugPanelChanged,
    required this.onScanAnswer,
  });

  final Uint8List data;
  final CallRole role;
  final bool showDebugPanel;
  final ValueChanged<bool>? onShowDebugPanelChanged;
  final VoidCallback? onScanAnswer;

  Future<void> _share(BuildContext context) async {
    final pngBytes = await renderQrPng(data);
    if (pngBytes == null) return;
    final fileName = role == CallRole.host ? 'call-offer.png' : 'call-answer.png';
    // Deliberately no `subject`: on Android it maps to EXTRA_SUBJECT, and
    // some share targets (notably Google Drive's "Save to Drive") use that
    // text as the saved file's name instead of the actual file name when
    // saving directly from the share sheet - the file only gets its correct
    // name if it's saved to local storage first and shared again from there.
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qrCode = QrCode.fromUint8List(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.H,
    );
    return SingleChildScrollView(
      child: Center(
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
              if (onShowDebugPanelChanged != null) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: showDebugPanel,
                  onChanged: (value) => onShowDebugPanelChanged!(value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Show debug panel during call'),
                  subtitle: const Text("Displays the joiner's connection info on the call screen"),
                ),
              ],
              if (onScanAnswer != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onScanAnswer,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text("I've got their answer, scan it"),
                ),
              ],
              if (role == CallRole.joiner) ...[
                const SizedBox(height: 24),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Waiting for the host to connect…'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
