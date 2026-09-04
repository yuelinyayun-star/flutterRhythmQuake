import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WAuthCredentials {
  const WAuthCredentials({this.accessToken = '', this.apiToken = ''});

  final String accessToken;
  final String apiToken;

  bool get hasAccessToken => accessToken.trim().isNotEmpty;
  bool get hasApiToken => apiToken.trim().isNotEmpty;
  bool get isComplete => hasAccessToken && hasApiToken;
}

/// Stores WAuth credentials in the platform credential store.
///
/// SharedPreferences keys are read only for one-time migration. Plaintext
/// values are removed only after the secure write succeeds.
class WAuthCredentialStore {
  WAuthCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _secureAccessTokenKey = 'wauth.secure.access_token';
  static const String _secureApiTokenKey = 'wauth.secure.api_token';
  static const String legacyAccessTokenPreferenceKey = 'wauth_access_token';
  static const String legacyApiTokenPreferenceKey = 'wauth_api_token';

  final FlutterSecureStorage _storage;

  Future<WAuthCredentials> readAndMigrate({
    SharedPreferences? preferences,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    var accessToken = (await _storage.read(key: _secureAccessTokenKey))?.trim();
    var apiToken = (await _storage.read(key: _secureApiTokenKey))?.trim();

    final legacyAccess = prefs
        .getString(legacyAccessTokenPreferenceKey)
        ?.trim();
    final legacyApi = prefs.getString(legacyApiTokenPreferenceKey)?.trim();

    if ((accessToken == null || accessToken.isEmpty) &&
        legacyAccess != null &&
        legacyAccess.isNotEmpty) {
      await _storage.write(key: _secureAccessTokenKey, value: legacyAccess);
      accessToken = legacyAccess;
    }
    if ((apiToken == null || apiToken.isEmpty) &&
        legacyApi != null &&
        legacyApi.isNotEmpty) {
      await _storage.write(key: _secureApiTokenKey, value: legacyApi);
      apiToken = legacyApi;
    }

    if (accessToken?.isNotEmpty == true) {
      await prefs.remove(legacyAccessTokenPreferenceKey);
    }
    if (apiToken?.isNotEmpty == true) {
      await prefs.remove(legacyApiTokenPreferenceKey);
    }

    return WAuthCredentials(
      accessToken: accessToken ?? '',
      apiToken: apiToken ?? '',
    );
  }

  Future<void> write({
    required String accessToken,
    required String apiToken,
    SharedPreferences? preferences,
  }) async {
    final normalizedAccess = accessToken.trim();
    final normalizedApi = apiToken.trim();
    if (normalizedAccess.isEmpty || normalizedApi.isEmpty) {
      throw ArgumentError('Both WAuth access and API tokens are required.');
    }
    await _storage.write(key: _secureAccessTokenKey, value: normalizedAccess);
    await _storage.write(key: _secureApiTokenKey, value: normalizedApi);
    final prefs = preferences ?? await SharedPreferences.getInstance();
    await prefs.remove(legacyAccessTokenPreferenceKey);
    await prefs.remove(legacyApiTokenPreferenceKey);
  }

  Future<void> clear({SharedPreferences? preferences}) async {
    await _storage.delete(key: _secureAccessTokenKey);
    await _storage.delete(key: _secureApiTokenKey);
    final prefs = preferences ?? await SharedPreferences.getInstance();
    await prefs.remove(legacyAccessTokenPreferenceKey);
    await prefs.remove(legacyApiTokenPreferenceKey);
  }
}
