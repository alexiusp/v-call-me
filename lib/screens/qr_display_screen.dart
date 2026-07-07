import 'package:flutter/material.dart';

import 'home_screen.dart';

/// Renders the current payload (offer or answer) as a QR code, reused for
/// both roles per DESIGN.md section 6.
class QrDisplayScreen extends StatelessWidget {
  const QrDisplayScreen({super.key, required this.role, this.payload});

  final CallRole role;
  final String? payload;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(role == CallRole.host ? 'Offer QR' : 'Answer QR'),
      ),
      body: const Center(child: Text('QR generation not implemented yet')),
    );
  }
}
