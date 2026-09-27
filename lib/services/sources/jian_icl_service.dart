import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/source_status.dart';
import '../quake_event_adapter.dart';
import 'base_source.dart';

typedef JianIclSocketFactory = WebSocketChannel Function(Uri uri);

class JianIclTokenStore {
  JianIclTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'jian_icl.secure.token';
  final FlutterSecureStorage _storage;

  Future<bool> hasToken() async => (await read()).isNotEmpty;
  Future<String> read() async => (await _storage.read(key: storageKey)) ?? '';

  Future<void> write(String token) async {
    if (!RegExp(r'^ja_[A-Za-z0-9_-]+$').hasMatch(token)) {
      throw const FormatException('ICL Token 格式无效');
    }
    await _storage.write(key: storageKey, value: token);
  }

  Future<void> clear() => _storage.delete(key: storageKey);
}

class JianIclService extends BaseSourceService {
  static final JianIclService _instance = JianIclService._internal();
  factory JianIclService() => _instance;
  JianIclService._internal();

  static const sourceName = 'Jian ICL';
  static const enabledPreferenceKey = 'jian_icl_debug_enabled';
  static final endpoint = Uri.parse('wss://api.sismotide.top/icl');

  JianIclTokenStore tokenStore = JianIclTokenStore();
  JianIclSocketFactory socketFactory = (uri) => IOWebSocketChannel.connect(
    uri,
    connectTimeout: const Duration(seconds: 20),
  );

  final _stateController = StreamController<void>.broadcast();
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  bool _enabled = false;
  int _generation = 0;
  int _failures = 0;
  SourceStatus status = SourceStatus.disconnected;
  String? lastError;
  DateTime? lastFrameAt;
  int receivedEvents = 0;
  int unrecognizedFrames = 0;

  @override
  String get name => sourceName;
  @override
  bool get autoStart => false;
  bool get isEnabled => _enabled;
  Stream<void> get onDebugStateChanged => _stateController.stream;

  void _setStatus(SourceStatus value) {
    status = value;
    onStatusChanged?.call(value);
    _stateController.add(null);
  }

  @override
  void connect() {
    if (_enabled) return;
    _enabled = true;
    unawaited(_open());
  }

  void reloadToken() {
    if (!_enabled) return;
    disconnect();
    connect();
  }

  Future<void> _open() async {
    final generation = ++_generation;
    _setStatus(SourceStatus.connecting);
    String token;
    try {
      token = await tokenStore.read();
    } catch (_) {
      _fail(generation, '无法读取 ICL Token', retry: false);
      return;
    }
    if (!_current(generation)) return;
    if (token.isEmpty) {
      _fail(generation, '请先在 DEBUG 中填写 ICL Token', retry: false);
      return;
    }
    try {
      final uri = endpoint.replace(queryParameters: {'token': token});
      final socket = socketFactory(uri);
      _socket = socket;
      _subscription = socket.stream.listen(
        _receive,
        onError: (Object _) => _fail(generation, 'ICL 连接中断'),
        onDone: () => _fail(generation, 'ICL 连接关闭'),
      );
      await socket.ready.timeout(const Duration(seconds: 20));
      if (!_current(generation)) return;
      _failures = 0;
      lastError = null;
      _setStatus(SourceStatus.connected);
    } catch (_) {
      // WebSocket errors can include the query string. Never print them.
      _fail(generation, 'ICL 握手失败');
    }
  }

  bool _current(int generation) => _enabled && generation == _generation;

  void _receive(dynamic message) {
    try {
      final decoded = jsonDecode(
        message is String ? message : utf8.decode(message as List<int>),
      );
      if (decoded is! Map) return;
      final frame = Map<String, dynamic>.from(decoded);
      lastFrameAt = DateTime.now();
      if (frame['ok'] == false || frame['type'] == 'error') {
        _fail(_generation, 'ICL 服务拒绝连接', retry: false);
        return;
      }
      if (frame['type'] == 'heartbeat' || frame['type'] == 'pong') return;
      final event = QuakeEventAdapter.convertJianIcl(frame);
      if (event == null) {
        unrecognizedFrames++;
      } else {
        receivedEvents++;
        emitUnified(event);
      }
      _stateController.add(null);
    } catch (_) {
      unrecognizedFrames++;
      _stateController.add(null);
    }
  }

  void _fail(int generation, String reason, {bool retry = true}) {
    if (!_current(generation)) return;
    ++_generation;
    lastError = reason;
    _closeSocket();
    _setStatus(SourceStatus.error);
    if (retry) {
      final seconds = math.min(300, 45 * (1 << math.min(_failures++, 3)));
      _retryTimer = Timer(Duration(seconds: seconds), () => unawaited(_open()));
    }
  }

  void _closeSocket() {
    _retryTimer?.cancel();
    _retryTimer = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      unawaited(socket.sink.close().catchError((Object _) {}));
    }
  }

  @override
  void disconnect() {
    _enabled = false;
    ++_generation;
    _closeSocket();
    lastError = null;
    _setStatus(SourceStatus.disconnected);
  }
}
