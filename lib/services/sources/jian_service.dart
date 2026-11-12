import '../debug/network_trace.dart';
import 'dart:async';
import 'api_json_decoder.dart';
import '../native_jian_connection.dart';
import 'source_socket_error.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'source_socket.dart';
import 'source_connection_lifecycle.dart';
import '../jian_auth_service.dart';
import '../jian_auth_retry_policy.dart';

import '../../models/jian_sources.dart';
import '../../models/tsunami_message.dart';
import '../../models/source_status.dart';
import '../../models/source_credential_info.dart';
import '../quake_event_adapter.dart';
import 'base_source.dart';

typedef JianSocketFactory =
    WebSocketChannel Function(Uri uri, {Map<String, dynamic>? headers});

/// One aggregate connection, owned by the existing foreground/background
/// source manager. Emits unified earthquakes and JMA tsunami bulletins;
/// no UI, audio or map callbacks.
class JianService extends BaseSourceService {
  JianService({
    JianSocketFactory? socketFactory,
    DateTime Function()? now,
    JianCredentialStore? credentialStore,
    JianAuthService? authService,
    JianAuthRetryPolicy? retryPolicy,
  }) : _socketFactory = socketFactory ?? (kIsWeb ? _webSocket : _nativeSocket),
       _credentialStore = credentialStore ?? JianCredentialStore(),
       _authService = authService ?? JianAuthService(),
       _retryPolicy = retryPolicy ?? JianAuthRetryPolicy(),
       _now = now ?? DateTime.now;

  static WebSocketChannel _nativeSocket(
    Uri uri, {
    Map<String, dynamic>? headers,
  }) => connectSourceSocket(
    uri,
    headers: headers,
    connectTimeout: const Duration(seconds: 20),
  );
  static WebSocketChannel _webSocket(
    Uri uri, {
    Map<String, dynamic>? headers,
  }) => WebSocketChannel.connect(uri);
  final JianCredentialStore _credentialStore;
  final JianAuthService _authService;
  final JianAuthRetryPolicy _retryPolicy;
  String? _refreshToken;
  int _retryRevision = 0;
  bool _confirmedAuth = false, _resumeAuthorization = false;
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
  int _endpointIndex = 0;
  Uri get activeEndpoint => Uri.parse(
    (NativeJianConnection.prepare({
              'op': 'endpoint',
              'index': _endpointIndex,
              'path': '/all',
            })
            as Map)['url']
        as String,
  );
  static const historyTypes = ['cenc', 'cwa', 'jma', 'kma', 'usgs', 'emsc'];

