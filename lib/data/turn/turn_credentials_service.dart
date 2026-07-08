import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/turn_config.dart' as config;

/// Fetches STUN/TURN server credentials from the Metered ("Open Relay
/// Project") endpoint (DESIGN.md section 7). The response is already shaped
/// exactly like WebRTC's `iceServers` config
/// (`[{"urls": "..."}, {"urls": "...", "username": "...", "credential": "..."}]`),
/// so no reshaping is needed - callers pass the result straight through as
/// `configuration['iceServers']`.
class TurnCredentialsService {
  TurnCredentialsService({
    http.Client? client,
    String? apiKey,
    this.appName = 'v-call-me',
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _apiKey = apiKey ?? config.meteredApiKey;

  final http.Client _client;
  final bool _ownsClient;
  final String _apiKey;
  final String appName;

  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    final uri = Uri.https(
      '$appName.metered.live',
      '/api/v1/turn/credentials',
      {'apiKey': _apiKey},
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw StateError(
        'TURN credentials request failed: HTTP ${response.statusCode}',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      throw FormatException('TURN credentials response was not valid JSON: $e');
    }
    if (decoded is! List) {
      throw const FormatException('TURN credentials response was not a JSON array');
    }

    return decoded.map((entry) {
      if (entry is! Map) {
        throw const FormatException('TURN credentials entry was not a JSON object');
      }
      return Map<String, dynamic>.from(entry);
    }).toList();
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
