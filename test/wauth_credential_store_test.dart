import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/wauth_credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('login credentials survive a new store instance', () async {
    await WAuthCredentialStore().write(
      accessToken: 'oauth-test',
      apiToken: 'business-test',
    );
    final restored = await WAuthCredentialStore().readAndMigrate();
    expect(restored.accessToken, 'oauth-test');
    expect(restored.apiToken, 'business-test');
    expect(restored.hasApiToken, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('API-only credential persists without an OAuth session', () async {
    await WAuthCredentialStore().writeApiToken(apiToken: ' business-test ');
    final restored = await WAuthCredentialStore().readAndMigrate();
    expect(restored.apiToken, 'business-test');
    expect(restored.hasAccessToken, isFalse);
    expect(restored.hasApiToken, isTrue);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('saving the same token preserves the account session', () async {
    final store = WAuthCredentialStore();
    await store.write(accessToken: 'account-A', apiToken: 'business-A');
    await store.writeApiToken(apiToken: 'business-A');
    expect((await store.readAndMigrate()).accessToken, 'account-A');
  });

  test('replacing the business token clears the old account session', () async {
    final store = WAuthCredentialStore();
    await store.write(accessToken: 'account-A', apiToken: 'business-A');
    await store.writeApiToken(apiToken: 'business-B');
    final restored = await store.readAndMigrate();
    expect(restored.accessToken, isEmpty);
    expect(restored.apiToken, 'business-B');
  });

  test('empty import fails without removing the saved token', () async {
    final store = WAuthCredentialStore();
    await store.writeApiToken(apiToken: 'business-test');
    await expectLater(store.writeApiToken(apiToken: ' '), throwsArgumentError);
    expect((await store.readAndMigrate()).apiToken, 'business-test');
  });

  test(
    'legacy API-only credentials migrate and clearing removes all copies',
    () async {
      SharedPreferences.setMockInitialValues({
        WAuthCredentialStore.legacyApiTokenPreferenceKey: 'legacy-business',
      });
      final store = WAuthCredentialStore();
      expect((await store.readAndMigrate()).apiToken, 'legacy-business');
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await store.clear();
      expect(
        (await WAuthCredentialStore().readAndMigrate()).hasApiToken,
        isFalse,
      );
    },
  );
}
