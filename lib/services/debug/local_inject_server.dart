import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        kIsWeb,
        kReleaseMode,
        visibleForTesting;

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/nied_replay_logger.dart';
import '../../core/utils/quake_time.dart';
import '../../models/quake_message.dart';
import '../../widgets/map/quake_map_view.dart';
import '../sources/mock_input_service.dart';
import '../sources/nied_monitor.dart';
import '../sources/nied_yahoo_service.dart';
import '../sources/source_manager.dart';

/// Loopback HTTP façade over [MockInputService] for camera / EEW testing.
///
/// Bind: `127.0.0.1` only. Off by default; enable from Debug → 调试工具, or
/// `--dart-define=LOCAL_INJECT=true`. Optional port:
/// `--dart-define=LOCAL_INJECT_PORT=8765`.
///
/// SSH from another machine: `ssh -L 8765:127.0.0.1:8765 user@host`
class LocalInjectServer {
  LocalInjectServer._();

  static HttpServer? _server;
  static Completer<void>? _niedGifBusy;

  static const String enabledPreferenceKey = 'debug_local_inject_enabled';

  static const bool _forceEnable = bool.fromEnvironment(
    'LOCAL_INJECT',
    defaultValue: false,
  );
  static const int _port = int.fromEnvironment(
    'LOCAL_INJECT_PORT',
    defaultValue: 8765,
  );

  static bool get isRunning => _server != null;
  static int? get boundPort => _server?.port;
  static int get defaultPort => _port;
  static bool get isForcedByBuild => _forceEnable;

