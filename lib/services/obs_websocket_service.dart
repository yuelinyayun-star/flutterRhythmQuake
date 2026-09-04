import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ObsConnectionState {
  disconnected,
  connecting,
  reconnecting,
  authenticating,
  connected,
  authenticationFailed,
  unsupported,
  error,
}

class ObsConnectionConfig {
  const ObsConnectionConfig({
    required this.uri,
    this.password = '',
    this.autoReconnect = true,
  });

  factory ObsConnectionConfig.local({
    String host = '127.0.0.1',
    int port = 4455,
    String password = '',
    bool autoReconnect = true,
  }) {
    return ObsConnectionConfig(
      uri: Uri(scheme: 'ws', host: host, port: port),
      password: password,
      autoReconnect: autoReconnect,
    );
  }

  final Uri uri;
  final String password;
  final bool autoReconnect;
}

class ObsServerInfo {
  const ObsServerInfo({
    required this.obsVersion,
    required this.obsWebSocketVersion,
    required this.rpcVersion,
    required this.availableRequests,
    required this.platform,
    required this.platformDescription,
  });

  final String obsVersion;
  final String obsWebSocketVersion;
  final int rpcVersion;
  final Set<String> availableRequests;
  final String platform;
  final String platformDescription;
}

class ObsRecordStatus {
  const ObsRecordStatus({
    required this.isKnown,
    required this.active,
    required this.paused,
    required this.outputState,
    required this.duration,
    required this.bytes,
    this.outputPath,
  });

  static const unknown = ObsRecordStatus(
    isKnown: false,
    active: false,
    paused: false,
    outputState: '',
    duration: Duration.zero,
    bytes: 0,
  );

  final bool isKnown;
  final bool active;
  final bool paused;
  final String outputState;
  final Duration duration;
  final int bytes;
  final String? outputPath;

  ObsRecordStatus copyWith({
    bool? isKnown,
    bool? active,
    bool? paused,
    String? outputState,
    Duration? duration,
    int? bytes,
    String? outputPath,
  }) {
    return ObsRecordStatus(
      isKnown: isKnown ?? this.isKnown,
      active: active ?? this.active,
      paused: paused ?? this.paused,
      outputState: outputState ?? this.outputState,
      duration: duration ?? this.duration,
      bytes: bytes ?? this.bytes,
      outputPath: outputPath ?? this.outputPath,
    );
  }
}

class ObsReplayBufferStatus {
  const ObsReplayBufferStatus({
    required this.isKnown,
    required this.active,
    required this.outputState,
    this.lastSavedPath,
  });

  static const unknown = ObsReplayBufferStatus(
    isKnown: false,
    active: false,
    outputState: '',
  );

  final bool isKnown;
  final bool active;
  final String outputState;
  final String? lastSavedPath;

  ObsReplayBufferStatus copyWith({
    bool? isKnown,
    bool? active,
    String? outputState,
    String? lastSavedPath,
  }) {
    return ObsReplayBufferStatus(
      isKnown: isKnown ?? this.isKnown,
      active: active ?? this.active,
      outputState: outputState ?? this.outputState,
      lastSavedPath: lastSavedPath ?? this.lastSavedPath,
    );
  }
}

class ObsRequestException implements Exception {
  const ObsRequestException({
    required this.requestType,
    required this.code,
    this.comment = '',
  });

  final String requestType;
  final int code;
  final String comment;

  @override
  String toString() {
    final suffix = comment.isEmpty ? '' : ': $comment';
    return 'OBS request $requestType failed ($code)$suffix';
  }
}

