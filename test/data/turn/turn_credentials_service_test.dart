import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:v_call_me/data/turn/turn_credentials_service.dart';

void main() {
  test('decodes a Metered-shaped iceServers JSON array', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'v-call-me.metered.live');
      expect(request.url.path, '/api/v1/turn/credentials');
      expect(request.url.queryParameters['apiKey'], 'test-key');
      return http.Response(
        '[{"urls":"stun:stun.relay.metered.ca:80"},'
        '{"urls":"turn:global.relay.metered.ca:80","username":"u","credential":"c"}]',
        200,
      );
    });
    final service = TurnCredentialsService(client: client, apiKey: 'test-key');

    final servers = await service.fetchIceServers();

    expect(servers, [
      {'urls': 'stun:stun.relay.metered.ca:80'},
      {'urls': 'turn:global.relay.metered.ca:80', 'username': 'u', 'credential': 'c'},
    ]);
  });

  test('throws on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('nope', 403));
    final service = TurnCredentialsService(client: client, apiKey: 'bad-key');

    expect(service.fetchIceServers(), throwsA(isA<StateError>()));
  });

  test('throws FormatException on malformed JSON', () async {
    final client = MockClient((request) async => http.Response('not json', 200));
    final service = TurnCredentialsService(client: client, apiKey: 'test-key');

    expect(service.fetchIceServers(), throwsFormatException);
  });

  test('throws FormatException when the response is not a JSON array', () async {
    final client = MockClient((request) async => http.Response('{"oops": true}', 200));
    final service = TurnCredentialsService(client: client, apiKey: 'test-key');

    expect(service.fetchIceServers(), throwsFormatException);
  });

  test('dispose() does not throw when given an injected client', () async {
    final client = MockClient((request) async => http.Response('[]', 200));
    final service = TurnCredentialsService(client: client, apiKey: 'test-key');

    expect(service.dispose, returnsNormally);
  });
}