  static bool get isSupportedPlatform {
    if (kIsWeb || kReleaseMode) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  static bool isUserEnabled(SharedPreferences prefs) {
    return prefs.getBool(enabledPreferenceKey) ?? false;
  }

  static bool shouldStart(SharedPreferences prefs) {
    return _forceEnable || (isSupportedPlatform && isUserEnabled(prefs));
  }

  /// Start when Debug toggle (or [LOCAL_INJECT] build flag) is on.
  static Future<void> startIfEnabled({SharedPreferences? prefs}) async {
    if (!isSupportedPlatform && !_forceEnable) return;
    final enabled = prefs == null ? _forceEnable : shouldStart(prefs);
    if (!enabled) return;
    await start(port: _port);
  }

  static Future<void> setEnabled(
    bool enabled, {
    SharedPreferences? prefs,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    await store.setBool(enabledPreferenceKey, enabled);
    if (_forceEnable) {
      if (!isRunning) await start(port: _port);
      return;
    }
    if (enabled) {
      if (isSupportedPlatform) {
        await start(port: _port);
      }
    } else {
      await stop();
    }
  }

  static Future<void> start({int port = 8765}) async {
    if (_server != null) return;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server = server;
      debugPrint(
        '[LocalInject] listening on http://127.0.0.1:${server.port} '
        '(EEW / NIED GIF / K-NET / NIED replay)',
      );
      server.listen(
        _handleRequest,
        onError: (Object e, StackTrace st) {
          debugPrint('[LocalInject] listen error: $e\n$st');
        },
      );
    } catch (e, st) {
      debugPrint('[LocalInject] failed to bind :$port — $e\n$st');
    }
  }

  static Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    _allowCors(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      final path = request.uri.path;
      if (request.method == 'GET' && (path == '/' || path == '/help')) {
        await _writeJson(request.response, HttpStatus.ok, _helpPayload());
        return;
      }
      if (request.method == 'GET' && path == '/health') {
        final mock = SourceManager().getSource<MockInputService>();
        await _writeJson(request.response, HttpStatus.ok, {
          'ok': true,
          'mockRegistered': mock != null,
          'port': _server?.port,
          'niedGifBusy': _niedGifBusy != null && !(_niedGifBusy!.isCompleted),
        });
        return;
      }

      if (request.method == 'POST' && path == '/inject/eew') {
        final body = await utf8.decoder.bind(request).join();
        final freshQs = request.uri.queryParameters['fresh'];
        final freshOrigin =
            freshQs == '1' ||
            freshQs == 'true' ||
            request.uri.queryParameters.containsKey('freshOriginSeconds');
        final freshSecs =
            int.tryParse(
              request.uri.queryParameters['freshOriginSeconds'] ?? '',
            ) ??
            15;
        final count = _injectEew(
          body,
          freshOrigin: freshOrigin,
          freshOriginSeconds: freshSecs,
        );
        await _writeJson(request.response, HttpStatus.ok, {
          'ok': true,
          'injected': count.injected,
          'freshOrigin': freshOrigin,
          'wallClockOffsetHours': count.wallClockOffsetHours,
        });
        return;
      }

      if (request.method == 'POST' && path == '/inject/stop') {
        final mock = SourceManager().getSource<MockInputService>();
        final wasBusy =
            mock?.isNiedGifInjectionRunning == true ||
            (_niedGifBusy != null && !_niedGifBusy!.isCompleted);
        mock?.stopNiedGifInjection();
        await _writeJson(request.response, HttpStatus.ok, {
          'ok': true,
          'stopped': wasBusy,
          'niedGifBusy':
              mock?.isNiedGifInjectionRunning == true ||
              (_niedGifBusy != null && !_niedGifBusy!.isCompleted),
        });
        return;
      }

      // NIED GIF playback is long; don't block other inject routes.
      if (request.method == 'POST' && path == '/inject/nied-gif') {
        final body = await _readJsonObject(request);
        final gifPath = body['path']?.toString() ?? '';
        if (gifPath.trim().isEmpty) {
          throw FormatException('path 必填');
        }
        if (_niedGifBusy != null && !_niedGifBusy!.isCompleted) {
          throw StateError('NIED GIF 注入进行中');
        }
        unawaited(
          _injectNiedGif(gifPath.trim())
              .then((count) {
                debugPrint('[LocalInject] NIED GIF finished: $count s');
              })
              .catchError((Object e) {
                debugPrint('[LocalInject] NIED GIF failed: $e');
              }),
        );
        await _writeJson(request.response, HttpStatus.accepted, {
          'ok': true,
          'started': true,
          'path': gifPath.trim(),
        });
        return;
      }

      if (request.method == 'POST' && path == '/inject/knet') {
        final body = await _readJsonObject(request);
        final zipPath = body['path']?.toString() ?? '';
        if (zipPath.trim().isEmpty) {
          throw FormatException('path 必填');
        }
        final count = _injectKnet(zipPath.trim());
        await _writeJson(request.response, HttpStatus.ok, {
          'ok': true,
          'stations': count,
          'path': zipPath.trim(),
        });
        return;
      }

      if (request.method == 'POST' && path == '/nied/replay') {
        final body = await _readJsonObject(request);
        final config = _parseReplayConfig(body);
        QuakeMapView.niedReplayNotifier.value = config;
        NiedMonitorService().configureReplay(config);
        NiedYahooService().configureReplay(config);
        await _writeJson(request.response, HttpStatus.ok, {
          'ok': true,
          'enabled': config.enabled,
          'startJst': config.startJst?.toIso8601String(),
          'stepSeconds': config.stepSeconds,
        });
        return;
      }

      if (request.method == 'POST' && path == '/inject/scenario') {
        final body = await _readJsonObject(request);
        final result = await _runScenario(body);
        await _writeJson(request.response, HttpStatus.ok, result);
        return;
      }

      await _writeJson(request.response, HttpStatus.notFound, {
        'ok': false,
        'error': 'not found: ${request.method} $path',
        'help': _helpPayload(),
      });
    } catch (e) {
      debugPrint(
        '[LocalInject] ${request.method} ${request.uri.path} failed: $e',
      );
      await _writeJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': e.toString(),
      });
    }
  }

  static Map<String, dynamic> _helpPayload() {
    return {
      'service': 'LocalInjectServer',
      'bind': '127.0.0.1',
      'routes': {
        'GET /health': 'server + MockInputService status',
        'POST /inject/eew':
            'raw Wolfx/FAN/P2P JSON → MockInputService; fresh=1 按机构墙钟时区改写 (JMA/KMA UTC+9, 其他 UTC+8)',
        'POST /inject/nied-gif':
            '{"path":"..."} → GIF 回放；结束后清理并恢复原 NIED/GIF 连接',
        'POST /inject/stop': '取消进行中的 NIED GIF 注入（同样会清理并恢复连接）',
        'POST /inject/knet': '{"path":"...zip"} → K-NET 注入',
        'POST /nied/replay':
            '{"enabled":true,"startJst":"2026-05-30 23:34:00","stepSeconds":1}',
        'POST /inject/scenario':
            '{"eew":{...},"niedGifPath":"...","delayMs":800,"freshOriginSeconds":15}',
      },
      'ssh': 'ssh -L 8765:127.0.0.1:8765 user@host',
    };
  }

  static MockInputService _requireMock() {
    final mock = SourceManager().getSource<MockInputService>();
    if (mock == null) {
      throw StateError('MockInputService 未注册');
    }
    return mock;
  }

  static ({int injected, int? wallClockOffsetHours}) _injectEew(
    String raw, {
    bool freshOrigin = false,
    int? freshOriginSeconds,
  }) {
    var payload = raw.trim();
    if (payload.isEmpty) {
      throw FormatException('报文为空');
    }
    int? offsetHours;
    if (freshOrigin) {
      final rewritten = rewriteInjectOriginTimes(
        payload,
        freshOriginSeconds ?? 15,
      );
      payload = rewritten.payload;
      offsetHours = rewritten.wallClockOffsetHours;
    }
    final count = _requireMock().injectFromJs(payload);
    debugPrint(
      '[LocalInject] EEW injected: $count'
      '${offsetHours == null ? '' : ' (wall UTC+$offsetHours)'}',
    );
    return (injected: count, wallClockOffsetHours: offsetHours);
  }

  static Future<int> _injectNiedGif(String path) async {
    if (_niedGifBusy != null && !_niedGifBusy!.isCompleted) {
      throw StateError('NIED GIF 注入进行中');
    }
    _niedGifBusy = Completer<void>();
    final previousSource = QuakeMapView.niedSourceNotifier.value;
    try {
      QuakeMapView.niedSourceNotifier.value = 'lmoni';
      NiedMonitorService().stop();
      NiedYahooService().stop();
      final count = await _requireMock().injectFromNiedGifPath(path);
      debugPrint('[LocalInject] NIED GIF injected: $count s from $path');
      return count;
    } finally {
      QuakeMapView.restoreNiedLiveSource(previousSource);
      debugPrint('[LocalInject] NIED live source restored → $previousSource');
      _niedGifBusy?.complete();
      _niedGifBusy = null;
    }
  }

  static int _injectKnet(String path) {
    NiedMonitorService().stop();
    NiedYahooService().stop();
    final logger = NiedReplayLogger.instance;
    logger.setEnabled(true);
    final count = _requireMock().injectFromKnetZip(path);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 500), () async {
        await logger.save();
        logger.setEnabled(false);
      }),
    );
    debugPrint('[LocalInject] K-NET injected: $count stations');
    return count;
  }

  static Future<Map<String, dynamic>> _runScenario(
    Map<String, dynamic> body,
  ) async {
    final delayMs = (body['delayMs'] is num)
        ? (body['delayMs'] as num).toInt()
        : 800;
    final freshOrigin =
        body['freshOrigin'] == true || body['freshOriginSeconds'] != null;
    final freshOriginSeconds = (body['freshOriginSeconds'] is num)
        ? (body['freshOriginSeconds'] as num).toInt()
        : 15;

    int? eewCount;
    int? wallClockOffsetHours;
    final eew = body['eew'];
    if (eew != null) {
      final raw = eew is String ? eew : jsonEncode(eew);
      final result = _injectEew(
        raw,
        freshOrigin: freshOrigin || eew is! String,
        freshOriginSeconds: freshOriginSeconds,
      );
      eewCount = result.injected;
      wallClockOffsetHours = result.wallClockOffsetHours;
    }

    if (delayMs > 0 && body['niedGifPath'] != null) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }

    int? gifSeconds;
    final gifPath = body['niedGifPath']?.toString();
    if (gifPath != null && gifPath.trim().isNotEmpty) {
      gifSeconds = await _injectNiedGif(gifPath.trim());
    }

    final replay = body['niedReplay'];
    Map<String, dynamic>? replayResult;
    if (replay is Map<String, dynamic>) {
      final config = _parseReplayConfig(replay);
      QuakeMapView.niedReplayNotifier.value = config;
      NiedMonitorService().configureReplay(config);
      NiedYahooService().configureReplay(config);
      replayResult = {
        'enabled': config.enabled,
        'startJst': config.startJst?.toIso8601String(),
        'stepSeconds': config.stepSeconds,
      };
    }

    return {
      'ok': true,
      'eewInjected': eewCount,
      'wallClockOffsetHours': wallClockOffsetHours,
      'niedGifSeconds': gifSeconds,
      'niedReplay': replayResult,
    };
  }

  static NiedReplayConfig _parseReplayConfig(Map<String, dynamic> body) {
    final enabled = body['enabled'] == true;
    if (!enabled) return const NiedReplayConfig.disabled();
    final startText = body['startJst']?.toString() ?? '';
    final start = _parseJstWallTime(startText);
    if (start == null) {
      throw FormatException('startJst 无效，期望 "YYYY-MM-DD HH:mm:ss"');
    }
    final step = (body['stepSeconds'] is num)
        ? (body['stepSeconds'] as num).toInt()
        : 1;
    return NiedReplayConfig(
      enabled: true,
      startJst: start,
      stepSeconds: step.clamp(1, 60),
    );
  }

  static DateTime? _parseJstWallTime(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.contains('T')
        ? trimmed
        : trimmed.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;
    // Treat wall clock as JST (UTC+9) the same way settings does.
    if (parsed.isUtc) return parsed.toLocal();
    return parsed;
  }

  /// Rewrite OriginTime / AnnouncedTime / shockTime to now - N seconds so
  /// wave layers and camera follow have a live expanding radius.
  ///
  /// Wall-clock timezone follows production: JMA/KMA (+P2P/NIED) = UTC+9,
  /// everything else (CEA/CENC/USGS/CWA/…) = UTC+8.
  static ({String payload, int wallClockOffsetHours}) rewriteInjectOriginTimes(
    String raw,
    int secondsAgo, {
    DateTime? nowUtc,
  }) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return (payload: raw, wallClockOffsetHours: 8);
    }
    final offsetHours = inferInjectWallClockOffsetHours(decoded);
    final stamp = (nowUtc ?? DateTime.now().toUtc())
        .add(Duration(hours: offsetHours))
        .subtract(Duration(seconds: secondsAgo));
    final wall =
        '${stamp.year.toString().padLeft(4, '0')}-'
        '${stamp.month.toString().padLeft(2, '0')}-'
        '${stamp.day.toString().padLeft(2, '0')} '
        '${stamp.hour.toString().padLeft(2, '0')}:'
        '${stamp.minute.toString().padLeft(2, '0')}:'
        '${stamp.second.toString().padLeft(2, '0')}';

    void patch(Map<String, dynamic> map) {
      for (final key in const [
        'OriginTime',
        'originTime',
        'AnnouncedTime',
        'ReportTime',
        'shockTime',
        'createTime',
      ]) {
        if (map.containsKey(key)) map[key] = wall;
      }
      final nested = map['Data'] ?? map['data'] ?? map['payload'];
      if (nested is Map<String, dynamic>) patch(nested);
    }

    if (decoded is Map<String, dynamic>) {
      patch(decoded);
      return (payload: jsonEncode(decoded), wallClockOffsetHours: offsetHours);
    }
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) patch(item);
      }
      return (payload: jsonEncode(decoded), wallClockOffsetHours: offsetHours);
    }
    return (payload: raw, wallClockOffsetHours: offsetHours);
  }

  /// Infer source wall-clock offset the same way mock/production does.
  @visibleForTesting
  static int inferInjectWallClockOffsetHours(Object? decoded) {
    final source = inferInjectSourceType(decoded);
    if (source == null) return 8;
    return QuakeTime.wallClockOffsetHours(source);
  }

  @visibleForTesting
  static QuakeSourceType? inferInjectSourceType(Object? decoded) {
    if (decoded is List) {
      for (final item in decoded) {
        final found = inferInjectSourceType(item);
        if (found != null) return found;
      }
      return null;
    }
    if (decoded is! Map) return null;
    final json = Map<String, dynamic>.from(decoded);

    final type = json['type']?.toString() ?? '';
    switch (type) {
      case 'jma_eew':
        return QuakeSourceType.wolfx;
      case 'cenc_eew':
        return QuakeSourceType.cea;
      case 'sc_eew':
        return QuakeSourceType.sc_eew;
      case 'fj_eew':
        return QuakeSourceType.fj_eew;
      case 'cq_eew':
        return QuakeSourceType.cq_eew;
      case 'cwa_eew':
        return QuakeSourceType.cwa_eew;
    }

    final sourceHint = json['source']?.toString().toLowerCase() ?? '';
    switch (sourceHint) {
      case 'jma':
        return QuakeSourceType.jma_fan;
      case 'kma':
        return QuakeSourceType.kma_eq;
      case 'kma-eew':
        return QuakeSourceType.kma_eew_fan;
      case 'cea':
        return QuakeSourceType.cea;
      case 'cea-pr':
        return QuakeSourceType.cea_pr;
      case 'cenc':
        return QuakeSourceType.cenc;
      case 'usgs':
        return QuakeSourceType.usgs;
      case 'cwa':
        return QuakeSourceType.cwa;
      case 'cwa-eew':
        return QuakeSourceType.cwa_eew;
    }

    final code = int.tryParse(json['code']?.toString() ?? '');
    if (code == 551 ||
        code == 552 ||
        (json.containsKey('issue') && json.containsKey('earthquake'))) {
      return QuakeSourceType.p2p;
    }

    if ((json.containsKey('EventID') || json.containsKey('ID')) &&
        (json.containsKey('OriginTime') || json.containsKey('ReportTime')) &&
        (json.containsKey('Serial') || json.containsKey('AnnouncedTime'))) {
      return QuakeSourceType.wolfx;
    }

    if (json.containsKey('shockTime') ||
        json.containsKey('placeName') ||
        json.containsKey('eventId')) {
      // FAN-style without source hint: default like production non-JP path.
      return QuakeSourceType.usgs;
    }

    for (final key in const ['data', 'Data', 'payload', 'message']) {
      final nested = json[key];
      if (nested == null) continue;
      final found = inferInjectSourceType(nested);
      if (found != null) return found;
    }
    return null;
  }

  static Future<Map<String, dynamic>> _readJsonObject(
    HttpRequest request,
  ) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException('期望 JSON object');
  }

  static void _allowCors(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  }

  static Future<void> _writeJson(
    HttpResponse response,
    int status,
    Object body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
