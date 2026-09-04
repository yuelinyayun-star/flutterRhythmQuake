import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/obs_websocket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates the OBS 5.x SHA-256 challenge response', () {
    final response = ObsWebSocketService.createAuthenticationResponse(
      password: 'supersecretpassword',
      salt: 'lM1GncleQOaCu9lT1yeUZhFYnqhsLLP1G5lAGo3ixaI=',
      challenge: '+IxH4CnCiqpX1rM9scsNynZzbOe4KhDeYcTNS3PDaeY=',
    );

    expect(response, '1Ct943GAT+6YQUUX47Ia/ncufilbe6+oD6lY+5kaCu4=');
  });

  test('connects, identifies, and synchronizes OBS output status', () async {
    final server = await _FakeObsServer.start(replayActive: true);
    final service = ObsWebSocketService();
    addTearDown(() async {
      await service.dispose();
      await server.close();
    });

    await service.connect(
      ObsConnectionConfig(uri: server.uri, autoReconnect: false),
    );

    expect(service.connectionStateNotifier.value, ObsConnectionState.connected);
    expect(
      server.eventSubscriptions,
      ObsWebSocketService.outputEventSubscription,
    );
    expect(service.serverInfoNotifier.value?.obsVersion, '32.2.2');
    expect(service.serverInfoNotifier.value?.obsWebSocketVersion, '5.7.4');
    expect(service.supportsRequest('StartRecord'), isTrue);
    expect(service.supportsRequest('SetCurrentProgramScene'), isTrue);
    expect(service.recordStatusNotifier.value.isKnown, isTrue);
    expect(service.recordStatusNotifier.value.active, isFalse);
    expect(service.replayBufferStatusNotifier.value.isKnown, isTrue);
    expect(service.replayBufferStatusNotifier.value.active, isTrue);
  });

  test('authenticates and reports an invalid OBS password', () async {
    final authenticatedServer = await _FakeObsServer.start(
      password: 'supersecretpassword',
    );
    final authenticatedService = ObsWebSocketService();
    addTearDown(() async {
      await authenticatedService.dispose();
      await authenticatedServer.close();
    });

    await authenticatedService.connect(
      ObsConnectionConfig(
        uri: authenticatedServer.uri,
        password: 'supersecretpassword',
        autoReconnect: false,
      ),
    );
    expect(
      authenticatedService.connectionStateNotifier.value,
      ObsConnectionState.connected,
    );

    final rejectedServer = await _FakeObsServer.start(
      password: 'supersecretpassword',
    );
    final rejectedService = ObsWebSocketService();
    addTearDown(() async {
      await rejectedService.dispose();
      await rejectedServer.close();
    });

    await expectLater(
      rejectedService.connect(
        ObsConnectionConfig(
          uri: rejectedServer.uri,
          password: 'wrong-password',
          autoReconnect: false,
        ),
      ),
      throwsA(isA<ObsConnectionException>()),
    );
    expect(
      rejectedService.connectionStateNotifier.value,
      ObsConnectionState.authenticationFailed,
    );
  });

  test('controls recording idempotently and follows output events', () async {
    final server = await _FakeObsServer.start();
    final service = ObsWebSocketService();
    addTearDown(() async {
      await service.dispose();
      await server.close();
    });
    await service.connect(
      ObsConnectionConfig(uri: server.uri, autoReconnect: false),
    );

    final started = await service.startRecord();
    expect(started.active, isTrue);
    await service.startRecord();
    expect(server.requestCount('StartRecord'), 1);

    final paused = await service.pauseRecord();
    expect(paused.paused, isTrue);
    final resumed = await service.resumeRecord();
    expect(resumed.paused, isFalse);

    await service.splitRecordFile();
    await service.createRecordChapter(chapterName: 'EEW #1');
    expect(server.lastChapterName, 'EEW #1');
    await service.setInputText(inputName: '地震字幕', text: 'UI 标题');
    expect(server.lastInputName, '地震字幕');
    expect(server.lastInputText, 'UI 标题');
    expect(server.lastInputOverlay, isTrue);
    await service.setCurrentProgramScene('地震画面');
    expect(server.lastProgramScene, '地震画面');
    await service.setSceneItemEnabled(
      sceneName: '地震画面',
      sourceName: '地震字幕',
      enabled: false,
    );
    expect(server.lastSceneItemEnabled, isFalse);

    final outputPath = await service.stopRecord();
    expect(outputPath, r'C:\OBS\recording.mkv');
    expect(service.recordStatusNotifier.value.active, isFalse);
    await service.stopRecord();
    expect(server.requestCount('StopRecord'), 1);
  });

  test('starts, saves, and stops the replay buffer', () async {
    final server = await _FakeObsServer.start();
    final service = ObsWebSocketService();
    addTearDown(() async {
      await service.dispose();
      await server.close();
    });
    await service.connect(
      ObsConnectionConfig(uri: server.uri, autoReconnect: false),
    );

    await expectLater(
      service.saveReplayBuffer(),
      throwsA(
        isA<ObsRequestException>().having((error) => error.code, 'code', 501),
      ),
    );

    final started = await service.startReplayBuffer();
    expect(started.active, isTrue);
    await service.startReplayBuffer();
    expect(server.requestCount('StartReplayBuffer'), 1);

    final savedPath = await service.saveReplayBuffer();
    expect(savedPath, r'C:\OBS\Replay 1.mkv');
    expect(
      service.replayBufferStatusNotifier.value.lastSavedPath,
      r'C:\OBS\Replay 1.mkv',
    );

    final stopped = await service.stopReplayBuffer();
    expect(stopped.active, isFalse);
    await service.stopReplayBuffer();
    expect(server.requestCount('StopReplayBuffer'), 1);
  });

  test(
    'reconnects after OBS closes the socket and resynchronizes state',
    () async {
      final server = await _FakeObsServer.start(replayActive: true);
      final service = ObsWebSocketService();
      addTearDown(() async {
        await service.dispose();
        await server.close();
      });
      await service.connect(ObsConnectionConfig(uri: server.uri));
      expect(server.connectionCount, 1);

      await server.closeClientSockets();
      await _waitUntil(
        () =>
            server.connectionCount >= 2 &&
            service.isConnected &&
            service.recordStatusNotifier.value.isKnown &&
            service.replayBufferStatusNotifier.value.isKnown,
        timeout: const Duration(seconds: 4),
      );

      expect(service.recordStatusNotifier.value.isKnown, isTrue);
      expect(service.replayBufferStatusNotifier.value.isKnown, isTrue);
      expect(service.replayBufferStatusNotifier.value.active, isTrue);
    },
  );
}

