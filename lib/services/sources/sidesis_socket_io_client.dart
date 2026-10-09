import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Low-level Socket.IO/Engine.IO 4 client for the Sidesis feed.
///
/// This class intentionally does not guess a business subscription event.
/// It exposes raw Socket.IO event frames until the upstream event contract is
/// confirmed from a real pushed message or an official client.
class SidesisSocketIoClient {
  SidesisSocketIoClient({
    this.url = defaultUrl,
    this.onEvent,
    this.onMessage,
    this.onRawFrame,
    this.onStateChanged,
  });

  static const String defaultUrl = 'wss://sidesis.iigea.org/socket.io/';
  static const Duration connectTimeout = Duration(seconds: 12);
  static const Duration minReconnectDelay = Duration(seconds: 3);
  static const Duration maxReconnectDelay = Duration(seconds: 30);

  final String url;
  final void Function(String eventName, dynamic data)? onEvent;
  final void Function(SidesisSocketIoMessage message)? onMessage;
  final void Function(String frame)? onRawFrame;
  final void Function(SidesisSocketIoState state)? onStateChanged;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _generation = 0;
  int _reconnectSeconds = minReconnectDelay.inSeconds;
  bool _running = false;
  bool _namespaceConnected = false;

  bool get isRunning => _running;
  bool get isConnected => _namespaceConnected;

  /// Starts the transport and connects the Socket.IO root namespace.
  void start() {
    if (_running) return;
    _running = true;
    _reconnectSeconds = minReconnectDelay.inSeconds;
    _connect();
  }

  /// Stops the transport without scheduling another reconnect.
  void stop() {
    _running = false;
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeCurrent();
    _setState(SidesisSocketIoState.disconnected);
  }

  /// Sends a Socket.IO event only when the upstream contract is confirmed.
  ///
  /// No event is sent automatically by this client because the service's
  /// subscription event has not been identified yet.
  bool sendEvent(String eventName, [dynamic data]) {
    final channel = _channel;
    if (!_namespaceConnected || channel == null || eventName.trim().isEmpty) {
      return false;
    }
    final packet = <dynamic>[eventName, ?data];
    channel.sink.add('42${jsonEncode(packet)}');
    return true;
  }

  Future<void> _connect() async {
    if (!_running) return;
    final generation = ++_generation;
    _closeCurrent();
    _namespaceConnected = false;
    _setState(SidesisSocketIoState.connecting);

    final uri = _buildUri(url);
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready.timeout(connectTimeout);
      if (!_isCurrent(channel, generation)) {
        await channel.sink.close();
        return;
      }
      _subscription = channel.stream.listen(
        (raw) => _handleFrame(channel!, generation, raw),
        onError: (Object error, StackTrace stackTrace) {
          if (!_isCurrent(channel!, generation)) return;
          _handleFailure(error);
        },
        onDone: () {
          if (!_isCurrent(channel!, generation)) return;
          _handleFailure();
        },
        cancelOnError: true,
      );
    } catch (error) {
      if (channel != null && !_isCurrent(channel, generation)) return;
      _handleFailure(error);
    }
  }

  void _handleFrame(WebSocketChannel channel, int generation, dynamic raw) {
    if (!_isCurrent(channel, generation)) return;
    if (raw is! String) return;
    onRawFrame?.call(raw);
    if (raw.isEmpty) return;

    final engineType = raw.codeUnitAt(0) - 48;
    switch (engineType) {
      case 0:
        // Engine.IO open packet. Connect the root Socket.IO namespace.
        channel.sink.add('40');
        return;
      case 2:
        // Engine.IO ping.
        channel.sink.add('3');
        return;
      case 3:
        return;
      case 4:
        _handleSocketPacket(raw.substring(1));
        return;
      case 1:
        _handleFailure();
        return;
      default:
        return;
    }
  }

  void _handleSocketPacket(String packet) {
    if (packet.isEmpty) return;
    final socketType = packet.codeUnitAt(0) - 48;
    final payload = packet.substring(1);
    switch (socketType) {
      case 0:
        _namespaceConnected = true;
        _reconnectSeconds = minReconnectDelay.inSeconds;
        _setState(SidesisSocketIoState.connected);
        return;
      case 1:
        _handleFailure();
        return;
      case 2:
        _handleEvent(payload);
        return;
      case 4:
        _handleFailure(payload);
        return;
      default:
        return;
    }
  }

  void _handleEvent(String payload) {
    dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (decoded is! List || decoded.isEmpty || decoded.first is! String) {
      return;
    }
    final eventName = decoded.first as String;
    final data = decoded.length > 1 ? decoded[1] : null;
    onEvent?.call(eventName, data);
    final message = SidesisSocketIoMessage.tryParse(eventName, data);
    if (message != null) onMessage?.call(message);
  }

  void _handleFailure([Object? error]) {
    if (!_running) {
      _setState(SidesisSocketIoState.disconnected);
      return;
    }
    _namespaceConnected = false;
    _closeCurrent();
    _setState(SidesisSocketIoState.error);
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: _reconnectSeconds);
    _reconnectSeconds = (_reconnectSeconds * 2).clamp(
      minReconnectDelay.inSeconds,
      maxReconnectDelay.inSeconds,
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  Uri _buildUri(String rawUrl) {
    final base = Uri.parse(rawUrl);
    return base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        'EIO': '4',
        'transport': 'websocket',
      },
    );
  }

  bool _isCurrent(WebSocketChannel channel, int generation) {
    return _running &&
        identical(channel, _channel) &&
        generation == _generation;
  }

  void _closeCurrent() {
    _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    try {
      channel?.sink.close();
    } catch (_) {
      // The channel may already be closed.
    }
  }

  void _setState(SidesisSocketIoState state) {
    onStateChanged?.call(state);
  }

  void dispose() => stop();
}

