import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../domain/signaling/peer_connection_gateway.dart';
import '../domain/signaling/signaling_payload.dart';
import '../main.dart';
import '../services/call_session.dart';

/// The active call UI: local/remote video, basic controls, and (optionally,
/// host-only) a debug panel showing the joiner's decoded connection info -
/// handy for confirming a real physical-device connection actually worked.
///
/// Shared regardless of role, since the session is symmetric once connected.
class InCallScreen extends StatefulWidget {
  const InCallScreen({super.key, required this.session, this.showDebugPanel = false});

  final CallSession session;
  final bool showDebugPanel;

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  bool _renderersReady = false;
  bool _callEnded = false;
  late PeerConnectionStatus _status;
  StreamSubscription<PeerConnectionStatus>? _statusSub;
  StreamSubscription<MediaStream>? _remoteStreamSub;

  @override
  void initState() {
    super.initState();
    // Seed from the current status and subscribe synchronously, before any
    // `await` - connectionStatus is a broadcast stream with no replay, so a
    // subscription set up later (e.g. after awaiting renderer init below)
    // could miss a status change (most importantly "connected") that
    // already happened, such as one that this very screen's navigation was
    // triggered by, and get stuck forever.
    _status = widget.session.currentConnectionStatus;
    _statusSub = widget.session.connectionStatus.listen(_handleStatusChange);
    _maybeHandleCallEnded(_status);
    _init();
  }

  void _handleStatusChange(PeerConnectionStatus status) {
    if (mounted) setState(() => _status = status);
    _maybeHandleCallEnded(status);
  }

  /// If the other side disconnects, fails, or closes the connection while
  /// this screen is showing, leave the call screen instead of stranding the
  /// user on a frozen video - pop back to Home and say why.
  void _maybeHandleCallEnded(PeerConnectionStatus status) {
    if (_callEnded) return;
    final message = switch (status) {
      PeerConnectionStatus.disconnected => 'Call ended: connection was lost.',
      PeerConnectionStatus.failed => 'Call ended: connection failed.',
      PeerConnectionStatus.closed => 'Call ended.',
      PeerConnectionStatus.connecting || PeerConnectionStatus.connected => null,
    };
    if (message == null) return;
    _callEnded = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
    rootScaffoldMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _localRenderer.srcObject = widget.session.localStream;

    // Same broadcast-stream-has-no-replay hazard as connectionStatus above:
    // subscribe first, then check whether the remote track already arrived
    // while we were awaiting renderer initialization.
    _remoteStreamSub = widget.session.remoteStream.listen((stream) {
      if (mounted) setState(() => _remoteRenderer.srcObject = stream);
    });
    _remoteRenderer.srcObject = widget.session.currentRemoteStream;

    if (mounted) setState(() => _renderersReady = true);
  }

  void _hangUp() {
    _callEnded = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _remoteStreamSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: !_renderersReady
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: _remoteVideo()),
                        Positioned(
                          right: 16,
                          top: 16,
                          width: 110,
                          height: 150,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: RTCVideoView(_localRenderer, mirror: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Controls(onHangUp: _hangUp),
                  if (widget.showDebugPanel)
                    _DebugPanel(
                      status: _status,
                      localPayload: widget.session.localPayload,
                      remotePayload: widget.session.remotePayload,
                    ),
                ],
              ),
      ),
    );
  }

  Widget _remoteVideo() {
    if (_status == PeerConnectionStatus.connected) {
      return RTCVideoView(_remoteRenderer);
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(_statusMessage(_status), style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  String _statusMessage(PeerConnectionStatus status) {
    switch (status) {
      case PeerConnectionStatus.connecting:
        return 'Connecting…';
      case PeerConnectionStatus.connected:
        return 'Connected';
      case PeerConnectionStatus.disconnected:
        return 'Disconnected';
      case PeerConnectionStatus.failed:
        return 'Connection failed';
      case PeerConnectionStatus.closed:
        return 'Call ended';
    }
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.onHangUp});

  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: FloatingActionButton(
        onPressed: onHangUp,
        backgroundColor: Colors.red,
        child: const Icon(Icons.call_end, color: Colors.white),
      ),
    );
  }
}

/// Host-only diagnostics panel showing the host's and joiner's IP addresses
/// (from their decoded QR payloads), so you can confirm on a physical device
/// that a real peer actually showed up rather than just trusting a green
/// checkmark.
class _DebugPanel extends StatelessWidget {
  const _DebugPanel({
    required this.status,
    required this.localPayload,
    required this.remotePayload,
  });

  final PeerConnectionStatus status;
  final SignalingPayload? localPayload;
  final SignalingPayload? remotePayload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black87,
      padding: const EdgeInsets.all(12),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('DEBUG  ·  status: ${status.name}'),
            const SizedBox(height: 4),
            Text('host ip: ${_ips(localPayload)}'),
            Text('joiner ip: ${_ips(remotePayload)}'),
          ],
        ),
      ),
    );
  }

  String _ips(SignalingPayload? payload) {
    if (payload == null) return 'unknown';
    final ips = payload.candidates.map((c) => c.ip).toSet();
    if (ips.isEmpty) return 'none';
    return ips.join(', ');
  }
}
