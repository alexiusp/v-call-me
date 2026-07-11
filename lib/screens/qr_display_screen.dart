import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/signaling/peer_connection_gateway.dart';
import '../l10n/l10n.dart';
import '../services/call_session.dart';
import '../services/pending_host_session.dart';
import '../services/qr_export.dart';
import '../services/qr_link_codec.dart';
import '../widgets/settings_button.dart';
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
/// The host also gets a button here to move on to scanning the joiner's
/// answer QR. The joiner doesn't: once its answer QR is shown, this screen
/// just waits for the connection to complete and moves on to [InCallScreen]
/// automatically.
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
    if (widget.role == CallRole.host) {
      // Lets the share-target listener recognize a later shared QR image as
      // this call's answer rather than a fresh offer (see
      // `PendingHostSession`'s doc comment).
      PendingHostSession.current = widget.session;
    }
    if (widget.role == CallRole.joiner) {
      // The joiner has no further manual step: once the host scans this
      // answer QR and ICE connects, move straight on to the call screen.
      _connectionSub = widget.session.connectionStatus.listen((status) {
        if (status == PeerConnectionStatus.connected && mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => InCallScreen(session: widget.session),
          ));
        }
      });
    }
  }

  void _scanJoinerAnswer() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QrImportScreen(hostSession: widget.session),
    ));
  }

  @override
  void dispose() {
    if (PendingHostSession.current == widget.session) {
      PendingHostSession.current = null;
    }
    _connectionSub?.cancel();
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.role == CallRole.host ? context.l10n.offerQrTitle : context.l10n.answerQrTitle),
        actions: const [SettingsButton()],
      ),
      body: FutureBuilder<Uint8List>(
        future: _payloadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(context.l10n.gatheringConnectionInfo),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.l10n.couldNotGenerateQr('${snapshot.error}')),
              ),
            );
          }
          return _QrContent(
            data: snapshot.data!,
            role: widget.role,
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
    required this.onScanAnswer,
  });

  final Uint8List data;
  final CallRole role;
  final VoidCallback? onScanAnswer;

  // The default share action: a tappable link carrying the same payload as
  // the QR code, so the other side can open straight into the right screen
  // (see `deep_link_listener.dart`) with no scanning or gallery step -
  // easier for a non-technical recipient than the image below.
  Future<void> _shareLink(BuildContext context) async {
    await SharePlus.instance.share(
      ShareParams(text: buildShareLink(data).toString()),
    );
  }

  // Fallback for a channel that mangles custom-scheme links, or someone who
  // prefers a picture over a link.
  Future<void> _shareImage(BuildContext context) async {
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
                    ? context.l10n.sendToOtherSideHost
                    : context.l10n.sendBackToHostJoiner,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _shareLink(context),
                icon: const Icon(Icons.share),
                label: Text(context.l10n.shareButton),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => _shareImage(context),
                icon: const Icon(Icons.qr_code),
                label: Text(context.l10n.shareAsImageButton),
              ),
              if (onScanAnswer != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onScanAnswer,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(context.l10n.gotAnswerButton),
                ),
              ],
              if (role == CallRole.joiner) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(context.l10n.waitingForHost),
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
