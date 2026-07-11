import 'dart:convert';
import 'dart:typed_data';

const _scheme = 'vcallme';
const _host = 'call';

/// Encodes an offer/answer payload as a `vcallme://call?d=...` link - the
/// same bytes the QR code carries, just base64url-in-a-URI instead of pixels,
/// so it can be shared as plain text and opened with a tap (see
/// `deep_link_listener.dart`) instead of requiring a scan or gallery import.
Uri buildShareLink(Uint8List payload) {
  return Uri(
    scheme: _scheme,
    host: _host,
    queryParameters: {'d': base64Url.encode(payload)},
  );
}

/// Recovers the payload from a `vcallme://call?d=...` link, or `null` if
/// [uri] isn't one of ours or its `d` parameter isn't valid base64url.
Uint8List? decodeShareLink(Uri uri) {
  if (uri.scheme != _scheme || uri.host != _host) return null;
  final encoded = uri.queryParameters['d'];
  if (encoded == null) return null;
  try {
    return base64Url.decode(base64Url.normalize(encoded));
  } catch (_) {
    return null;
  }
}

/// Recovers the payload from the text content of a scanned QR code.
///
/// The QR carries the same `vcallme://call?d=...` URI as [buildShareLink] -
/// text, not raw byte-mode bytes - so it round-trips through a scanner's
/// `rawValue` on every platform. (Reading raw byte-mode content via `rawBytes`
/// works natively but not on web, where scanners surface the QR bitstream's
/// mode indicator instead of the payload.) Returns null if [text] is empty or
/// isn't one of our links.
Uint8List? decodeQrText(String? text) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  return decodeShareLink(uri);
}