  final JianSocketFactory _socketFactory;
  final DateTime Function() _now;
  WebSocketChannel? _socket;
  final _closing = SourceConnectionBarrier();
  final _activityWatchdog = SourceActivityWatchdog(const Duration(seconds: 30));
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
    NetworkDiagnostic.event("jian_policy", _generation, "status", {
      "status": status.name,
      "authentication": authStatus.name,
      "error": lastError,
    });
    connectionStatus = status;
    onStatusChanged?.call(status);
  }

  void reloadCredentials() {
    final reconnect = _enabled;
    _resumeAuthorization = true;
    disconnect();
    if (reconnect) connect();
  }

  @override
  void connect() {
    if (_disposed || _enabled) return;
    _enabled = true;
    _endpointIndex = 0;
    unawaited(_open());
  }

  Future<void> _open() async {
    final generation = ++_generation;
    NetworkDiagnostic.event("jian_policy", generation, "open_requested", {});
    try {
      await _closing.wait();
      if (!_isCurrent(generation)) return;
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
      if (credential.expiresAt != null &&
          !credential.expiresAt!.isAfter(_now().toUtc())) {
        throw const JianAuthException('expired_refresh_token');
      }
      _refreshToken = credential.token;
      JianAuthRetryState retryState;
      try {
        if (_resumeAuthorization) {
          _resumeAuthorization = false;
          await _retryPolicy.resume(credential.token);
        }
        retryState = await _retryPolicy.read(credential.token);
      } catch (_) {
        throw const JianAuthException('retry_storage');
      }
      if (!_isCurrent(generation)) return;
      if (retryState.blocked)
        throw const JianAuthException('auth_retry_exhausted');
      _retryRevision = retryState.revision;
      _confirmedAuth = false;
      final policyDeadline = retryState.nextAttemptAt;
      if (policyDeadline != null &&
          (_nextAttemptAt == null || policyDeadline.isAfter(_nextAttemptAt!))) {
        _nextAttemptAt = policyDeadline;
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
        NetworkDiagnostic.event("jian_policy", generation, "waiting_cooldown", {
          "nextAttemptUtc": _nextAttemptAt?.toUtc().toIso8601String(),
          "waitMs": wait.inMilliseconds,
        });
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
      NetworkDiagnostic.event(
        "jian_policy",
        generation,
        "access_exchange_requested",
        {},
      );
      final destination = activeEndpoint;
      _authService.selectApiEndpoint(destination);
      final access = await _authService.accessTokenCredential(refreshToken);
      NetworkDiagnostic.event(
        "jian_policy",
        generation,
        "access_exchange_succeeded",
        {"expiresUtc": access.expiresAt?.toUtc().toIso8601String()},
      );
      if (!_isCurrent(generation)) return;
      final refreshExpiry = access.refreshExpiresAt;
      if (refreshExpiry != null) {
        _credentialInfo = SourceCredentialInfo(
          configured: true,
          expiresAt: refreshExpiry,
        );
        try {
          await _credentialStore.updateExpiry(refreshToken, refreshExpiry);
        } catch (_) {
          // Server metadata remains usable for this session if saving fails.
          debugPrint('Jian Project: 无法保存长期凭证到期时间');
        }
        if (!_isCurrent(generation)) return;
      }
      if (access.expiresAt == null ||
          !access.expiresAt!.isAfter(
            _now().toUtc().add(const Duration(seconds: 30)),
          )) {
        throw const JianAuthException('expired_access_token');
      }
      if (refreshExpiry != null && !refreshExpiry.isAfter(_now().toUtc())) {
        throw const JianAuthException('expired_refresh_token');
      }
      final socket = _socketFactory(
        destination,
        headers: {'Authorization': 'Bearer ${access.token}'},
      );
      _socket = socket;
      _subscription = socket.stream.listen(
        (message) {
          if (!_isCurrent(generation)) return;
          _lastFrameAt = _now();
          _receive(message, generation);
        },
        onError: (Object error) => _transportFailed(generation, error),
        onDone: () => _transportFailed(generation),
      );
      await sourceReady(socket.ready, const Duration(seconds: 20));
      if (!_isCurrent(generation)) return;
      // Browser clients connect from their own IP and authenticate within the
      // 15-second window allowed by Jian; shared server-IP relays hit IP limits.
      if (!access.expiresAt!.isAfter(
        _now().toUtc().add(const Duration(seconds: 5)),
      )) {
        throw const JianAuthException('expired_access_token');
      }
      if (kIsWeb) socket.sink.add(access.token);
      _connectedAt = _now();
      _lastFrameAt ??= _connectedAt;
      authStatus = JianAuthStatus.authenticated;
      lastError = null;
      updateStatus(SourceStatus.connected);
      _activityWatchdog.reset(_now());
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_isCurrent(generation)) return;
        if (_activityWatchdog.mayDeclareStale(_now()) &&
            _now().difference(_lastFrameAt!) > const Duration(seconds: 90)) {
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
      await _authFailed(generation, error);
    } catch (error) {
      _transportFailed(generation, error);
    }
  }

  bool _isCurrent(int generation) =>
      _enabled && !_disposed && generation == _generation;

  void _transportFailed(int generation, [Object? error]) {
    if (!_isCurrent(generation)) return;
    final auth = JianAuthService.transportAuthFailure(
      error == null ? _socket?.closeCode : sourceSocketStatusCode(error),
    );
    if (auth != null) {
      unawaited(_authFailed(generation, auth));
    } else {
      _failed(generation, 'Jian 连接失败');
    }
  }

  void _receive(dynamic message, int generation) {
    try {
      final decoded = message is String
          ? decodeApiJson(message)
          : decodeApiJsonBytes(message as List<int>);
      if (decoded is! Map) return;
      final frame = Map<String, dynamic>.from(decoded);
      final type = frame['type']?.toString() ?? '';
      if (frame['ok'] == false ||
          frame['error'] != null && frame['code'] is num) {
        unawaited(
          _authFailed(generation, JianAuthException.fromResponse(frame)),
        );
        return;
      }
      if (type == 'error') {
        final error = frame['message']?.toString() ?? '服务器拒绝连接';
        _failed(
          generation,
          error.contains('封禁') ? 'Jian IP 已被封禁' : 'Jian 服务器拒绝连接',
          cooldown: Duration(minutes: error.contains('封禁') ? 24 * 60 : 5),
          retry: !error.contains('封禁'),
          switchEndpoint: false,
        );
        return;
      }
      if (!_confirmedAuth &&
          (type == 'all' ||
              ((jianEarthquakeSources.containsKey(type) ||
                      type == 'jma-tsunami') &&
                  frame['Data'] is Map))) {
        _confirmedAuth = true;
        final token = _refreshToken;
        if (token != null)
          unawaited(
            _retryPolicy.accepted(token, _retryRevision).catchError((Object _) {
              debugPrint('Jian Project: 无法更新鉴权恢复记录');
            }),
          );
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
    if (type == 'jma-tsunami') {
      if (payload is! Map || history) return;
      final generation = _generation;
      unawaited(
        TsunamiMessage.parseJmaSourceAsync(
              'jian',
              Map<String, dynamic>.from(payload),
            )
            .then((message) {
              if (!_disposed && generation == _generation)
                emitTsunami(message.copyWith(isInitialSnapshot: snapshot));
            })
            .catchError((Object error) {
              lastError = '$type 报文解析失败: $error';
              debugPrint('Jian Project: $lastError');
            }),
      );
      return;
    }
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

  Future<void> _authFailed(int generation, JianAuthException error) async {
    if (!_isCurrent(generation)) return;
    _credentialInfo = SourceCredentialInfo(
      configured: _credentialInfo.configured,
      expiresAt: _credentialInfo.expiresAt,
      errorCode: error.code,
    );
    authStatus = error.retryable
        ? JianAuthStatus.unavailable
        : JianAuthStatus.invalid;
    final token = _refreshToken;
    final bounded =
        token != null && JianAuthRetryPolicy.isTokenRejection(error.code);
    final stoppedGeneration = generation + 1;
    _failed(
      generation,
      error.message,
      cooldown: const Duration(minutes: 5),
      retry: !bounded && error.retryable,
      preserveAuthStatus: true,
      switchEndpoint: const {'network', 'server'}.contains(error.code),
    );
    if (!bounded) return;
    JianAuthRetryState state;
    try {
      state = await _retryPolicy.rejected(token, error.code, _now());
    } catch (_) {
      if (_isCurrent(stoppedGeneration)) {
        authStatus = JianAuthStatus.invalid;
        lastError = const JianAuthException('retry_storage').message;
        _credentialInfo = SourceCredentialInfo(
          configured: true,
          expiresAt: _credentialInfo.expiresAt,
          errorCode: 'retry_storage',
        );
        updateStatus(SourceStatus.error);
      }
      return;
    }
    if (!_isCurrent(stoppedGeneration)) return;
    final code = state.code ?? error.code;
    authStatus = state.blocked
        ? JianAuthStatus.invalid
        : JianAuthStatus.unavailable;
    lastError = JianAuthException(code).message;
    _credentialInfo = SourceCredentialInfo(
      configured: true,
      expiresAt: _credentialInfo.expiresAt,
      errorCode: code,
    );
    updateStatus(SourceStatus.error);
    if (!state.blocked) {
      final delay = state.nextAttemptAt!.difference(_now());
      _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
        if (_isCurrent(stoppedGeneration)) unawaited(_open());
      });
    }
  }

  void _failed(
    int generation,
    String error, {
    Duration? cooldown,
    bool retry = true,
    bool preserveAuthStatus = false,
    bool switchEndpoint = true,
  }) {
    if (!_isCurrent(generation)) return;
    ++_generation;
    lastError = error;
    if (!preserveAuthStatus && authStatus != JianAuthStatus.anonymous) {
      authStatus = JianAuthStatus.unavailable;
      _credentialInfo = SourceCredentialInfo(
        configured: _credentialInfo.configured,
        expiresAt: _credentialInfo.expiresAt,
        errorCode: kIsWeb && _connectedAt == null
            ? 'browser_connection'
            : 'connection',
      );
    }
    debugPrint('Jian Project: $error');
    final plan =
        NativeJianConnection.prepare({
              'op': 'retry',
              'index': _endpointIndex,
              'failures': _failures,
              'stableMillis': _connectedAt == null
                  ? null
                  : _now().difference(_connectedAt!).inMilliseconds,
              'cooldownMs': cooldown?.inMilliseconds,
              'switchEndpoint': retry && switchEndpoint,
            })
            as Map;
    _endpointIndex = plan['index'] as int;
    _failures = plan['failures'] as int;
    final delay = Duration(milliseconds: plan['delayMs'] as int);
    _nextAttemptAt = _now().add(delay);
    unawaited(_saveRetryAfter(_nextAttemptAt!));
    _closeConnection();
    updateStatus(SourceStatus.error);
    NetworkDiagnostic.event("jian_policy", generation, "retry_decision", {
      "error": error,
      "retry": retry,
      "delayMs": delay.inMilliseconds,
      "nextAttemptUtc": _nextAttemptAt?.toUtc().toIso8601String(),
    });
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
    final subscription = _subscription;
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null)
      _closing.close(() async {
        final closed = socket.sink.close();
        cancelSourceSubscription(subscription);
        await closed;
      });
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
