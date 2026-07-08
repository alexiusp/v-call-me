import 'dart:typed_data';

import 'package:qr_flutter/qr_flutter.dart';

/// Renders QR payload data to a PNG image, for lossless file sharing per
/// DESIGN.md section 4's "practical QR/sharing notes" (file sends over photo
/// sends to avoid recompression artifacts).
Future<Uint8List?> renderQrPng(String data, {double size = 1024}) async {
  final painter = QrPainter(
    data: data,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.H,
  );
  final imageData = await painter.toImageData(size);
  return imageData?.buffer.asUint8List();
}
