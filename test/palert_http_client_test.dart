import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';

import 'package:flutterrhythmquake/services/sources/palert_http_client.dart';
import 'package:flutterrhythmquake/services/sources/palert_http_client_io.dart'
    show createPAlertSecurityContext, pAlertRootAsset, pAlertRootSha256;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Bundled official TWCA certificate matches the verified fingerprint',
    () async {
      final asset = await rootBundle.load(pAlertRootAsset);
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      expect(bytes, File(pAlertRootAsset).readAsBytesSync());
      expect(sha256.convert(bytes).toString(), pAlertRootSha256);
      final originalDefault = SecurityContext.defaultContext;
      final context = createPAlertSecurityContext(bytes);
      expect(context, isNot(same(originalDefault)));
      expect(SecurityContext.defaultContext, same(originalDefault));
    },
  );

  test('Missing certificate cannot be silently trusted', () {
    expect(() => createPAlertSecurityContext(const []), throwsStateError);
  });

  test(
    'Windows factory loads the bundled certificate without a network request',
    () async {
      final client = await createPAlertHttpClient();
      addTearDown(client.close);
      if (Platform.isWindows) expect(client, isA<IOClient>());
    },
  );
}
