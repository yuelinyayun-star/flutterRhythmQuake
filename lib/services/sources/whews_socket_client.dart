import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_json_decoder.dart';
import 'source_socket.dart';
import 'source_socket_error.dart';
import 'source_connection_lifecycle.dart';
import 'source_connection_diagnostics.dart';
import '../whews_authorization_policy.dart';
import '../native_whews_connection.dart';

enum WhewsSocketState {
  disconnected,
  connecting,
  connected,
  unauthorized,
  error,
}

class WhewsSocketClient {
  WhewsSocketClient({
    required this.url,
    required String apiToken,
    required this.onMessage,
    this.onStateChanged,
    this.frameDecoder = decodeApiJson,
    this.binaryFrameDecoder = decodeApiJsonBytes,
    DateTime Function()? now,
    WebSocketChannel Function(Uri)? socketFactory,
    WhewsAuthorizationPolicy? authorizationPolicy,
  }) : _apiToken = apiToken.trim(),
       _now = now ?? DateTime.now,
       _authorizationPolicy = authorizationPolicy ?? WhewsAuthorizationPolicy(),
       _socketFactory =
           socketFactory ??
           ((uri) => connectSourceSocket(
             uri,
             connectTimeout: const Duration(seconds: 12),
           ));

  static const heartbeatInterval = Duration(seconds: 30);
  static const stallTimeout = Duration(seconds: 90);
  static const livenessTimeout = Duration(seconds: 20);
  final String url;
  late final List<String> _urls = List<String>.from(
    NativeWhewsConnection.prepare({'op': 'endpoints', 'url': url}) as List,
  );
  int _endpointIndex = 0;
  String get activeUrl => _urls[_endpointIndex];
  final void Function(dynamic) onMessage;
  final void Function(WhewsSocketState)? onStateChanged;
  final DateTime Function() _now;
  final WebSocketChannel Function(Uri) _socketFactory;
  final WhewsAuthorizationPolicy _authorizationPolicy;
  dynamic Function(String) frameDecoder;
  dynamic Function(List<int>) binaryFrameDecoder;
  static final Map<String, SourceConnectionBarrier> _closeBarriers = {};
  SourceConnectionBarrier get _closing =>
      _closeBarriers.putIfAbsent(url, SourceConnectionBarrier.new);
  final _watchdog = SourceActivityWatchdog(heartbeatInterval);
  String _apiToken;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer, _heartbeatTimer, _livenessTimer, _stableTimer;
  int _serial = 0, _retrySeconds = 3;
  bool _running = false,
      _authorizationRejected = false,
      _aliveConfirmed = false;
  DateTime? _lastFrameAt;
  bool get isRunning => _running;
  bool get authorizationRejected => _authorizationRejected;
  bool get aliveConfirmed => _aliveConfirmed;
  Future<void> get closed => _closing.wait();

  void _diagnostic(String event, [Map<String, Object?> fields = const {}]) {
    final uri = Uri.tryParse(activeUrl);
    recordSourceConnection({
      'source': 'WHEWS',
      'endpoint': uri == null
          ? 'invalid'
          : '${uri.scheme}://${uri.host}${uri.path}',
      'event': event,
      'serial': _serial,
      ...fields,
    }, secret: _apiToken);
  }

  void reconnect() {
    if (!_running || _authorizationRejected || _channel == null) return;
    _handleClosed(_channel!, _serial, trigger: 'requested_reconnect');
  }

  void setApiToken(String token) {
    final next = token.trim();
    if (next == _apiToken) return;
    final restart = _running;
    stop();
    _apiToken = next;
    _authorizationRejected = false;
    if (restart) start();
  }

