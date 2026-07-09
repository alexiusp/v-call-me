import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:v_call_me/services/qr_link_codec.dart';

void main() {
  test('round-trips a payload through buildShareLink/decodeShareLink', () {
    final payload = Uint8List.fromList(List.generate(120, (i) => i * 3 % 256));

    final link = buildShareLink(payload);
    final decoded = decodeShareLink(link);

    expect(decoded, payload);
  });

  test('buildShareLink produces a vcallme://call link', () {
    final link = buildShareLink(Uint8List.fromList([1, 2, 3]));

    expect(link.scheme, 'vcallme');
    expect(link.host, 'call');
  });

  test('decodeShareLink returns null for a link with the wrong scheme', () {
    final decoded = decodeShareLink(Uri.parse('https://example.com/call?d=AQID'));

    expect(decoded, isNull);
  });

  test('decodeShareLink returns null for a link with the wrong host', () {
    final decoded = decodeShareLink(Uri.parse('vcallme://other?d=AQID'));

    expect(decoded, isNull);
  });

  test('decodeShareLink returns null when the d parameter is missing', () {
    final decoded = decodeShareLink(Uri.parse('vcallme://call'));

    expect(decoded, isNull);
  });

  test('decodeShareLink returns null for invalid base64url', () {
    final decoded = decodeShareLink(Uri.parse('vcallme://call?d=not-valid-base64!!'));

    expect(decoded, isNull);
  });
}
