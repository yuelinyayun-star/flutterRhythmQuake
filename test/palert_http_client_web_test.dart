import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flutterrhythmquake/services/sources/palert_http_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Conditional client factory supports the browser without native TLS',
    () async {
      final client = await createPAlertHttpClient();
      addTearDown(client.close);
      expect(client, isA<http.Client>());
    },
  );
}
