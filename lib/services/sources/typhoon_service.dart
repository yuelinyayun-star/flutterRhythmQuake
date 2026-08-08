import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/typhoon_data.dart';

class TyphoonService {
  static const String _endpoint = 'https://api.fanstudio.tech/we/typhoon.php';
  static const Duration _timeout = Duration(seconds: 14);
  static const Duration _cacheMaxAge = Duration(hours: 24);
  static const Duration fallbackRefreshInterval = Duration(hours: 1);
  static const String _cacheBodyKey = 'typhoon_active_cache_body';
  static const String _cacheSavedAtKey = 'typhoon_active_cache_saved_at';

  Timer? _timer;
  bool _fetching = false;
  String _lastSignature = '';
  List<TyphoonData> _lastTyphoons = const [];

  void Function(List<TyphoonData> typhoons)? onActiveTyphoonsChanged;

  bool get isRunning => _timer != null;

  void start({Duration interval = fallbackRefreshInterval}) {
    _timer?.cancel();
    _emitCachedActive();
    fetchNow();
    _timer = Timer.periodic(interval, (_) => fetchNow());
  }

  void stop({bool clearState = false}) {
    _timer?.cancel();
    _timer = null;
    if (clearState) {
      _lastSignature = '';
      _lastTyphoons = const [];
    }
  }

  Future<void> fetchNow() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final result = await _fetchWithRaw(Uri.parse(_endpoint));
      final typhoons = result.typhoons;
      await _saveActiveCache(result.body, typhoons);
      final signature = typhoons.map((item) => item.signature).join('||');
      if (signature != _lastSignature || _lastTyphoons.isEmpty) {
        _lastSignature = signature;
        _lastTyphoons = List.unmodifiable(typhoons);
        onActiveTyphoonsChanged?.call(_lastTyphoons);
      }
    } catch (_) {
      // Keep the previous typhoon layer on transient network/API failures.
    } finally {
      _fetching = false;
    }
  }

  Future<List<TyphoonData>> fetchActiveNow() async {
    return (await _fetchWithRaw(Uri.parse(_endpoint))).typhoons;
  }

  Future<List<TyphoonData>> fetchById(String tfid) async {
    final id = tfid.trim();
    if (id.isEmpty) return const [];
    return (await _fetchWithRaw(
      Uri.parse(_endpoint).replace(queryParameters: {'tfid': id}),
    )).typhoons;
  }

  Future<_TyphoonFetchResult> _fetchWithRaw(Uri uri) async {
    final resp = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'User-Agent':
                'RhythmQuake/typhoon-layer (+https://api.fanstudio.tech/)',
          },
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) return const _TyphoonFetchResult('', []);

    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final decoded = json.decode(body);
    return _TyphoonFetchResult(body, TyphoonData.listFromJson(decoded));
  }

  Future<void> _emitCachedActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final body = prefs.getString(_cacheBodyKey);
      final savedAtMs = prefs.getInt(_cacheSavedAtKey);
      if (body == null || body.isEmpty || savedAtMs == null) return;

      final savedAt = DateTime.fromMillisecondsSinceEpoch(savedAtMs);
      if (DateTime.now().difference(savedAt) > _cacheMaxAge) return;

      final decoded = json.decode(body);
      final typhoons = TyphoonData.listFromJson(decoded);
      if (typhoons.isEmpty) return;

      final signature = typhoons.map((item) => item.signature).join('||');
      if (signature == _lastSignature && _lastTyphoons.isNotEmpty) return;
      _lastSignature = signature;
      _lastTyphoons = List.unmodifiable(typhoons);
      onActiveTyphoonsChanged?.call(_lastTyphoons);
    } catch (_) {}
  }

  Future<void> _saveActiveCache(String body, List<TyphoonData> typhoons) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (body.isEmpty || typhoons.isEmpty) {
        await prefs.remove(_cacheBodyKey);
        await prefs.remove(_cacheSavedAtKey);
        return;
      }
      await prefs.setString(_cacheBodyKey, body);
      await prefs.setInt(
        _cacheSavedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }
}

class _TyphoonFetchResult {
  final String body;
  final List<TyphoonData> typhoons;

  const _TyphoonFetchResult(this.body, this.typhoons);
}