  void start() {
    if (_running) return;
    if (_apiToken.isEmpty) {
      _diagnostic('start_blocked', {'cause': 'empty_api_token'});
      onStateChanged?.call(WhewsSocketState.unauthorized);
      return;
    }
    _running = true;
    _authorizationRejected = false;
    _retrySeconds = 3;
    _endpointIndex = 0;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_running ||
        _authorizationRejected ||
        _apiToken.isEmpty ||
        _channel != null)
      return;
    final serial = ++_serial;
    _reconnectTimer?.cancel();
    var blockedCause = 'previous_close_unconfirmed';
    try {
      await _closing.wait();
      if (!_running || serial != _serial) return;
      blockedCause = 'retry_state_unavailable';
      final blocked = await _authorizationPolicy.blockedCode(
        activeUrl,
        _apiToken,
      );
      if (!_running || serial != _serial) return;
      if (blocked != null) {
        _authorizationRejected = true;
        _diagnostic('start_blocked', {
          'cause': 'previous_rejection',
          'code': blocked,
        });
        onStateChanged?.call(
          blocked == 4401 || blocked == 401
              ? WhewsSocketState.unauthorized
              : WhewsSocketState.error,
        );
        return;
      }
    } catch (error) {
      if (_running && serial == _serial) {
        _diagnostic('start_blocked', {
          'cause': blockedCause,
          'error': error.toString(),
        });
        _authorizationRejected = true;
        onStateChanged?.call(WhewsSocketState.error);
      }
      return;
    }
    if (!_running ||
        _authorizationRejected ||
        serial != _serial ||
        _apiToken.isEmpty)
      return;
    _stopHeartbeatTimers();
    _aliveConfirmed = false;
    _lastFrameAt = null;
    onStateChanged?.call(WhewsSocketState.connecting);
    _diagnostic('connect');
    WebSocketChannel? channel;
    try {
      // URL authentication is supported by WHEWS. Never downgrade a rejected
      // credential to an unauthenticated upgrade awaiting a Dart first frame.
      channel = _socketFactory(buildConnectionUri(activeUrl, _apiToken));
      _channel = channel;
      _subscription = channel.stream.listen(
        (frame) => _handleFrame(channel!, serial, frame),
        onError: (Object error, StackTrace stack) {
          if (_isCurrent(channel!, serial))
            _handleClosed(
              channel,
              serial,
              code: sourceSocketStatusCode(error),
              trigger: 'transport_error',
              error: error,
            );
        },
        onDone: () => _handleClosed(channel!, serial),
        cancelOnError: true,
      );
      await sourceReady(channel.ready, const Duration(seconds: 12));
      if (!_isCurrent(channel, serial)) return;
      _startHeartbeat(channel, serial);
    } catch (error) {
      if (serial != _serial || !_running) return;
      if (channel == null) {
        _diagnostic('connect_error', {
          'error': error.toString(),
          'httpStatus': sourceSocketStatusCode(error),
        });
        _scheduleRetry(serial);
        return;
      }
      if (_isCurrent(channel, serial))
        _handleClosed(
          channel,
          serial,
          code: sourceSocketStatusCode(error),
          trigger: 'ready_error',
          error: error,
        );
    }
  }

  void _handleFrame(WebSocketChannel channel, int serial, dynamic raw) {
    if (!_isCurrent(channel, serial)) return;
    dynamic decoded;
    try {
      decoded = raw is String
          ? frameDecoder(raw)
          : raw is List<int>
          ? binaryFrameDecoder(raw)
          : raw;
    } catch (_) {
      return;
    }
    if (decoded is Map &&
        (decoded['ok'] == false ||
            const {
              'error',
              'auth_error',
              'auth_fail',
            }.contains(decoded['type']))) {
      final code = decoded['code'] is num
          ? (decoded['code'] as num).toInt()
          : null;
      _diagnostic('server_error', {
        'type': decoded['type']?.toString(),
        'code': decoded['code'],
        'message': decoded['message']?.toString(),
        'error': decoded['error']?.toString(),
        'detail': decoded['detail']?.toString(),
      });
      // Unknown server rejection is also terminal, never a proof of liveness.
      _handleClosed(
        channel,
        serial,
        trigger: 'server_error_frame',
        code: code == 4503
            ? 4503
            : const {401, 403, 429, 4401, 4403, 4008}.contains(code)
            ? code
            : 4403,
      );
      return;
    }
    if (decoded is! Map && decoded is! List) return;
    _lastFrameAt = _now();
    if (!_aliveConfirmed) {
      _aliveConfirmed = true;
      _diagnostic('alive_confirmed');
      _livenessTimer?.cancel();
      onStateChanged?.call(WhewsSocketState.connected);
      _stableTimer = Timer(const Duration(minutes: 1), () {
        if (_isCurrent(channel, serial) && _aliveConfirmed) _retrySeconds = 3;
      });
    }
    if (decoded is Map && decoded['type'] == 'heartbeat') {
      try {
        channel.sink.add(jsonEncode({'type': 'ping'}));
      } catch (error) {
        _handleClosed(
          channel,
          serial,
          trigger: 'ping_send_error',
          error: error,
        );
      }
      return;
    }
    if (decoded is Map && decoded['type'] == 'pong') return;
    onMessage(decoded);
  }

  void _startHeartbeat(WebSocketChannel channel, int serial) {
    _watchdog.reset(_now());
    void probe() {
      try {
        channel.sink.add(jsonEncode({'type': 'ping'}));
      } catch (error) {
        _handleClosed(
          channel,
          serial,
          trigger: 'ping_send_error',
          error: error,
        );
      }
    }

    probe();
    if (!_isCurrent(channel, serial)) return;
    void armLiveness() {
      final deadline = _now().add(livenessTimeout);
      _livenessTimer = Timer(livenessTimeout, () {
        if (!_isCurrent(channel, serial) || _aliveConfirmed) return;
        if (_now().difference(deadline) > const Duration(seconds: 5)) {
          armLiveness();
          return;
        }
        _handleClosed(channel, serial, trigger: 'liveness_timeout');
      });
    }

    if (!_aliveConfirmed) armLiveness();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (!_isCurrent(channel, serial)) return;
      final mayExpire = _watchdog.mayDeclareStale(_now());
      if (mayExpire &&
          _lastFrameAt != null &&
          _now().difference(_lastFrameAt!) > stallTimeout) {
        _handleClosed(channel, serial, trigger: 'heartbeat_stale');
        return;
      }
      probe();
    });
  }

  void _stopHeartbeatTimers() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _livenessTimer?.cancel();
    _livenessTimer = null;
    _stableTimer?.cancel();
    _stableTimer = null;
  }

  void _handleClosed(
    WebSocketChannel channel,
    int serial, {
    int? code,
    String trigger = 'peer_close',
    Object? error,
  }) {
    if (!_isCurrent(channel, serial)) return;
    final closeCode = code ?? channel.closeCode;
    _diagnostic('disconnected', {
      'trigger': trigger,
      'code': closeCode,
      'peerCloseCode': channel.closeCode,
      'peerCloseReason': channel.closeReason,
      if (error != null) 'error': error.toString(),
    });
    ++_serial;
    _stopHeartbeatTimers();
    final subscription = _subscription;
    _subscription = null;
    _channel = null;
    _aliveConfirmed = false;
    _lastFrameAt = null;
    _closing.close(() async {
      final closed = channel.sink.close();
      cancelSourceSubscription(subscription);
      await closed;
    });
    if (!_running) return;
    if (WhewsAuthorizationPolicy.isTerminal(closeCode)) {
      _authorizationRejected = true;
      final rejectedUrl = activeUrl;
      final rejectedToken = _apiToken;
      _closing.close(
        () =>
            _authorizationPolicy.block(rejectedUrl, rejectedToken, closeCode!),
      );
      _diagnostic('retry_stopped', {'code': closeCode});
      _reconnectTimer?.cancel();
      onStateChanged?.call(
        closeCode == 4401 || closeCode == 401
            ? WhewsSocketState.unauthorized
            : WhewsSocketState.error,
      );
      return;
    }
    _scheduleRetry(_serial, temporaryAuthFailure: closeCode == 4503);
  }

  void _scheduleRetry(int serial, {bool temporaryAuthFailure = false}) {
    if (!_running || _authorizationRejected) return;
    onStateChanged?.call(WhewsSocketState.error);
    final plan =
        NativeWhewsConnection.prepare({
              'op': 'retry',
              'index': _endpointIndex,
              'count': _urls.length,
              'seconds': _retrySeconds,
              'code': temporaryAuthFailure ? 4503 : 0,
            })
            as Map;
    final delay = plan['delay'] as int;
    final previousUrl = activeUrl;
    _endpointIndex = plan['index'] as int;
    _retrySeconds = plan['next'] as int;
    if (previousUrl != activeUrl) {
      _diagnostic('endpoint_switched', {
        'previousEndpoint': WhewsAuthorizationPolicy.endpoint(previousUrl),
      });
    }
    _diagnostic('retry_scheduled', {'afterSeconds': delay});
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (_running && serial == _serial && !_authorizationRejected)
        unawaited(_connect());
    });
  }

  bool _isCurrent(WebSocketChannel channel, int serial) =>
      _running && serial == _serial && identical(channel, _channel);
  @visibleForTesting
  static Uri buildConnectionUri(String url, String token) =>
      Uri.parse(url).replace(
        queryParameters: {
          ...Uri.parse(url).queryParameters,
          'token': token.trim(),
        },
      );

  void stop() {
    if (_running || _channel != null) _diagnostic('stop_requested');
    _running = false;
    ++_serial;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeatTimers();
    final channel = _channel;
    final subscription = _subscription;
    _channel = null;
    _subscription = null;
    if (channel != null)
      _closing.close(() async {
        final closed = channel.sink.close();
        cancelSourceSubscription(subscription);
        await closed;
      });
    _lastFrameAt = null;
    _aliveConfirmed = false;
    onStateChanged?.call(WhewsSocketState.disconnected);
  }

  void dispose() => stop();
}
