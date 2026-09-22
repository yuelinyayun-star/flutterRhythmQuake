import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
  }) : _apiToken = apiToken.trim();

  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration stallTimeout = Duration(seconds: 90);
  static const Duration livenessTimeout = Duration(seconds: 20);

  final String url;
  final void Function(dynamic message) onMessage;
  final void Function(WhewsSocketState state)? onStateChanged;

  String _apiToken;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _livenessTimer;
  int _serial = 0;
  int _retrySeconds = 3;
  bool _running = false;
  bool _authorizationRejected = false;
  bool _queryAuthFailed = false;
  DateTime? _lastFrameAt;
  bool _aliveConfirmed = false;

  bool get isRunning => _running;
  bool get authorizationRejected => _authorizationRejected;
  bool get aliveConfirmed => _aliveConfirmed;

  /// Reuse the transport's bounded retry and authorization handling.
  void reconnect() {
    if (!_running || _authorizationRejected) return;
    _handleClosed(_channel, _serial);
  }

  void setApiToken(String apiToken) {
    final next = apiToken.trim();
    if (next == _apiToken) return;
    _apiToken = next;
    _authorizationRejected = false;
    _queryAuthFailed = false;
    if (_running) {
      stop();
      start();
    }
  }

  void start() {
    if (_running || _apiToken.isEmpty) {
      if (_apiToken.isEmpty) {
        onStateChanged?.call(WhewsSocketState.unauthorized);
      }
      return;
    }
    _running = true;
    _authorizationRejected = false;
    _queryAuthFailed = false;
    _retrySeconds = 3;
    _connect();
  }

  Future<void> _connect() async {
    if (!_running || _authorizationRejected || _apiToken.isEmpty) return;
    final serial = ++_serial;
    _reconnectTimer?.cancel();
    _stopHeartbeatTimers();
    _aliveConfirmed = false;
    _lastFrameAt = null;
    onStateChanged?.call(WhewsSocketState.connecting);

    final useQueryTokenAuth = !_queryAuthFailed;
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(
        useQueryTokenAuth ? buildConnectionUri(url, _apiToken) : Uri.parse(url),
      );
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 12));
      if (!_isCurrent(channel, serial)) {
        await channel.sink.close();
        return;
      }
      if (!useQueryTokenAuth) {
        channel.sink.add(jsonEncode({'token': _apiToken}));
      }
      _retrySeconds = 3;
      _subscription = channel.stream.listen(
        (data) => _handleFrame(channel!, serial, data),
        onError: (Object error, StackTrace stackTrace) {
          if (!_isCurrent(channel!, serial)) return;
          debugPrint('WHEWS $url WebSocket error: ${error.runtimeType}');
          _handleClosed(channel, serial);
        },
        onDone: () => _handleClosed(channel!, serial),
        cancelOnError: true,
      );
      // Stay yellow until heartbeat/pong/any valid frame proves the session is
      // alive. Probe immediately so we do not wait a full heartbeat interval.
      _startHeartbeat(channel, serial);
    } catch (error) {
      if (channel != null && !_isCurrent(channel, serial)) return;
      debugPrint('WHEWS $url connection failed: ${error.runtimeType}');
      _handleClosed(channel, serial);
    }
  }

  void _handleFrame(WebSocketChannel channel, int serial, dynamic raw) {
    if (!_isCurrent(channel, serial)) return;
    dynamic decoded;
    try {
      decoded = raw is String ? jsonDecode(raw) : raw;
    } catch (_) {
      return;
    }
    _lastFrameAt = DateTime.now();
    _confirmAlive();
    if (decoded is Map && decoded['type'] == 'heartbeat') {
      channel.sink.add(jsonEncode({'type': 'ping'}));
      return;
    }
    if (decoded is Map && decoded['type'] == 'pong') return;
    onMessage(decoded);
  }

  void _confirmAlive() {
    if (_aliveConfirmed) return;
    _aliveConfirmed = true;
    _livenessTimer?.cancel();
    _livenessTimer = null;
    onStateChanged?.call(WhewsSocketState.connected);
  }

  void _startHeartbeat(WebSocketChannel channel, int serial) {
    _stopHeartbeatTimers();
    try {
      channel.sink.add(jsonEncode({'type': 'ping'}));
    } catch (_) {
      _handleClosed(channel, serial);
      return;
    }
    _livenessTimer = Timer(livenessTimeout, () {
      if (!_isCurrent(channel, serial) || _aliveConfirmed) return;
      debugPrint('WHEWS $url liveness timeout waiting for heartbeat/pong');
      _handleClosed(channel, serial);
    });
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (!_isCurrent(channel, serial)) return;
      final lastFrameAt = _lastFrameAt;
      if (lastFrameAt != null &&
          DateTime.now().difference(lastFrameAt) > stallTimeout) {
        _handleClosed(channel, serial);
        return;
      }
      try {
        channel.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {
        _handleClosed(channel, serial);
      }
    });
  }

  void _stopHeartbeatTimers() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _livenessTimer?.cancel();
    _livenessTimer = null;
  }

  void _handleClosed(WebSocketChannel? channel, int serial) {
    if (channel != null && !_isCurrent(channel, serial)) return;
    final closeCode = channel?.closeCode;
    _stopHeartbeatTimers();
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _aliveConfirmed = false;
    _lastFrameAt = null;
    try {
      channel?.sink.close();
    } catch (_) {
      // The channel may already be closed by the WebSocket implementation.
    }

    if (!_running) {
      onStateChanged?.call(WhewsSocketState.disconnected);
      return;
    }
    if (closeCode == 4401) {
      if (!_queryAuthFailed) {
        _queryAuthFailed = true;
        debugPrint(
          'WHEWS $url query-token auth rejected; retrying with frame token',
        );
        onStateChanged?.call(WhewsSocketState.connecting);
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(Duration.zero, _connect);
        return;
      }
      _authorizationRejected = true;
      onStateChanged?.call(WhewsSocketState.unauthorized);
      return;
    }
    onStateChanged?.call(WhewsSocketState.error);
    final delay = closeCode == 4503 ? 10 : _retrySeconds;
    _retrySeconds = (_retrySeconds + 2).clamp(3, 30);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), _connect);
  }

  bool _isCurrent(WebSocketChannel channel, int serial) {
    return _running && identical(_channel, channel) && _serial == serial;
  }

  @visibleForTesting
  static Uri buildConnectionUri(String url, String apiToken) {
    final base = Uri.parse(url);
    return base.replace(
      queryParameters: {...base.queryParameters, 'token': apiToken.trim()},
    );
  }

  void stop() {
    _running = false;
    _serial++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeatTimers();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _lastFrameAt = null;
    _aliveConfirmed = false;
    onStateChanged?.call(WhewsSocketState.disconnected);
  }

  void dispose() => stop();
}