class ObsAuthenticationException implements Exception {
  const ObsAuthenticationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ObsConnectionException implements Exception {
  const ObsConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ObsWebSocketService {
  ObsWebSocketService({
    this.connectionTimeout = const Duration(seconds: 8),
    this.handshakeTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 8),
    this.replaySaveTimeout = const Duration(seconds: 20),
    this.closeTimeout = const Duration(seconds: 2),
  });

  static const int supportedRpcVersion = 1;
  static const int outputEventSubscription = 1 << 6;
  static const int authenticationFailedCloseCode = 4009;
  static const int unsupportedRpcCloseCode = 4010;
  static const int sessionInvalidatedCloseCode = 4011;
  static const int unsupportedFeatureCloseCode = 4012;

  final Duration connectionTimeout;
  final Duration handshakeTimeout;
  final Duration requestTimeout;
  final Duration replaySaveTimeout;
  final Duration closeTimeout;

  final ValueNotifier<ObsConnectionState> connectionStateNotifier =
      ValueNotifier(ObsConnectionState.disconnected);
  final ValueNotifier<ObsServerInfo?> serverInfoNotifier = ValueNotifier(null);
  final ValueNotifier<ObsRecordStatus> recordStatusNotifier = ValueNotifier(
    ObsRecordStatus.unknown,
  );
  final ValueNotifier<ObsReplayBufferStatus> replayBufferStatusNotifier =
      ValueNotifier(ObsReplayBufferStatus.unknown);
  final ValueNotifier<String?> lastErrorNotifier = ValueNotifier(null);

  ObsConnectionConfig? _config;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Completer<Map<String, dynamic>>? _helloCompleter;
  Completer<Map<String, dynamic>>? _identifiedCompleter;
  final Map<String, _PendingObsRequest> _pendingRequests = {};
  Completer<String>? _pendingReplaySave;
  Timer? _pendingReplaySaveTimer;
  String? _replayPathBeforeSave;
  bool _replaySaveRequestSent = false;
  Future<void>? _connectOperation;
  bool _shouldRun = false;
  bool _disposed = false;
  int _connectionSerial = 0;
  int _requestSerial = 0;
  int _reconnectAttempt = 0;

  bool get isConnected =>
      connectionStateNotifier.value == ObsConnectionState.connected;
  bool get isRunning => _shouldRun;
  ObsConnectionConfig? get config => _config;

  bool supportsRequest(String requestType) {
    final info = serverInfoNotifier.value;
    return info != null && info.availableRequests.contains(requestType);
  }

  Future<void> connect(ObsConnectionConfig config) async {
    _ensureNotDisposed();
    if (config.uri.scheme != 'ws' && config.uri.scheme != 'wss') {
      throw ArgumentError.value(
        config.uri,
        'uri',
        'OBS URI must use ws or wss',
      );
    }

    final sameConfig = _sameConfig(_config, config);
    if (_shouldRun && sameConfig && isConnected) return;
    if (_shouldRun && !sameConfig) {
      await disconnect();
    }

    _config = config;
    _shouldRun = true;
    _reconnectAttempt = 0;
    await _openConnection(isReconnect: false);
  }

  Future<void> reconnect() async {
    _ensureNotDisposed();
    final current = _config;
    if (current == null) {
      throw const ObsConnectionException('OBS connection is not configured.');
    }
    _shouldRun = true;
    _reconnectAttempt = 0;
    await _closeCurrentConnection();
    await _openConnection(isReconnect: false);
  }

  Future<void> disconnect() async {
    _shouldRun = false;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final activeConnect = _connectOperation;
    await _closeCurrentConnection();
    if (activeConnect != null) {
      try {
        await activeConnect;
      } catch (_) {}
    }
    _markOutputStateUnknown();
    _setConnectionState(ObsConnectionState.disconnected);
  }

  Future<void> _openConnection({required bool isReconnect}) async {
    final existing = _connectOperation;
    if (existing != null) return existing;

    late final Future<void> operation;
    operation = _performOpenConnection(isReconnect: isReconnect);
    _connectOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_connectOperation, operation)) {
        _connectOperation = null;
      }
    }
  }

  Future<void> _performOpenConnection({required bool isReconnect}) async {
    if (!_shouldRun) return;
    final currentConfig = _config;
    if (currentConfig == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final serial = ++_connectionSerial;
    _setConnectionState(
      isReconnect
          ? ObsConnectionState.reconnecting
          : ObsConnectionState.connecting,
    );
    lastErrorNotifier.value = null;

    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(currentConfig.uri);
      _channel = channel;
      await channel.ready.timeout(connectionTimeout);
      if (!_isCurrentConnection(channel, serial)) {
        await channel.sink.close();
        return;
      }

      final helloCompleter = Completer<Map<String, dynamic>>();
      final identifiedCompleter = Completer<Map<String, dynamic>>();
      _helloCompleter = helloCompleter;
      _identifiedCompleter = identifiedCompleter;
      _subscription = channel.stream.listen(
        (raw) => _handleFrame(channel!, serial, raw),
        onError: (Object error, StackTrace stackTrace) {
          _handleSocketEnded(channel!, serial, error: error);
        },
        onDone: () => _handleSocketEnded(channel!, serial),
        cancelOnError: true,
      );

      final hello = await helloCompleter.future.timeout(handshakeTimeout);
      if (!_isCurrentConnection(channel, serial)) return;
      final serverRpc = _asInt(hello['rpcVersion']);
      if (serverRpc == null || serverRpc < supportedRpcVersion) {
        throw ObsConnectionException(
          'OBS WebSocket RPC version ${serverRpc ?? 'unknown'} is unsupported.',
        );
      }

      final identifyData = <String, dynamic>{
        'rpcVersion': supportedRpcVersion,
        'eventSubscriptions': outputEventSubscription,
      };
      final requiresAuthentication = hello.containsKey('authentication');
      final authentication = _asStringMap(hello['authentication']);
      if (requiresAuthentication) {
        if (authentication == null) {
          throw const ObsConnectionException(
            'OBS WebSocket returned invalid authentication data.',
          );
        }
        _setConnectionState(ObsConnectionState.authenticating);
        if (currentConfig.password.isEmpty) {
          throw const ObsAuthenticationException(
            'OBS WebSocket requires a password.',
          );
        }
        final salt = authentication['salt']?.toString() ?? '';
        final challenge = authentication['challenge']?.toString() ?? '';
        if (salt.isEmpty || challenge.isEmpty) {
          throw const ObsConnectionException(
            'OBS WebSocket authentication data is incomplete.',
          );
        }
        identifyData['authentication'] = createAuthenticationResponse(
          password: currentConfig.password,
          salt: salt,
          challenge: challenge,
        );
      }

      channel.sink.add(jsonEncode({'op': 1, 'd': identifyData}));
      await identifiedCompleter.future.timeout(handshakeTimeout);
      if (!_isCurrentConnection(channel, serial)) return;

      _reconnectAttempt = 0;
      _setConnectionState(ObsConnectionState.connected);
      await _synchronizeServerState();
    } catch (error) {
      if (channel != null && _isCurrentConnection(channel, serial)) {
        await _handleConnectFailure(channel, serial, error);
      }
      rethrow;
    }
  }

  Future<void> _synchronizeServerState() async {
    await refreshServerInfo();
    try {
      await refreshRecordStatus();
    } catch (error) {
      debugPrint('OBS WebSocket record status sync failed: $error');
    }
    try {
      await refreshReplayBufferStatus();
    } on ObsRequestException catch (error) {
      if (error.code == 504) {
        replayBufferStatusNotifier.value = const ObsReplayBufferStatus(
          isKnown: true,
          active: false,
          outputState: 'OBS_WEBSOCKET_OUTPUT_DISABLED',
        );
      } else {
        debugPrint('OBS WebSocket replay status sync failed: $error');
      }
    }
  }

  Future<void> _handleConnectFailure(
    WebSocketChannel channel,
    int serial,
    Object error,
  ) async {
    if (!_isCurrentConnection(channel, serial)) return;
    final isAuthenticationError = error is ObsAuthenticationException;
    final isUnsupported =
        error is ObsConnectionException &&
        error.message.contains('unsupported');
    lastErrorNotifier.value = error.toString();
    _invalidateConnection(serial);
    await _cancelSubscription(_subscription);
    _subscription = null;
    try {
      await channel.sink.close().timeout(closeTimeout);
    } catch (_) {}
    if (identical(_channel, channel)) _channel = null;
    _failHandshake(error);
    _failPendingRequests(error);
    _markOutputStateUnknown();

    if (isAuthenticationError) {
      _setConnectionState(ObsConnectionState.authenticationFailed);
      return;
    }
    if (isUnsupported) {
      _setConnectionState(ObsConnectionState.unsupported);
      return;
    }
    _setConnectionState(ObsConnectionState.error);
    _scheduleReconnect();
  }

  void _handleFrame(WebSocketChannel channel, int serial, dynamic raw) {
    if (!_isCurrentConnection(channel, serial)) return;
    Map<String, dynamic>? message;
    try {
      final decoded = raw is String
          ? jsonDecode(raw)
          : jsonDecode(utf8.decode((raw as List).cast<int>()));
      message = _asStringMap(decoded);
    } catch (_) {
      return;
    }
    if (message == null) return;
    final op = _asInt(message['op']);
    final data = _asStringMap(message['d']) ?? const <String, dynamic>{};
    switch (op) {
      case 0:
        _completeIfPending(_helloCompleter, data);
      case 2:
        _completeIfPending(_identifiedCompleter, data);
      case 5:
        _handleObsEvent(data);
      case 7:
        _handleRequestResponse(data);
    }
  }

  void _handleObsEvent(Map<String, dynamic> data) {
    final eventType = data['eventType']?.toString() ?? '';
    final eventData = _asStringMap(data['eventData']) ?? const {};
    switch (eventType) {
      case 'RecordStateChanged':
        final current = recordStatusNotifier.value;
        final outputState = eventData['outputState']?.toString() ?? '';
        recordStatusNotifier.value = current.copyWith(
          isKnown: true,
          active: eventData['outputActive'] == true,
          paused: _isPausedOutputState(outputState),
          outputState: outputState,
          outputPath:
              _nonEmptyString(eventData['outputPath']) ?? current.outputPath,
        );
      case 'RecordFileChanged':
        final path = _nonEmptyString(eventData['newOutputPath']);
        if (path != null) {
          recordStatusNotifier.value = recordStatusNotifier.value.copyWith(
            isKnown: true,
            outputPath: path,
          );
        }
      case 'ReplayBufferStateChanged':
        final current = replayBufferStatusNotifier.value;
        replayBufferStatusNotifier.value = current.copyWith(
          isKnown: true,
          active: eventData['outputActive'] == true,
          outputState: eventData['outputState']?.toString() ?? '',
        );
      case 'ReplayBufferSaved':
        final path = _nonEmptyString(eventData['savedReplayPath']);
        if (path != null) {
          replayBufferStatusNotifier.value = replayBufferStatusNotifier.value
              .copyWith(isKnown: true, lastSavedPath: path);
          _completeReplaySave(path);
        }
    }
  }

  void _handleRequestResponse(Map<String, dynamic> data) {
    final requestId = data['requestId']?.toString() ?? '';
    final pending = _pendingRequests.remove(requestId);
    if (pending == null) return;
    pending.timer.cancel();
    final requestStatus = _asStringMap(data['requestStatus']) ?? const {};
    if (requestStatus['result'] == true) {
      pending.completer.complete(
        _asStringMap(data['responseData']) ?? const <String, dynamic>{},
      );
      return;
    }
    pending.completer.completeError(
      ObsRequestException(
        requestType: pending.requestType,
        code: _asInt(requestStatus['code']) ?? -1,
        comment: requestStatus['comment']?.toString() ?? '',
      ),
    );
  }

  void _handleSocketEnded(
    WebSocketChannel channel,
    int serial, {
    Object? error,
  }) {
    if (!_isCurrentConnection(channel, serial)) return;
    final closeCode = channel.closeCode;
    final failure =
        error ??
        ObsConnectionException(
          closeCode == null
              ? 'OBS WebSocket connection closed.'
              : 'OBS WebSocket connection closed ($closeCode).',
        );
    lastErrorNotifier.value = failure.toString();
    _invalidateConnection(serial);
    _subscription = null;
    if (identical(_channel, channel)) _channel = null;
    _failHandshake(failure);
    _failPendingRequests(failure);
    _markOutputStateUnknown();

    if (!_shouldRun) {
      _setConnectionState(ObsConnectionState.disconnected);
      return;
    }
    if (closeCode == authenticationFailedCloseCode) {
      _setConnectionState(ObsConnectionState.authenticationFailed);
      return;
    }
    if (closeCode == unsupportedRpcCloseCode ||
        closeCode == unsupportedFeatureCloseCode) {
      _setConnectionState(ObsConnectionState.unsupported);
      return;
    }
    if (closeCode == sessionInvalidatedCloseCode) {
      _shouldRun = false;
      _setConnectionState(ObsConnectionState.error);
      return;
    }
    _setConnectionState(ObsConnectionState.error);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final currentConfig = _config;
    if (!_shouldRun || currentConfig == null || !currentConfig.autoReconnect) {
      return;
    }
    _reconnectTimer?.cancel();
    const delays = <int>[1, 2, 5, 10, 20, 30];
    final index = _reconnectAttempt.clamp(0, delays.length - 1);
    final delay = Duration(seconds: delays[index]);
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_shouldRun) return;
      unawaited(_openConnection(isReconnect: true).catchError((Object _) {}));
    });
  }

  Future<Map<String, dynamic>> sendRequest(
    String requestType, {
    Map<String, dynamic>? requestData,
    Duration? timeout,
  }) {
    _ensureNotDisposed();
    final channel = _channel;
    if (!isConnected || channel == null) {
      return Future.error(
        const ObsConnectionException('OBS WebSocket is not connected.'),
      );
    }

    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${++_requestSerial}';
    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(timeout ?? requestTimeout, () {
      final pending = _pendingRequests.remove(requestId);
      if (pending == null || pending.completer.isCompleted) return;
      pending.completer.completeError(
        TimeoutException('OBS request timed out: $requestType'),
      );
    });
    _pendingRequests[requestId] = _PendingObsRequest(
      requestType: requestType,
      completer: completer,
      timer: timer,
    );

    final data = <String, dynamic>{
      'requestType': requestType,
      'requestId': requestId,
      if (requestData != null && requestData.isNotEmpty)
        'requestData': requestData,
    };
    try {
      channel.sink.add(jsonEncode({'op': 6, 'd': data}));
    } catch (error, stackTrace) {
      _pendingRequests.remove(requestId);
      timer.cancel();
      completer.completeError(error, stackTrace);
    }
    return completer.future;
  }

  Future<ObsServerInfo> refreshServerInfo() async {
    final response = await sendRequest('GetVersion');
    final requests =
        (response['availableRequests'] as List?)
            ?.map((item) => item.toString())
            .toSet() ??
        <String>{};
    final info = ObsServerInfo(
      obsVersion: response['obsVersion']?.toString() ?? '',
      obsWebSocketVersion: response['obsWebSocketVersion']?.toString() ?? '',
      rpcVersion: _asInt(response['rpcVersion']) ?? supportedRpcVersion,
      availableRequests: Set.unmodifiable(requests),
      platform: response['platform']?.toString() ?? '',
      platformDescription: response['platformDescription']?.toString() ?? '',
    );
    serverInfoNotifier.value = info;
    return info;
  }

  Future<ObsRecordStatus> refreshRecordStatus() async {
    final response = await sendRequest('GetRecordStatus');
    final current = recordStatusNotifier.value;
    final status = ObsRecordStatus(
      isKnown: true,
      active: response['outputActive'] == true,
      paused: response['outputPaused'] == true,
      outputState: current.outputState,
      duration: Duration(milliseconds: _asInt(response['outputDuration']) ?? 0),
      bytes: _asInt(response['outputBytes']) ?? 0,
      outputPath: current.outputPath,
    );
    recordStatusNotifier.value = status;
    return status;
  }

  Future<ObsReplayBufferStatus> refreshReplayBufferStatus() async {
    final response = await sendRequest('GetReplayBufferStatus');
    final current = replayBufferStatusNotifier.value;
    final status = current.copyWith(
      isKnown: true,
      active: response['outputActive'] == true,
    );
    replayBufferStatusNotifier.value = status;
    return status;
  }

  Future<ObsRecordStatus> startRecord() async {
    final current = await refreshRecordStatus();
    if (current.active) return current;
    try {
      await sendRequest('StartRecord');
    } on ObsRequestException catch (error) {
      if (error.code != 500) rethrow;
    }
    return refreshRecordStatus();
  }

  Future<String?> stopRecord() async {
    final current = await refreshRecordStatus();
    if (!current.active) return null;
    Map<String, dynamic> response;
    try {
      response = await sendRequest('StopRecord');
    } on ObsRequestException catch (error) {
      if (error.code != 501) rethrow;
      return null;
    }
    final path = _nonEmptyString(response['outputPath']);
    recordStatusNotifier.value = recordStatusNotifier.value.copyWith(
      isKnown: true,
      active: false,
      paused: false,
      outputState: 'OBS_WEBSOCKET_OUTPUT_STOPPED',
      outputPath: path,
    );
    return path;
  }

  Future<ObsRecordStatus> pauseRecord() async {
    final current = await refreshRecordStatus();
    if (!current.active) {
      throw const ObsRequestException(
        requestType: 'PauseRecord',
        code: 501,
        comment: 'Record output is not running.',
      );
    }
    if (current.paused) return current;
    try {
      await sendRequest('PauseRecord');
    } on ObsRequestException catch (error) {
      if (error.code != 502) rethrow;
    }
    return refreshRecordStatus();
  }

  Future<ObsRecordStatus> resumeRecord() async {
    final current = await refreshRecordStatus();
    if (!current.active) {
      throw const ObsRequestException(
        requestType: 'ResumeRecord',
        code: 501,
        comment: 'Record output is not running.',
      );
    }
    if (!current.paused) return current;
    try {
      await sendRequest('ResumeRecord');
    } on ObsRequestException catch (error) {
      if (error.code != 503) rethrow;
    }
    return refreshRecordStatus();
  }

  Future<void> splitRecordFile() async {
    await sendRequest('SplitRecordFile');
  }

  Future<void> createRecordChapter({String? chapterName}) async {
    await sendRequest(
      'CreateRecordChapter',
      requestData: {
        if (chapterName != null && chapterName.trim().isNotEmpty)
          'chapterName': chapterName.trim(),
      },
    );
  }

  Future<void> setInputText({
    required String inputName,
    required String text,
  }) async {
    await sendRequest(
      'SetInputSettings',
      requestData: {
        'inputName': inputName,
        'inputSettings': {'text': text},
        'overlay': true,
      },
    );
  }

  Future<void> setCurrentProgramScene(String sceneName) async {
    await sendRequest(
      'SetCurrentProgramScene',
      requestData: {'sceneName': sceneName},
    );
  }

  Future<void> setSceneItemEnabled({
    required String sceneName,
    required String sourceName,
    required bool enabled,
  }) async {
    final item = await sendRequest(
      'GetSceneItemId',
      requestData: {'sceneName': sceneName, 'sourceName': sourceName},
    );
    final sceneItemId = _asInt(item['sceneItemId']);
    if (sceneItemId == null) {
      throw const ObsRequestException(
        requestType: 'GetSceneItemId',
        code: 600,
        comment: 'OBS did not return a scene item ID.',
      );
    }
    await sendRequest(
      'SetSceneItemEnabled',
      requestData: {
        'sceneName': sceneName,
        'sceneItemId': sceneItemId,
        'sceneItemEnabled': enabled,
      },
    );
  }

  Future<ObsReplayBufferStatus> startReplayBuffer() async {
    final current = await refreshReplayBufferStatus();
    if (current.active) return current;
    try {
      await sendRequest('StartReplayBuffer');
    } on ObsRequestException catch (error) {
      if (error.code != 500) rethrow;
    }
    return refreshReplayBufferStatus();
  }

  Future<ObsReplayBufferStatus> stopReplayBuffer() async {
    final current = await refreshReplayBufferStatus();
    if (!current.active) return current;
    try {
      await sendRequest('StopReplayBuffer');
    } on ObsRequestException catch (error) {
      if (error.code != 501) rethrow;
    }
    return refreshReplayBufferStatus();
  }

  Future<String> saveReplayBuffer() {
    _ensureNotDisposed();
    final existing = _pendingReplaySave;
    if (existing != null) return existing.future;
    final completer = Completer<String>();
    _pendingReplaySave = completer;
    unawaited(_beginReplayBufferSave(completer));
    return completer.future;
  }

  Future<void> _beginReplayBufferSave(Completer<String> completer) async {
    try {
      final status = await refreshReplayBufferStatus();
      if (!status.active) {
        throw const ObsRequestException(
          requestType: 'SaveReplayBuffer',
          code: 501,
          comment: 'Replay buffer is not running.',
        );
      }
      String? previousPath;
      try {
        previousPath = await getLastReplayBufferReplay();
      } catch (_) {
        previousPath = replayBufferStatusNotifier.value.lastSavedPath;
      }
      if (!identical(_pendingReplaySave, completer)) return;
      _replayPathBeforeSave = previousPath;
      _replaySaveRequestSent = true;
      await sendRequest('SaveReplayBuffer');
      if (!identical(_pendingReplaySave, completer) || completer.isCompleted) {
        return;
      }
      _pendingReplaySaveTimer = Timer(replaySaveTimeout, () {
        unawaited(_recoverReplaySavePath(completer));
      });
    } catch (error, stackTrace) {
      _completeReplaySaveError(completer, error, stackTrace);
    }
  }

  Future<void> _recoverReplaySavePath(Completer<String> completer) async {
    if (!identical(_pendingReplaySave, completer) || completer.isCompleted) {
      return;
    }
    try {
      final path = await getLastReplayBufferReplay();
      if (path.isNotEmpty && path != _replayPathBeforeSave) {
        _completeReplaySave(path);
        return;
      }
    } catch (_) {}
    _completeReplaySaveError(
      completer,
      TimeoutException('OBS did not report the saved replay path.'),
      StackTrace.current,
    );
  }

  Future<String> getLastReplayBufferReplay() async {
    final response = await sendRequest('GetLastReplayBufferReplay');
    final path = _nonEmptyString(response['savedReplayPath']);
    if (path == null) {
      throw const ObsConnectionException(
        'OBS did not return a replay buffer file path.',
      );
    }
    replayBufferStatusNotifier.value = replayBufferStatusNotifier.value
        .copyWith(isKnown: true, lastSavedPath: path);
    return path;
  }

  static String createAuthenticationResponse({
    required String password,
    required String salt,
    required String challenge,
  }) {
    final secretDigest = sha256.convert(utf8.encode('$password$salt'));
    final secret = base64Encode(secretDigest.bytes);
    final authenticationDigest = sha256.convert(
      utf8.encode('$secret$challenge'),
    );
    return base64Encode(authenticationDigest.bytes);
  }

  Future<void> _closeCurrentConnection() async {
    _connectionSerial++;
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    _failHandshake(
      const ObsConnectionException('OBS WebSocket connection closed.'),
    );
    _failPendingRequests(
      const ObsConnectionException('OBS WebSocket connection closed.'),
    );
    await _cancelSubscription(subscription);
    try {
      await channel?.sink.close().timeout(closeTimeout);
    } catch (_) {}
  }

  Future<void> _cancelSubscription(
    StreamSubscription<dynamic>? subscription,
  ) async {
    if (subscription == null) return;
    try {
      await subscription.cancel().timeout(closeTimeout);
    } catch (_) {}
  }

  void _failHandshake(Object error) {
    final hello = _helloCompleter;
    final identified = _identifiedCompleter;
    _helloCompleter = null;
    _identifiedCompleter = null;
    if (hello != null && !hello.isCompleted) hello.completeError(error);
    if (identified != null && !identified.isCompleted) {
      identified.completeError(error);
    }
  }

  void _failPendingRequests(Object error) {
    final pending = _pendingRequests.values.toList(growable: false);
    _pendingRequests.clear();
    for (final request in pending) {
      request.timer.cancel();
      if (!request.completer.isCompleted) {
        request.completer.completeError(error);
      }
    }
    final replaySave = _pendingReplaySave;
    if (replaySave != null && !replaySave.isCompleted) {
      _completeReplaySaveError(replaySave, error, StackTrace.current);
    }
  }

  void _completeReplaySave(String path) {
    final completer = _pendingReplaySave;
    if (!_replaySaveRequestSent) return;
    _pendingReplaySaveTimer?.cancel();
    _pendingReplaySaveTimer = null;
    _pendingReplaySave = null;
    _replayPathBeforeSave = null;
    _replaySaveRequestSent = false;
    if (completer != null && !completer.isCompleted) {
      completer.complete(path);
    }
  }

  void _completeReplaySaveError(
    Completer<String> completer,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!identical(_pendingReplaySave, completer)) return;
    _pendingReplaySaveTimer?.cancel();
    _pendingReplaySaveTimer = null;
    _pendingReplaySave = null;
    _replayPathBeforeSave = null;
    _replaySaveRequestSent = false;
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  void _markOutputStateUnknown() {
    recordStatusNotifier.value = ObsRecordStatus.unknown;
    replayBufferStatusNotifier.value = ObsReplayBufferStatus.unknown;
  }

  void _setConnectionState(ObsConnectionState state) {
    if (connectionStateNotifier.value == state) return;
    connectionStateNotifier.value = state;
  }

  bool _isCurrentConnection(WebSocketChannel channel, int serial) {
    return _shouldRun &&
        identical(_channel, channel) &&
        _connectionSerial == serial;
  }

  void _invalidateConnection(int serial) {
    if (_connectionSerial == serial) _connectionSerial++;
  }

  static bool _sameConfig(
    ObsConnectionConfig? left,
    ObsConnectionConfig right,
  ) {
    return left?.uri == right.uri &&
        left?.password == right.password &&
        left?.autoReconnect == right.autoReconnect;
  }

  static void _completeIfPending(
    Completer<Map<String, dynamic>>? completer,
    Map<String, dynamic> value,
  ) {
    if (completer != null && !completer.isCompleted) {
      completer.complete(value);
    }
  }

  static bool _isPausedOutputState(String state) {
    return state == 'OBS_WEBSOCKET_OUTPUT_PAUSED' || state.endsWith('_PAUSED');
  }

  static Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _nonEmptyString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('ObsWebSocketService has been disposed.');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    connectionStateNotifier.dispose();
    serverInfoNotifier.dispose();
    recordStatusNotifier.dispose();
    replayBufferStatusNotifier.dispose();
    lastErrorNotifier.dispose();
  }
}

class _PendingObsRequest {
  const _PendingObsRequest({
    required this.requestType,
    required this.completer,
    required this.timer,
  });

  final String requestType;
  final Completer<Map<String, dynamic>> completer;
  final Timer timer;
}
