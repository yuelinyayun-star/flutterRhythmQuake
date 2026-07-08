import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import 'kotoho7_js_receiver_bridge_models.dart';

final _persistentReceiverBridge = _InAppWebViewKotoho7ReceiverBridge();

Kotoho7ReceiverBridgeResult kotoho7JsReceiverBridge(
  Kotoho7ReceiverBridgeInput input,
) {
  if (input.persistent) {
    return _persistentReceiverBridge.run(input);
  }
  final script = File(input.scriptPath);
  if (!script.existsSync()) {
    return Kotoho7ReceiverBridgeResult.unavailable(
      'kotoho7_receiver_bridge_script_not_found:${input.scriptPath}',
    );
  }
  if (input.observations.isEmpty) {
    return const Kotoho7ReceiverBridgeResult(
      ok: false,
      available: true,
      error: 'kotoho7_receiver_bridge_empty_observations',
    );
  }

  final stopwatch = Stopwatch()..start();
  final tempDir = Directory.systemTemp.createTempSync(
    'rhythmquake_kotoho7_receiver_',
  );
  try {
    final inputFile = File('${tempDir.path}${Platform.pathSeparator}in.json');
    final outputFile = File('${tempDir.path}${Platform.pathSeparator}out.json');
    inputFile.writeAsStringSync(
      jsonEncode({
        'schemaVersion': 'kotoho7_receiver_observations_v1',
        'observations': [
          for (final observation in input.observations) observation.toJson(),
        ],
      }),
      encoding: utf8,
      flush: true,
    );

    final args = <String>[
      input.scriptPath,
      'observations',
      inputFile.path,
      if (input.cloudRt) '--cloud-rt',
      if (input.traceStations) '--trace-stations',
      if (!input.runHyp) '--no-hyp',
      '--output',
      outputFile.path,
      '--quiet',
    ];

    ProcessResult result;
    try {
      // Current SourceEstimator is synchronous; keep this as a short-lived
      // local Node invocation and rely on caller-side frame caps for runtime.
      result = Process.runSync(
        'node',
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } on Object catch (error) {
      return Kotoho7ReceiverBridgeResult.unavailable(
        'kotoho7_receiver_bridge_process_error:$error',
      );
    }

    stopwatch.stop();
    if (result.exitCode != 0) {
      return Kotoho7ReceiverBridgeResult(
        ok: false,
        available: true,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        error:
            'kotoho7_receiver_bridge_exit_${result.exitCode}:'
            '${result.stderr?.toString() ?? result.stdout?.toString() ?? ''}',
      );
    }
    if (!outputFile.existsSync()) {
      return Kotoho7ReceiverBridgeResult(
        ok: false,
        available: true,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        error: 'kotoho7_receiver_bridge_output_missing',
      );
    }

    final decoded = jsonDecode(outputFile.readAsStringSync(encoding: utf8));
    if (decoded is! Map) {
      return Kotoho7ReceiverBridgeResult(
        ok: false,
        available: true,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        error: 'kotoho7_receiver_bridge_output_not_object',
      );
    }
    return Kotoho7ReceiverBridgeResult(
      ok: true,
      available: true,
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      result: objectMap(decoded),
    );
  } on Object catch (error) {
    return Kotoho7ReceiverBridgeResult(
      ok: false,
      available: true,
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      error: 'kotoho7_receiver_bridge_json_error:$error',
    );
  } finally {
    try {
      tempDir.deleteSync(recursive: true);
    } on Object {
      // Best-effort temp cleanup.
    }
  }
}

Kotoho7ReceiverBridgeResult? kotoho7JsReceiverBridgeLatest(String sessionKey) {
  return _persistentReceiverBridge.latest(sessionKey);
}

Kotoho7ReceiverBridgeQueueStatus kotoho7JsReceiverBridgeQueueStatus() {
  return _persistentReceiverBridge.queueStatus();
}

class _InAppWebViewKotoho7ReceiverBridge {
  WebviewController? _controller;
  Future<void>? _initializing;
  StreamSubscription<dynamic>? _webMessageSub;
  int _nextRequestId = 1;

  final Map<String, List<Kotoho7ReceiverBridgeInput>> _pendingBySession =
      <String, List<Kotoho7ReceiverBridgeInput>>{};
  final Set<String> _inFlightSessions = <String>{};
  final Map<int, String> _sessionByRequestId = <int, String>{};
  final Map<int, Stopwatch> _stopwatchByRequestId = <int, Stopwatch>{};
  final Map<int, Timer> _timeoutByRequestId = <int, Timer>{};
  final Map<String, Kotoho7ReceiverBridgeResult> _latestBySession =
      <String, Kotoho7ReceiverBridgeResult>{};
  final Map<String, String> _lastErrorBySession = <String, String>{};
  final Map<String, String> _lastLoggedErrorBySession = <String, String>{};
  final Map<String, String> _lastLoggedStatusBySession = <String, String>{};
  final Map<String, int> _droppedPendingBySession = <String, int>{};

  Kotoho7ReceiverBridgeResult run(Kotoho7ReceiverBridgeInput input) {
    if (input.observations.isEmpty) {
      return const Kotoho7ReceiverBridgeResult(
        ok: false,
        available: true,
        error: 'kotoho7_receiver_bridge_empty_observations',
      );
    }
    _ensureInitialized();
    final queued = _enqueueInput(input);
    _logSessionStatus(
      input.sessionKey,
      'queued=$queued observations=${input.observations.length} '
      'controllerReady=${_controller != null} '
      'inFlight=${_inFlightSessions.contains(input.sessionKey)} '
      'dropped=${_droppedPendingBySession[input.sessionKey] ?? 0}',
    );
    _drainSession(input.sessionKey);
    final latest = _latestBySession[input.sessionKey];
    if (latest != null) return latest;
    return Kotoho7ReceiverBridgeResult(
      ok: false,
      available: true,
      error:
          _lastErrorBySession[input.sessionKey] ??
          'kotoho7_receiver_bridge_in_app_pending',
    );
  }

  Kotoho7ReceiverBridgeResult? latest(String sessionKey) {
    return _latestBySession[sessionKey];
  }

  Kotoho7ReceiverBridgeQueueStatus queueStatus() {
    var pendingFrameCount = 0;
    for (final queue in _pendingBySession.values) {
      pendingFrameCount += queue.length;
    }
    return Kotoho7ReceiverBridgeQueueStatus(
      pendingFrameCount: pendingFrameCount,
      inFlightSessionCount: _inFlightSessions.length,
      sessionCount: _pendingBySession.length + _inFlightSessions.length,
    );
  }

  void _ensureInitialized() {
    if (_controller != null || _initializing != null) return;
    _initializing = _initialize();
    _initializing!.whenComplete(() {
      _initializing = null;
      for (final session in List<String>.from(_pendingBySession.keys)) {
        _drainSession(session);
      }
    });
  }

  int _enqueueInput(Kotoho7ReceiverBridgeInput input) {
    final queue = _pendingBySession.putIfAbsent(
      input.sessionKey,
      () => <Kotoho7ReceiverBridgeInput>[],
    );
    final inputFrameKey = _inputFrameKey(input);
    if (queue.isNotEmpty && _inputFrameKey(queue.last) == inputFrameKey) {
      queue[queue.length - 1] = input;
      _droppedPendingBySession[input.sessionKey] =
          (_droppedPendingBySession[input.sessionKey] ?? 0) + 1;
      return queue.length;
    }
    queue.add(input);
    return queue.length;
  }

  Future<void> _initialize() async {
    try {
      final version = await WebviewController.getWebViewVersion();
      if (version == null || version.isEmpty) {
        _markAllPending('kotoho7_receiver_webview2_runtime_missing');
        return;
      }
      debugPrint('[Kotoho7ReceiverBridge] WebView2 version: $version');
      final controller = WebviewController();
      await controller.initialize();
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      final loaded = Completer<void>();
      late final StreamSubscription<LoadingState> loadingSub;
      loadingSub = controller.loadingState.listen((state) {
        if (!loaded.isCompleted && state == LoadingState.navigationCompleted) {
          loaded.complete();
        }
      });
      final loadErrorSub = controller.onLoadError.listen((error) {
        debugPrint('[Kotoho7ReceiverBridge] WebView load error: $error');
      });
      final core = await rootBundle.loadString(
        'assets/kotoho7/kotoho7_receiver_compiled_core.js',
      );
      final runtime = await rootBundle.loadString(
        'assets/kotoho7/kotoho7_receiver_web_runtime.js',
      );
      final runtimeUri = await _writeRuntimeFiles(core: core, runtime: runtime);
      await controller.loadUrl(runtimeUri.toString());
      await loaded.future.timeout(const Duration(seconds: 8), onTimeout: () {});
      await loadingSub.cancel();
      await loadErrorSub.cancel();
      final ready = await controller.executeScript(
        'typeof window.Kotoho7ReceiverRuntime === "object"',
      );
      if (!_isTruthyScriptResult(ready)) {
        final detail = await controller.executeScript(
          'JSON.stringify({'
          'ready: typeof window.Kotoho7ReceiverRuntime,'
          'coreKeys: window.module && window.module.exports ? Object.keys(window.module.exports).slice(0,8) : null,'
          'error: window.__kotoho7ReceiverRuntimeError || null'
          '})',
        );
        _markAllPending(
          'kotoho7_receiver_in_app_runtime_not_ready:$ready detail:$detail',
        );
        return;
      }
      await _webMessageSub?.cancel();
      _webMessageSub = controller.webMessage.listen(
        _handleWebMessage,
        onError: (Object error) {
          debugPrint('[Kotoho7ReceiverBridge] WebMessage error: $error');
        },
      );
      _controller = controller;
      debugPrint(
        '[Kotoho7ReceiverBridge] in-app JS runtime ready (webMessage)',
      );
    } catch (error) {
      _markAllPending('kotoho7_receiver_in_app_init_error:$error');
    }
  }

  Future<Uri> _writeRuntimeFiles({
    required String core,
    required String runtime,
  }) async {
    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'rhythmquake_kotoho7_receiver_webview',
    );
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final coreFile = File(
      '${directory.path}${Platform.pathSeparator}'
      'kotoho7_receiver_compiled_core.js',
    );
    final runtimeFile = File(
      '${directory.path}${Platform.pathSeparator}'
      'kotoho7_receiver_web_runtime.js',
    );
    final htmlFile = File(
      '${directory.path}${Platform.pathSeparator}'
      'kotoho7_receiver_runtime.html',
    );
    coreFile.writeAsStringSync(core, encoding: utf8, flush: true);
    runtimeFile.writeAsStringSync(runtime, encoding: utf8, flush: true);
    htmlFile.writeAsStringSync(
      '<!doctype html><html><head><meta charset="utf-8"></head><body>'
      '<script>'
      'window.__kotoho7ReceiverRuntimeError=null;'
      'window.onerror=function(message,source,lineno,colno,error){'
      'window.__kotoho7ReceiverRuntimeError=String(message)+" @"+String(source)+":"+String(lineno)+":"+String(colno);'
      '};'
      'window.module={exports:{}};'
      'window.exports=window.module.exports;'
      'window.require={main:null};'
      '</script>'
      '<script src="kotoho7_receiver_compiled_core.js"></script>'
      '<script src="kotoho7_receiver_web_runtime.js"></script>'
      '</body></html>',
      encoding: utf8,
      flush: true,
    );
    return htmlFile.uri;
  }

  void _drainSession(String sessionKey) {
    if (_inFlightSessions.contains(sessionKey)) return;
    final controller = _controller;
    if (controller == null) return;
    final queue = _pendingBySession[sessionKey];
    if (queue == null || queue.isEmpty) return;
    final input = queue.removeAt(0);
    if (queue.isEmpty) {
      _pendingBySession.remove(sessionKey);
    }
    _inFlightSessions.add(sessionKey);
    final id = _nextRequestId++;
    final compactObservedAt = _compactObservedAt(input.observations);
    final canUseCompactPayload = compactObservedAt != null;
    final payload = <String, Object?>{
      'id': id,
      'sessionKey': sessionKey,
      'reset': input.resetSession,
      'runHyp': input.runHyp,
      if (canUseCompactPayload) ...{
        'observedAtUtc': compactObservedAt,
        'compactObservations': [
          for (final observation in input.observations)
            [
              observation.scratchTenIndex,
              observation.gifDecodedShindo,
              observation.stationCode,
            ],
        ],
      } else
        'observations': [
          for (final observation in input.observations) observation.toJson(),
        ],
    };
    final encoded = jsonEncode(payload);
    _sessionByRequestId[id] = sessionKey;
    _stopwatchByRequestId[id] = Stopwatch()..start();
    _timeoutByRequestId[id] = Timer(input.timeout, () {
      if (_sessionByRequestId.remove(id) == null) return;
      _stopwatchByRequestId.remove(id);
      _timeoutByRequestId.remove(id);
      _setSessionError(
        sessionKey,
        'kotoho7_receiver_in_app_web_message_timeout',
      );
      _inFlightSessions.remove(sessionKey);
      _drainSession(sessionKey);
    });
    controller.postWebMessage(encoded).catchError((Object error) {
      _sessionByRequestId.remove(id);
      _stopwatchByRequestId.remove(id);
      _timeoutByRequestId.remove(id)?.cancel();
      _setSessionError(
        sessionKey,
        'kotoho7_receiver_in_app_post_message_error:$error',
      );
      _inFlightSessions.remove(sessionKey);
      _drainSession(sessionKey);
    });
  }

  void _handleWebMessage(Object? message) {
    final decoded = objectMap(message);
    final id = _intFromObject(decoded['id']);
    if (id == null) {
      debugPrint('[Kotoho7ReceiverBridge] webMessage without id: $message');
      return;
    }
    final sessionKey = _sessionByRequestId.remove(id);
    if (sessionKey == null) return;
    final stopwatch = _stopwatchByRequestId.remove(id);
    stopwatch?.stop();
    _timeoutByRequestId.remove(id)?.cancel();

    final ok = decoded['ok'] == true;
    if (!ok) {
      _setSessionError(
        sessionKey,
        'kotoho7_receiver_in_app_web_message_error:${decoded['error']}',
      );
      _inFlightSessions.remove(sessionKey);
      _drainSession(sessionKey);
      return;
    }

    final result = objectMap(decoded['result']);
    _latestBySession[sessionKey] = Kotoho7ReceiverBridgeResult(
      ok: true,
      available: true,
      elapsedMilliseconds: stopwatch?.elapsedMilliseconds,
      result: result,
    );
    _clearSessionError(sessionKey);
    _logSuccess(sessionKey, result);
    _inFlightSessions.remove(sessionKey);
    _drainSession(sessionKey);
  }

  void _markAllPending(String error) {
    for (final session in List<String>.from(_pendingBySession.keys)) {
      _setSessionError(session, error);
    }
  }

  void _setSessionError(String sessionKey, String error) {
    _lastErrorBySession[sessionKey] = error;
    if (error.startsWith('kotoho7_receiver_in_app_runtime_not_ready') ||
        error.startsWith('kotoho7_receiver_in_app_init_error') ||
        error.startsWith('kotoho7_receiver_webview2_runtime_missing')) {
      _pendingBySession.remove(sessionKey);
    }
    if (_lastLoggedErrorBySession[sessionKey] == error) return;
    _lastLoggedErrorBySession[sessionKey] = error;
    debugPrint('[Kotoho7ReceiverBridge] $sessionKey: $error');
  }

  void _clearSessionError(String sessionKey) {
    _lastErrorBySession.remove(sessionKey);
    _lastLoggedErrorBySession.remove(sessionKey);
  }

  bool _isTruthyScriptResult(Object? value) {
    if (value == true) return true;
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == '"true"';
  }

  void _logSuccess(String sessionKey, Map<String, Object?> result) {
    final finalState = objectMap(result['final']);
    final best = objectMap(result['bestSourceByError']);
    final source = objectMap(best['source']);
    final status =
        'ok processed=${result['processedFrameCount']} '
        'peakIds=${result['peakDetectionIdCount']} '
        'peakEstimated=${result['peakEstimatedStations']} '
        'finalIds=${finalState['detectionIdCount']} '
        'finalEstimated=${finalState['estimatedStations']} '
        'finalPermitted=${finalState['permittedStations']} '
        'bestLat=${source['lat']} bestLon=${source['lon']} '
        'bestDepth=${source['depthKm']} bestError=${best['error']}';
    _logSessionStatus(sessionKey, status);
  }

  void _logSessionStatus(String sessionKey, String status) {
    if (!kDebugMode) return;
    if (_lastLoggedStatusBySession[sessionKey] == status) return;
    _lastLoggedStatusBySession[sessionKey] = status;
    debugPrint('[Kotoho7ReceiverBridge] $sessionKey: $status');
  }

  String? _compactObservedAt(List<Kotoho7ReceiverObservation> observations) {
    String? observedAtUtc;
    for (final observation in observations) {
      if (observation.scratchTenIndex == null) return null;
      final itemObservedAtUtc = observation.observedAtUtc
          .toUtc()
          .toIso8601String();
      if (observedAtUtc == null) {
        observedAtUtc = itemObservedAtUtc;
      } else if (observedAtUtc != itemObservedAtUtc) {
        return null;
      }
    }
    return observedAtUtc;
  }

  String _inputFrameKey(Kotoho7ReceiverBridgeInput input) {
    final compactObservedAt = _compactObservedAt(input.observations);
    if (compactObservedAt != null) return compactObservedAt;
    if (input.observations.isEmpty) return 'empty';
    final first = input.observations.first.observedAtUtc
        .toUtc()
        .toIso8601String();
    final last = input.observations.last.observedAtUtc
        .toUtc()
        .toIso8601String();
    return '$first/$last/${input.observations.length}';
  }

  int? _intFromObject(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
