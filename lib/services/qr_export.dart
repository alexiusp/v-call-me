import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Renders QR payload data to a PNG image, for lossless file sharing per
/// DESIGN.md section 4's "practical QR/sharing notes" (file sends over photo
/// sends to avoid recompression artifacts).
///
/// Unlike [QrImageView] on-screen (which sits on an opaque container),
/// [QrPainter.toImageData] paints onto a blank canvas with no background fill
/// of its own (its `emptyColor` only covers empty modules within the code,
/// not the quiet-zone margin around it) - so the PNG comes out with a
/// transparent margin. Some decoders (e.g. Android's) composite that as solid
/// black, making the code unreadable. Painting a white background rect
/// ourselves before the QR code avoids that.
Future<Uint8List?> renderQrPng(Uint8List data, {double size = 1024}) async {
  final qrCode = QrCode.fromUint8List(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.H,
  );
  final painter = QrPainter.withQr(qr: qrCode);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size, size),
    Paint()..color = Colors.white,
  );
  painter.paint(canvas, Size(size, size));
  final image = await recorder.endRecording().toImage(
        size.toInt(),
        size.toInt(),
      );
  final imageData = await image.toByteData(format: ui.ImageByteFormat.png);
  return imageData?.buffer.asUint8List();
}