enum SidesisSocketIoState { disconnected, connecting, connected, error }

enum SidesisSocketIoMessageKind { heartbeat, alert, other }

/// The three severity levels used by the Sidesis/ASMX page.
///
/// The upstream value is kept separately in [SidesisSocketIoMessage.severity].
/// This enum is only the semantic mapping used by the application.
enum SidesisSeverityLevel { minor, moderate, severe, unknown }

extension SidesisSeverityLevelLabels on SidesisSeverityLevel {
  String get displayName {
    switch (this) {
      case SidesisSeverityLevel.minor:
        return '轻度';
      case SidesisSeverityLevel.moderate:
        return '中度';
      case SidesisSeverityLevel.severe:
        return '强';
      case SidesisSeverityLevel.unknown:
        return '未知';
    }
  }
}

/// Raw-preserving classification based on the public Sidesis page handlers.
///
/// The website only treats `new_message` and `message` as business events.
/// It identifies a station heartbeat by `type: heartbeat` without severity,
/// and treats a message with a top-level severity as an alert. No fields are
/// invented. The ASMX three-level interpretation is exposed separately from
/// this transport-level classification.
class SidesisSocketIoMessage {
  SidesisSocketIoMessage._({
    required this.eventName,
    required this.data,
    required this.kind,
  });

  static const String newMessageEvent = 'new_message';
  static const String messageEvent = 'message';

  final String eventName;
  final Map<String, dynamic> data;
  final SidesisSocketIoMessageKind kind;

  bool get isHeartbeat => kind == SidesisSocketIoMessageKind.heartbeat;
  bool get isAlert => kind == SidesisSocketIoMessageKind.alert;

  String? get title => _string(data['title']);
  String? get identifier => _string(data['identifier'] ?? data['id']);
  String? get messageType => _string(data['msgType']);

  /// The top-level value exactly as supplied by the upstream message.
  String? get rawSeverity => _string(data['severity']);

  /// The severity shown by the website: info[0] first, then top-level.
  String? get severity => _string(firstInfo?['severity'] ?? data['severity']);

  SidesisSeverityLevel get asMxLevel => _levelFromSeverity(severity);

  /// Only the upstream `Severe` level is treated as an official alert.
  bool get isOfficialAlert => asMxLevel == SidesisSeverityLevel.severe;

  /// Minor and Moderate are detections without an official alert.
  bool get isNoAlertDetection =>
      asMxLevel == SidesisSeverityLevel.minor ||
      asMxLevel == SidesisSeverityLevel.moderate;

  String? get sent => _string(data['sent']);
  String? get updated => _string(data['updated']);

  Map<String, dynamic>? get firstInfo {
    final rawInfo = data['info'];
    if (rawInfo is! List || rawInfo.isEmpty || rawInfo.first is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(rawInfo.first as Map);
  }

  String? get event => _string(firstInfo?['event']);
  String? get description =>
      _string(firstInfo?['description'] ?? data['description']);

  static SidesisSocketIoMessage? tryParse(String eventName, dynamic rawData) {
    if (eventName != newMessageEvent && eventName != messageEvent) {
      return null;
    }
    if (rawData is! Map) return null;
    final data = Map<String, dynamic>.from(rawData);
    final hasSeverity = _string(data['severity'])?.isNotEmpty == true;
    final isHeartbeat = !hasSeverity && data['type'] == 'heartbeat';
    final kind = isHeartbeat
        ? SidesisSocketIoMessageKind.heartbeat
        : hasSeverity
        ? SidesisSocketIoMessageKind.alert
        : SidesisSocketIoMessageKind.other;
    return SidesisSocketIoMessage._(
      eventName: eventName,
      data: data,
      kind: kind,
    );
  }

  static String? _string(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static SidesisSeverityLevel _levelFromSeverity(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'minor':
        return SidesisSeverityLevel.minor;
      case 'moderate':
        return SidesisSeverityLevel.moderate;
      case 'severe':
        return SidesisSeverityLevel.severe;
      default:
        return SidesisSeverityLevel.unknown;
    }
  }
}
