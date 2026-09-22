import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../jian_auth_service.dart';

import '../../models/jian_sources.dart';
import '../../models/source_status.dart';
import '../../models/source_credential_info.dart';
import '../quake_event_adapter.dart';
import 'base_source.dart';

typedef JianSocketFactory =
    WebSocketChannel Function(Uri uri, {Map<String, dynamic>? headers});

/// One aggregate connection, owned by the existing foreground/background
/// source manager. Parsing ends at emitUnified: no UI, audio or map callbacks.
class JianService extends BaseSourceService {
  JianService({
    JianSocketFactory? socketFactory,
    DateTime Function()? now,
    JianCredentialStore? credentialStore,
    JianAuthService? authService,
  }) : _socketFactory = socketFactory ?? _nativeSocket,
       _credentialStore = credentialStore ?? JianCredentialStore(),
       _authService = authService ?? JianAuthService(),
       _now = now ?? DateTime.now;

  static WebSocketChannel _nativeSocket(
    Uri uri, {
    Map<String, dynamic>? headers,
  }) => IOWebSocketChannel.connect(
    uri,
    headers: headers,
    connectTimeout: const Duration(seconds: 20),
  );
  final JianCredentialStore _credentialStore;
  final JianAuthService _authService;
  JianAuthStatus authStatus = JianAuthStatus.anonymous;
  SourceStatus connectionStatus = SourceStatus.disconnected;
  @override
  String get authenticationStatus => authStatus.name;
  SourceCredentialInfo _credentialInfo = const SourceCredentialInfo();
  @override
  SourceCredentialInfo get credentialInfo => _credentialInfo;

  static const sourceName = 'Jian Project';
  static const enabledPreferenceKey = 'api_source_jian_enabled';
  static const retryAfterPreferenceKey = 'jian_retry_after_ms';
  static final endpoint = Uri.parse('wss://api.sismotide.top/all');
  static const historyTypes = ['cenc', 'cwa', 'jma', 'kma', 'usgs', 'emsc'];

  final JianSocketFactory _socketFactory;
  final DateTime Function() _now;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _heartbeatTimer;
  Timer? _historyTimer;
  DateTime? _lastFrameAt;
  DateTime? _connectedAt;
  DateTime? _nextAttemptAt;
  bool _enabled = false;
  bool _disposed = false;
  int _generation = 0;
  int _failures = 0;
  bool _requestedHistory = false;
  String? lastError;
  final Set<String> _ignoredTypes = {};
  Set<String> get ignoredTypes => Set.unmodifiable(_ignoredTypes);

  @override
  String get name => sourceName;

  void updateStatus(SourceStatus status) {
    connectionStatus = status;
    onStatusChanged?.call(status);
  }

  void reloadCredentials() {
    final reconnect = _enabled;
    disconnect();
    if (reconnect) connect();
  }

  @override
  void connect() {
    if (_disposed || _enabled) return;
    _enabled = true;
    unawaited(_open());
  }