Future<void> _waitUntil(
  bool Function() predicate, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition was not met within $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _FakeObsServer {
  _FakeObsServer._(
    this._server, {
    required this.password,
    required bool replayActive,
  }) : _replayActive = replayActive;

  static const _salt = 'lM1GncleQOaCu9lT1yeUZhFYnqhsLLP1G5lAGo3ixaI=';
  static const _challenge = '+IxH4CnCiqpX1rM9scsNynZzbOe4KhDeYcTNS3PDaeY=';
  static const _expectedAuthentication =
      '1Ct943GAT+6YQUUX47Ia/ncufilbe6+oD6lY+5kaCu4=';

  final HttpServer _server;
  final String? password;
  final List<WebSocket> _sockets = [];
  final Map<String, int> _requestCounts = {};
  bool _recordActive = false;
  bool _recordPaused = false;
  bool _replayActive;
  String _lastReplayPath = r'C:\OBS\old-replay.mkv';
  int? eventSubscriptions;
  String? lastChapterName;
  String? lastInputName;
  String? lastInputText;
  bool? lastInputOverlay;
  String? lastProgramScene;
  bool? lastSceneItemEnabled;
  int connectionCount = 0;

  Uri get uri => Uri(
    scheme: 'ws',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
  );

  int requestCount(String requestType) => _requestCounts[requestType] ?? 0;

  static Future<_FakeObsServer> start({
    String? password,
    bool replayActive = false,
  }) async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final result = _FakeObsServer._(
      httpServer,
      password: password,
      replayActive: replayActive,
    );
    httpServer.listen(result._handleHttpRequest);
    return result;
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    connectionCount++;
    _sockets.add(socket);
    socket.add(
      jsonEncode({
        'op': 0,
        'd': {
          'obsStudioVersion': '32.2.2',
          'obsWebSocketVersion': '5.7.4',
          'rpcVersion': 1,
          if (password != null)
            'authentication': {'salt': _salt, 'challenge': _challenge},
        },
      }),
    );
    socket.listen(
      (raw) => _handleMessage(socket, raw),
      onDone: () => _sockets.remove(socket),
    );
  }

  void _handleMessage(WebSocket socket, dynamic raw) {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    final op = message['op'] as int;
    final data = (message['d'] as Map).cast<String, dynamic>();
    if (op == 1) {
      eventSubscriptions = data['eventSubscriptions'] as int?;
      if (password != null &&
          data['authentication'] != _expectedAuthentication) {
        socket.close(ObsWebSocketService.authenticationFailedCloseCode);
        return;
      }
      socket.add(
        jsonEncode({
          'op': 2,
          'd': {'negotiatedRpcVersion': 1},
        }),
      );
      return;
    }
    if (op != 6) return;
    _handleRequest(socket, data);
  }

  void _handleRequest(WebSocket socket, Map<String, dynamic> data) {
    final requestType = data['requestType'] as String;
    final requestId = data['requestId'] as String;
    final requestData = (data['requestData'] as Map?)?.cast<String, dynamic>();
    _requestCounts.update(requestType, (value) => value + 1, ifAbsent: () => 1);

    switch (requestType) {
      case 'GetVersion':
        _success(socket, requestType, requestId, {
          'obsVersion': '32.2.2',
          'obsWebSocketVersion': '5.7.4',
          'rpcVersion': 1,
          'availableRequests': const [
            'GetVersion',
            'GetRecordStatus',
            'StartRecord',
            'StopRecord',
            'PauseRecord',
            'ResumeRecord',
            'SplitRecordFile',
            'CreateRecordChapter',
            'SetInputSettings',
            'SetCurrentProgramScene',
            'GetSceneItemId',
            'SetSceneItemEnabled',
            'GetReplayBufferStatus',
            'StartReplayBuffer',
            'StopReplayBuffer',
            'SaveReplayBuffer',
            'GetLastReplayBufferReplay',
          ],
          'platform': 'windows',
          'platformDescription': 'Windows',
        });
      case 'GetRecordStatus':
        _success(socket, requestType, requestId, {
          'outputActive': _recordActive,
          'outputPaused': _recordPaused,
          'outputTimecode': '00:00:00.000',
          'outputDuration': 0,
          'outputBytes': 0,
        });
      case 'StartRecord':
        if (_recordActive) {
          _failure(socket, requestType, requestId, 500);
          return;
        }
        _recordActive = true;
        _recordPaused = false;
        _success(socket, requestType, requestId);
        _recordEvent(socket, 'OBS_WEBSOCKET_OUTPUT_STARTED');
      case 'StopRecord':
        if (!_recordActive) {
          _failure(socket, requestType, requestId, 501);
          return;
        }
        _recordActive = false;
        _recordPaused = false;
        _success(socket, requestType, requestId, {
          'outputPath': r'C:\OBS\recording.mkv',
        });
        _recordEvent(
          socket,
          'OBS_WEBSOCKET_OUTPUT_STOPPED',
          outputPath: r'C:\OBS\recording.mkv',
        );
      case 'PauseRecord':
        _recordPaused = true;
        _success(socket, requestType, requestId);
        _recordEvent(socket, 'OBS_WEBSOCKET_OUTPUT_PAUSED');
      case 'ResumeRecord':
        _recordPaused = false;
        _success(socket, requestType, requestId);
        _recordEvent(socket, 'OBS_WEBSOCKET_OUTPUT_RESUMED');
      case 'SplitRecordFile':
        _success(socket, requestType, requestId);
        _event(socket, 'RecordFileChanged', {
          'newOutputPath': r'C:\OBS\recording-2.mkv',
        });
      case 'CreateRecordChapter':
        lastChapterName = requestData?['chapterName'] as String?;
        _success(socket, requestType, requestId);
      case 'SetInputSettings':
        lastInputName = requestData?['inputName'] as String?;
        lastInputText =
            (requestData?['inputSettings'] as Map?)?['text'] as String?;
        lastInputOverlay = requestData?['overlay'] as bool?;
        _success(socket, requestType, requestId);
      case 'SetCurrentProgramScene':
        lastProgramScene = requestData?['sceneName'] as String?;
        _success(socket, requestType, requestId);
      case 'GetSceneItemId':
        _success(socket, requestType, requestId, {'sceneItemId': 42});
      case 'SetSceneItemEnabled':
        expect(requestData?['sceneName'], '地震画面');
        expect(requestData?['sceneItemId'], 42);
        lastSceneItemEnabled = requestData?['sceneItemEnabled'] as bool?;
        _success(socket, requestType, requestId);
      case 'GetReplayBufferStatus':
        _success(socket, requestType, requestId, {
          'outputActive': _replayActive,
        });
      case 'StartReplayBuffer':
        if (_replayActive) {
          _failure(socket, requestType, requestId, 500);
          return;
        }
        _replayActive = true;
        _success(socket, requestType, requestId);
        _replayEvent(socket, 'OBS_WEBSOCKET_OUTPUT_STARTED');
      case 'StopReplayBuffer':
        if (!_replayActive) {
          _failure(socket, requestType, requestId, 501);
          return;
        }
        _replayActive = false;
        _success(socket, requestType, requestId);
        _replayEvent(socket, 'OBS_WEBSOCKET_OUTPUT_STOPPED');
      case 'GetLastReplayBufferReplay':
        _success(socket, requestType, requestId, {
          'savedReplayPath': _lastReplayPath,
        });
      case 'SaveReplayBuffer':
        if (!_replayActive) {
          _failure(socket, requestType, requestId, 501);
          return;
        }
        _lastReplayPath = r'C:\OBS\Replay 1.mkv';
        _success(socket, requestType, requestId);
        _event(socket, 'ReplayBufferSaved', {
          'savedReplayPath': _lastReplayPath,
        });
      default:
        _failure(socket, requestType, requestId, 204);
    }
  }

  void _recordEvent(
    WebSocket socket,
    String outputState, {
    String outputPath = '',
  }) {
    _event(socket, 'RecordStateChanged', {
      'outputActive': _recordActive,
      'outputState': outputState,
      'outputPath': outputPath,
    });
  }

  void _replayEvent(WebSocket socket, String outputState) {
    _event(socket, 'ReplayBufferStateChanged', {
      'outputActive': _replayActive,
      'outputState': outputState,
    });
  }

  void _event(WebSocket socket, String eventType, Map<String, dynamic> data) {
    socket.add(
      jsonEncode({
        'op': 5,
        'd': {
          'eventType': eventType,
          'eventIntent': ObsWebSocketService.outputEventSubscription,
          'eventData': data,
        },
      }),
    );
  }

  void _success(
    WebSocket socket,
    String requestType,
    String requestId, [
    Map<String, dynamic>? responseData,
  ]) {
    socket.add(
      jsonEncode({
        'op': 7,
        'd': {
          'requestType': requestType,
          'requestId': requestId,
          'requestStatus': {'result': true, 'code': 100},
          'responseData': ?responseData,
        },
      }),
    );
  }

  void _failure(
    WebSocket socket,
    String requestType,
    String requestId,
    int code,
  ) {
    socket.add(
      jsonEncode({
        'op': 7,
        'd': {
          'requestType': requestType,
          'requestId': requestId,
          'requestStatus': {'result': false, 'code': code},
        },
      }),
    );
  }

  Future<void> close() async {
    await closeClientSockets();
    await _server.close(force: true);
  }

  Future<void> closeClientSockets() async {
    for (final socket in _sockets.toList(growable: false)) {
      await socket.close();
    }
  }
}
