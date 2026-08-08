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

  final String url;
  final void Function(dynamic message) onMessage;
  final void Function(WhewsSocketState state)? onStateChanged;

  String _apiToken;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _serial = 0;
  int _retrySeconds = 3;
  bool _running = false;
  bool _authorizationRejected = false;
  DateTime? _lastFrameAt;
  bool _serverFrameReceived = false;

  bool get isRunning => _running;
  bool get authorizationRejected => _authorizationRejected;

  void setApiToken(String apiToken) {
    final next = apiToken.trim();
    if (next == _apiToken) return;
    _apiToken = next;
    _authorizationRejected = false;
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
    _retrySeconds = 3;
    _connect();
  }

  Future<void> _connect() async {
    if (!_running || _authorizationRejected || _apiToken.isEmpty) return;
    final serial = ++_serial;
    _reconnectTimer?.cancel();
    onStateChanged?.call(WhewsSocketState.connecting);

    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 12));
      if (!_isCurrent(channel, serial)) {
        await channel.sink.close();
        return;
      }
      channel.sink.add(jsonEncode({'token': _apiToken}));
      _lastFrameAt = DateTime.now();
      _retrySeconds = 3;
      _serverFrameReceived = false;
      _startHeartbeat(channel, serial);
      _subscription = channel.stream.listen(
        (data) => _handleFrame(channel!, serial, data),
        onError: (Object error, StackTrace stackTrace) {
          if (!_isCurrent(channel!, serial)) return;
          debugPrint('WHEWS $url WebSocket error: $error');
          _handleClosed(channel, serial);
        },
        onDone: () => _handleClosed(channel!, serial),
        cancelOnError: true,
      );
    } catch (error) {
      if (channel != null && !_isCurrent(channel, serial)) return;
      debugPrint('WHEWS $url connection failed: $error');
      _handleClosed(channel, serial);
    }
  }

  void _handleFrame(WebSocketChannel channel, int serial, dynamic raw) {
    if (!_isCurrent(channel, serial)) return;
    _lastFrameAt = DateTime.now();
    dynamic decoded;
    try {
      decoded = raw is String ? jsonDecode(raw) : raw;
    } catch (_) {
      return;
    }
    if (!_serverFrameReceived) {
      _serverFrameReceived = true;
      onStateChanged?.call(WhewsSocketState.connected);
    }
    if (decoded is Map && decoded['type'] == 'heartbeat') {
      channel.sink.add(jsonEncode({'type': 'ping'}));
      return;
    }
    if (decoded is Map && decoded['type'] == 'pong') return;
    onMessage(decoded);
  }

  void _startHeartbeat(WebSocketChannel channel, int serial) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!_isCurrent(channel, serial)) return;
      final lastFrameAt = _lastFrameAt;
      if (lastFrameAt != null &&
          DateTime.now().difference(lastFrameAt) >
              const Duration(seconds: 75)) {
        _handleClosed(channel, serial);
        return;
      }
      channel.sink.add(jsonEncode({'type': 'ping'}));
    });
  }

  void _handleClosed(WebSocketChannel? channel, int serial) {
    if (channel != null && !_isCurrent(channel, serial)) return;
    final closeCode = channel?.closeCode;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _serverFrameReceived = false;
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

  void stop() {
    _running = false;
    _serial++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _lastFrameAt = null;
    _serverFrameReceived = false;
    onStateChanged?.call(WhewsSocketState.disconnected);
  }

  void dispose() => stop();
}