  Future<void> _open() async {
    final generation = ++_generation;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (!_isCurrent(generation)) return;
      JianCredential credential;
      try {
        credential = await _credentialStore.readCredential();
      } catch (_) {
        throw const JianAuthException('storage');
      }
      if (!_isCurrent(generation)) return;
      _credentialInfo = SourceCredentialInfo(
        configured: credential.token.isNotEmpty,
        expiresAt: credential.expiresAt,
      );
      if (credential.token.isEmpty) {
        authStatus = JianAuthStatus.unconfigured;
        lastError = const JianAuthException('credential_required').message;
        updateStatus(SourceStatus.error);
        return;
      }
      final saved = prefs.getInt(retryAfterPreferenceKey);
      if (saved != null) {
        final savedTime = DateTime.fromMillisecondsSinceEpoch(saved);
        if (_nextAttemptAt == null || savedTime.isAfter(_nextAttemptAt!)) {
          _nextAttemptAt = savedTime;
        }
      }
      final wait = _nextAttemptAt?.difference(_now());
      if (wait != null && wait > Duration.zero) {
        updateStatus(SourceStatus.error);
        _retryTimer = Timer(wait, () => unawaited(_open()));
        return;
      }
      // Persist attempt spacing across settings reloads and isolate restarts.
      _nextAttemptAt = _now().add(const Duration(seconds: 45));
      await prefs.setInt(
        retryAfterPreferenceKey,
        _nextAttemptAt!.millisecondsSinceEpoch,
      );
      if (!_isCurrent(generation)) return;
      authStatus = JianAuthStatus.authenticating;
      updateStatus(SourceStatus.connecting);
      _requestedHistory = false;
      final refreshToken = credential.token;
      final access = await _authService.accessToken(refreshToken);
      if (!_isCurrent(generation)) return;
      final socket = _socketFactory(
        endpoint,
        headers: {'Authorization': 'Bearer $access'},
      );
      _socket = socket;
      _subscription = socket.stream.listen(
        (message) {
          if (!_isCurrent(generation)) return;
          _lastFrameAt = _now();
          _receive(message, generation);
        },
        onError: (Object error) => _failed(generation, 'Jian 连接失败'),
        onDone: () => _failed(generation, '连接关闭'),
      );
      await socket.ready.timeout(const Duration(seconds: 20));
      if (!_isCurrent(generation)) return;
      _connectedAt = _now();
      _lastFrameAt ??= _connectedAt;
      authStatus = JianAuthStatus.authenticated;
      lastError = null;
      updateStatus(SourceStatus.connected);
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_isCurrent(generation)) return;
        if (_now().difference(_lastFrameAt!) > const Duration(seconds: 90)) {
          _failed(generation, '超过 90 秒未收到数据');
          return;
        }
        try {
          socket.sink.add('ping');
        } catch (error) {
          _failed(generation, '心跳发送失败');
        }
      });
    } on JianAuthException catch (error) {
      _authFailed(generation, error);
    } catch (_) {
      _failed(generation, 'Jian 握手失败');
    }
  }

  bool _isCurrent(int generation) =>
      _enabled && !_disposed && generation == _generation;

  void _receive(dynamic message, int generation) {
    try {
      final decoded = jsonDecode(
        message is String ? message : utf8.decode(message as List<int>),
      );
      if (decoded is! Map) return;
      final frame = Map<String, dynamic>.from(decoded);
      final type = frame['type']?.toString() ?? '';
      if (frame['ok'] == false ||
          frame['error'] != null && frame['code'] is num) {
        _authFailed(generation, JianAuthException.fromResponse(frame));
        return;
      }
      if (type == 'error') {
        final error = frame['message']?.toString() ?? '服务器拒绝连接';
        _failed(
          generation,
          error.contains('封禁') ? 'Jian IP 已被封禁' : 'Jian 服务器拒绝连接',
          cooldown: Duration(minutes: error.contains('封禁') ? 24 * 60 : 5),
        );
        return;
      }
      if (type == 'heartbeat' || type == 'pong') return;
      if (type == 'all') {
        for (final entry in frame.entries) {
          // The documented/live protocol uses U+FF1A, not ASCII ':'.
          final match = RegExp(r'^source[:：](.+)$').firstMatch(entry.key);
          if (match == null || entry.value is! Map) continue;
          _emitPayload(
            match.group(1)!,
            (entry.value as Map)['Data'],
            snapshot: true,
          );
        }
        _requestHistory(generation);
      } else if (type.endsWith('list_response')) {
        final source = type.substring(0, type.length - 'list_response'.length);
        if (frame['Data'] is List) {
          for (final item in frame['Data'] as List) {
            _emitPayload(source, item, history: true);
          }
        }
      } else {
        _emitPayload(type, frame['Data']);
      }
    } catch (error) {
      lastError = 'Jian 报文解析失败';
      debugPrint('Jian Project: $lastError');
    }
  }

  void _emitPayload(
    String type,
    dynamic payload, {
    bool snapshot = false,
    bool history = false,
  }) {
    if (!jianEarthquakeSources.containsKey(type)) {
      _ignoredTypes.add(type);
      return;
    }
    if (payload is! Map) return;
    try {
      final event = QuakeEventAdapter.convertJian(
        type,
        Map<String, dynamic>.from(payload),
        isHistory: history || (snapshot && !jianEewTypes.contains(type)),
        isSnapshot: snapshot,
      );
      if (event != null) emitUnified(event);
    } catch (error) {
      lastError = '$type 报文解析失败: $error';
      debugPrint('Jian Project: $lastError');
    }
  }

  void _requestHistory(int generation) {
    if (_requestedHistory) return;
    _requestedHistory = true;
    var index = 0;
    _historyTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isCurrent(generation) || index >= historyTypes.length) {
        timer.cancel();
        return;
      }
      try {
        _socket?.sink.add('${historyTypes[index++]}list');
      } catch (error) {
        _failed(generation, '历史请求失败');
      }
    });
  }

  void _authFailed(int generation, JianAuthException error) {
    if (!_isCurrent(generation)) return;
    _credentialInfo = SourceCredentialInfo(
      configured: _credentialInfo.configured,
      expiresAt: _credentialInfo.expiresAt,
      errorCode: error.code,
    );
    authStatus = error.retryable
        ? JianAuthStatus.unavailable
        : JianAuthStatus.invalid;
    _failed(
      generation,
      error.message,
      cooldown: const Duration(minutes: 5),
      retry: error.retryable,
      preserveAuthStatus: true,
    );
  }

  void _failed(
    int generation,
    String error, {
    Duration? cooldown,
    bool retry = true,
    bool preserveAuthStatus = false,
  }) {
    if (!_isCurrent(generation)) return;
    ++_generation;
    lastError = error;
    if (!preserveAuthStatus && authStatus != JianAuthStatus.anonymous) {
      authStatus = JianAuthStatus.unavailable;
      _credentialInfo = SourceCredentialInfo(
        configured: _credentialInfo.configured,
        expiresAt: _credentialInfo.expiresAt,
        errorCode: 'connection',
      );
    }
    debugPrint('Jian Project: $error');
    if (_connectedAt != null &&
        _now().difference(_connectedAt!) > const Duration(minutes: 2)) {
      _failures = 0;
    }
    final delay =
        cooldown ??
        Duration(seconds: math.min(300, 45 * (1 << math.min(_failures++, 3))));
    _nextAttemptAt = _now().add(delay);
    unawaited(_saveRetryAfter(_nextAttemptAt!));
    _closeConnection();
    updateStatus(SourceStatus.error);
    if (retry) _retryTimer = Timer(delay, () => unawaited(_open()));
  }

  Future<void> _saveRetryAfter(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(retryAfterPreferenceKey, time.millisecondsSinceEpoch);
    } catch (error) {
      debugPrint('Jian Project: 无法保存重连间隔: $error');
    }
  }

  void _closeConnection() {
    _retryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _historyTimer?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      unawaited(
        socket.sink
            .close()
            .timeout(const Duration(seconds: 5))
            .catchError((Object _) {}),
      );
    }
    _connectedAt = null;
    _lastFrameAt = null;
  }

  @override
  void disconnect() {
    _enabled = false;
    ++_generation;
    _closeConnection();
    authStatus = JianAuthStatus.anonymous;
    updateStatus(SourceStatus.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    _disposed = true;
    _authService.close();
    super.dispose();
  }
}
