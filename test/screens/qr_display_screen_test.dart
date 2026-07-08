import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:v_call_me/screens/home_screen.dart';
import 'package:v_call_me/screens/qr_display_screen.dart';
import 'package:v_call_me/services/call_session.dart';

class _FakeCallSession extends CallSession {
  _FakeCallSession(this.offer);

  final Uint8List offer;
  bool disposed = false;

  @override
  Future<Uint8List> createOffer() async => offer;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _ThrowingCallSession extends CallSession {
  @override
  Future<Uint8List> createOffer() async {
    throw UnimplementedError('offer generation not wired up yet');
  }
}

void main() {
  testWidgets('renders a QR code immediately when a payload is supplied', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrDisplayScreen(
          role: CallRole.host,
          payload: Uint8List.fromList(utf8.encode('fixed-payload')),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('host role generates its own payload via CallSession.createOffer', (tester) async {
    final session = _FakeCallSession(Uint8List.fromList(utf8.encode('generated-offer')));
    await tester.pumpWidget(
      MaterialApp(
        home: QrDisplayScreen(role: CallRole.host, session: session),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('shows an error state when offer generation fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrDisplayScreen(role: CallRole.host, session: _ThrowingCallSession()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Could not generate QR code'), findsOneWidget);
  });

  testWidgets('disposes its CallSession when popped', (tester) async {
    final session = _FakeCallSession(Uint8List.fromList(utf8.encode('generated-offer')));
    await tester.pumpWidget(
      MaterialApp(
        home: QrDisplayScreen(role: CallRole.host, session: session),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(session.disposed, isTrue);
  });
}
