import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/obs_automation_preset.dart';
import 'obs_automation_input_service.dart';
import 'obs_automation_runner.dart';
import 'obs_websocket_service.dart';

const obsAutomationPresetsPreferenceKey = 'obs_automation_presets_v1';

class ObsAutomationRuntimeService {
  ObsAutomationRuntimeService._() {
    runner = ObsAutomationRunner(
      inputService: ObsAutomationInputService(),
      actionExecutor: ObsWebSocketActionExecutor(obs),
    );
  }

  static final ObsAutomationRuntimeService _instance =
      ObsAutomationRuntimeService._();

  factory ObsAutomationRuntimeService() => _instance;

  static const enabledPreferenceKey = 'obs_websocket_enabled';
  static const hostPreferenceKey = 'obs_websocket_host';
  static const portPreferenceKey = 'obs_websocket_port';
  static const autoReconnectPreferenceKey = 'obs_websocket_auto_reconnect';
  static const defaultHost = '127.0.0.1';
  static const defaultPort = 4455;
  static const _passwordStorageKey = 'obs_websocket_password';

  final ObsWebSocketService obs = ObsWebSocketService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ValueNotifier<bool> configuredNotifier = ValueNotifier(false);
  final ValueNotifier<String?> presetErrorNotifier = ValueNotifier(null);
  late final ObsAutomationRunner runner;

  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> initialize({SharedPreferences? preferences}) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    await reloadPresets(preferences: prefs);
    configuredNotifier.value = prefs.getBool(enabledPreferenceKey) ?? false;
    _initialized = true;
    if (configuredNotifier.value) {
      unawaited(_connectFromPreferences(prefs));
    }
  }

  Future<void> reloadPresets({SharedPreferences? preferences}) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(obsAutomationPresetsPreferenceKey);
    if (raw == null || raw.trim().isEmpty) {
      runner.configure(const []);
      presetErrorNotifier.value = null;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('invalid root');
      final document = ObsAutomationPresetDocument.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      runner.configure(document.presets);
      presetErrorNotifier.value = null;
    } catch (error) {
      runner.configure(const []);
      presetErrorNotifier.value = error.toString();
    }
  }

  Future<void> configureConnection({
    required bool enabled,
    required String host,
    required int port,
    required String password,
    required bool autoReconnect,
  }) async {
    final normalizedHost = host.trim().isEmpty ? defaultHost : host.trim();
    final normalizedPort = port.clamp(1, 65535);
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool(enabledPreferenceKey, enabled),
      prefs.setString(hostPreferenceKey, normalizedHost),
      prefs.setInt(portPreferenceKey, normalizedPort),
      prefs.setBool(autoReconnectPreferenceKey, autoReconnect),
    ]);
    if (password.isEmpty) {
      await _secureStorage.delete(key: _passwordStorageKey);
    } else {
      await _secureStorage.write(key: _passwordStorageKey, value: password);
    }
    configuredNotifier.value = enabled;
    if (!enabled) {
      await obs.disconnect();
      return;
    }
    await obs.connect(
      ObsConnectionConfig.local(
        host: normalizedHost,
        port: normalizedPort,
        password: password,
        autoReconnect: autoReconnect,
      ),
    );
  }

  Future<ObsAutomationConnectionSettings> loadConnectionSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String password = '';
    try {
      password = await _secureStorage.read(key: _passwordStorageKey) ?? '';
    } catch (_) {}
    return ObsAutomationConnectionSettings(
      enabled: prefs.getBool(enabledPreferenceKey) ?? false,
      host: prefs.getString(hostPreferenceKey) ?? defaultHost,
      port: prefs.getInt(portPreferenceKey) ?? defaultPort,
      password: password,
      autoReconnect: prefs.getBool(autoReconnectPreferenceKey) ?? true,
    );
  }

  Future<void> _connectFromPreferences(SharedPreferences prefs) async {
    final settings = await loadConnectionSettings();
    if (!settings.enabled) return;
    try {
      await obs.connect(
        ObsConnectionConfig.local(
          host: settings.host,
          port: settings.port,
          password: settings.password,
          autoReconnect: settings.autoReconnect,
        ),
      );
    } catch (error) {
      debugPrint('OBS automation connection failed: $error');
    }
  }
}

class ObsAutomationConnectionSettings {
  const ObsAutomationConnectionSettings({
    required this.enabled,
    required this.host,
    required this.port,
    required this.password,
    required this.autoReconnect,
  });

  final bool enabled;
  final String host;
  final int port;
  final String password;
  final bool autoReconnect;
}
