import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/whews_socket_client.dart';

void main() {
  test('buildConnectionUri appends the API token as a query parameter', () {
    final uri = WhewsSocketClient.buildConnectionUri(
      'wss://api.beecld.com/ws/all',
      'wat_test_token',
    );

    expect(uri.scheme, 'wss');
    expect(uri.host, 'api.beecld.com');
    expect(uri.path, '/ws/all');
    expect(uri.queryParameters['token'], 'wat_test_token');
  });

  test('buildConnectionUri preserves existing query parameters', () {
    final uri = WhewsSocketClient.buildConnectionUri(
      'wss://api.2v8.cn/ws/cea_all?lang=zh',
      'wat_domestic',
    );

    expect(uri.queryParameters['lang'], 'zh');
    expect(uri.queryParameters['token'], 'wat_domestic');
  });
}
