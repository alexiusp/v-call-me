import 'package:flutter/material.dart';

/// Camera scanner and/or gallery image picker for an offer/answer QR code,
/// reused for both roles per DESIGN.md section 6.
class QrImportScreen extends StatelessWidget {
  const QrImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan or import QR')),
      body: const Center(child: Text('QR scanning not implemented yet')),
    );
  }
}
