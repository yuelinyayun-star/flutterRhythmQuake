import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/intensity_calculator.dart';
import '../../models/quake_message.dart';
import '../../utils/fe_regions.dart';

typedef EmscSocketFactory = WebSocketChannel Function(Uri uri);
typedef EmscSnapshotLoader = Future<List<dynamic>> Function();

/// Official EMSC standing-order feed. HTTP is used once per connection to
/// populate/catch up the history; realtime events always come from WebSocket.
class EmscEqlistService {
  static const double _minimumMagnitude = 3.0;
  static final EmscEqlistService _instance = EmscEqlistService.detached();
  factory EmscEqlistService() => _instance;

  @visibleForTesting
  EmscEqlistService.detached({
    EmscSocketFactory? socketFactory,
    EmscSnapshotLoader? snapshotLoader,
    this.reconnectDelay = const Duration(seconds: 2),
  }) : _socketFactory = socketFactory ?? _openSocket,
       _snapshotLoader = snapshotLoader ?? _loadSnapshot;

  static final endpoint = Uri.parse(
    'wss://www.seismicportal.eu/standing_order/websocket',
  );
  static final historyEndpoint = Uri.parse(
    'https://www.seismicportal.eu/fdsnws/event/1/query?format=json&limit=50&orderby=time&minmag=3.0',
  );

  static WebSocketChannel _openSocket(Uri uri) => kIsWeb
      ? WebSocketChannel.connect(uri)
      : IOWebSocketChannel.connect(
          uri,
          pingInterval: const Duration(seconds: 15),
          connectTimeout: const Duration(seconds: 15),
        );

  static Future<List<dynamic>> _loadSnapshot() async {
    final response = await http
        .get(historyEndpoint)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('EMSC history HTTP ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map || body['features'] is! List) {
      throw const FormatException('EMSC history has no features');
    }
    return body['features'] as List;
  }

  final EmscSocketFactory _socketFactory;
  final EmscSnapshotLoader _snapshotLoader;
  final Duration reconnectDelay;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _running = false;
  bool _connected = false;
  int _generation = 0;
  int _failures = 0;
  final Map<String, _EmscRecord> _records = {};
  final Set<String> _liveEventIds = {};
  final List<QuakeMessage> _latestList = [];

  bool get isRunning => _running;
  bool get isConnected => _connected;
  List<QuakeMessage> get latestList => List.unmodifiable(_latestList);
  void Function(List<QuakeMessage>)? onListUpdated;
  void Function(Map<String, dynamic>)? onCurrentUpdated;
  void Function(bool connected)? onStatusChanged;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    ++_generation;
    _failures = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(_close(socket));
    _setConnected(false);
  }

  void _setConnected(bool value) {
    _connected = value;
    onStatusChanged?.call(value);
  }

  bool _active(int generation) => _running && generation == _generation;

  Future<void> _connect() async {
    final generation = ++_generation;
    _liveEventIds.clear();
    try {
      final socket = _socketFactory(endpoint);
      _socket = socket;
      // Listen before ready, so the first data frame cannot fall in a gap.
      _subscription = socket.stream.listen(
        (frame) {
          if (_active(generation)) _onFrame(frame);
        },
        onError: (Object error) => _lost(generation, error),
        onDone: () => _lost(generation, null),
      );
      await socket.ready.timeout(const Duration(seconds: 15));
      if (!_active(generation)) return;
      _failures = 0;
      _setConnected(true);
      debugPrint('EMSC: official WebSocket connected');
      try {
        final features = await _snapshotLoader();
        if (!_active(generation)) return;
        for (final feature in features) {
          _acceptFeature(feature, publishCurrent: false);
        }
        _publishList();
      } catch (error) {
        // History failure does not turn a working WS connection offline.
        debugPrint('EMSC: history sync failed: $error');
      }
    } catch (error) {
      _lost(generation, error);
    }
  }

  void _lost(int generation, Object? error) {
    if (!_active(generation)) return;
    ++_generation;
    _setConnected(false);
    _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(_close(socket));
    if (error != null) debugPrint('EMSC: WebSocket disconnected: $error');
    final multiplier = 1 << math.min(_failures++, 5);
    final delay = Duration(
      milliseconds: math.min(reconnectDelay.inMilliseconds * multiplier, 60000),
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_running) _connect();
    });
  }

  static Future<void> _close(WebSocketChannel socket) async {
    try {
      await socket.sink.close();
    } catch (error) {
      debugPrint('EMSC: socket close failed: $error');
    }
  }

  void _onFrame(dynamic frame) {
    try {
      final text = frame is List<int> ? utf8.decode(frame) : frame as String;
      final message = jsonDecode(text);
      if (message is! Map || message['data'] is! Map) return;
      // The official protocol supplies {action, data: GeoJSON Feature}.
      final action = message['action']?.toString().toLowerCase();
      if (action != 'create' && action != 'update') return;
      if (_acceptFeature(
        message['data'],
        publishCurrent: true,
        rawMessage: Map<String, dynamic>.from(message),
      )) {
        _publishList();
      }
    } catch (error) {
      debugPrint('EMSC: invalid WebSocket frame: $error');
    }
  }

  bool _acceptFeature(
    Object? feature, {
    required bool publishCurrent,
    Map<String, dynamic>? rawMessage,
  }) {
    final record = _EmscRecord.parse(feature);
    if (record == null || record.magnitude < _minimumMagnitude) return false;
    final previous = _records[record.eventId];
    if (previous != null) {
      // The REST snapshot starts after the live subscription. Never let its
      // response overwrite any event already received from this WS session.
      // Records from an earlier connection can still be caught up silently.
      if (!publishCurrent && _liveEventIds.contains(record.eventId)) {
        return false;
      }
      final oldTime = previous.updated;
      final newTime = record.updated;
      if (oldTime != null && (newTime == null || newTime.isBefore(oldTime))) {
        return false;
      }
      if (mapEquals(previous.props, record.props) &&
          listEquals(
            (previous.feature['geometry'] as Map)['coordinates'] as List,
            (record.feature['geometry'] as Map)['coordinates'] as List,
          )) {
        return false;
      }
    }
    _records[record.eventId] = record;
    if (publishCurrent) {
      _liveEventIds.add(record.eventId);
      onCurrentUpdated?.call({
        ...record.unifiedFields,
        'originalData': rawMessage ?? record.feature,
      });
    }
    return true;
  }

  void _publishList() {
    final records = _records.values.toList()
      ..sort((a, b) => b.origin.compareTo(a.origin));
    _latestList
      ..clear()
      ..addAll(records.take(50).map((record) => record.quake));
    // Keep revision guards for the current list without unbounded growth.
    final retained = records.take(50).map((record) => record.eventId).toSet();
    _records.removeWhere((id, _) => !retained.contains(id));
    _liveEventIds.retainAll(retained);
    onListUpdated?.call(latestList);
  }
}

class _EmscRecord {
  _EmscRecord(
    this.feature,
    this.props,
    this.eventId,
    this.origin,
    this.updated,
    this.longitude,
    this.latitude,
    this.magnitude,
    this.depth,
  );

  final Map<String, dynamic> feature;
  final Map<String, dynamic> props;
  final String eventId;
  final DateTime origin;
  final DateTime? updated;
  final double longitude, latitude, magnitude, depth;

  static _EmscRecord? parse(Object? raw) {
    if (raw is! Map) return null;
    final feature = Map<String, dynamic>.from(raw);
    final propsRaw = feature['properties'];
    final geometry = feature['geometry'];
    if (propsRaw is! Map || geometry is! Map) return null;
    final props = Map<String, dynamic>.from(propsRaw);
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final longitude = double.tryParse(coords[0].toString());
    final latitude = double.tryParse(coords[1].toString());
    final magnitude = double.tryParse(props['mag']?.toString() ?? '');
    final depth = double.tryParse(props['depth']?.toString() ?? '');
    final origin = DateTime.tryParse(props['time']?.toString() ?? '')?.toUtc();
    final updated = DateTime.tryParse(
      props['lastupdate']?.toString() ?? '',
    )?.toUtc();
    final unid = props['unid']?.toString().trim() ?? '';
    final eventId = unid.isNotEmpty
        ? unid
        : feature['id']?.toString().trim() ?? '';
    if (eventId.isEmpty ||
        origin == null ||
        longitude == null ||
        latitude == null ||
        magnitude == null ||
        depth == null ||
        !longitude.isFinite ||
        !latitude.isFinite ||
        !magnitude.isFinite ||
        !depth.isFinite ||
        longitude.abs() > 180 ||
        latitude.abs() > 90) {
      return null;
    }
    return _EmscRecord(
      feature,
      props,
      eventId,
      origin,
      updated,
      longitude,
      latitude,
      magnitude,
      depth,
    );
  }

  String get location {
    final chinese = getFEName(latitude, longitude);
    return chinese.isNotEmpty
        ? chinese
        : props['flynn_region']?.toString() ??
              props['region']?.toString() ??
              '';
  }

  int get intensity => IntensityCalculator.calcCsisLevel(magnitude, depth, 0);

  Map<String, dynamic> get unifiedFields => {
    'eventId': eventId,
    'location': location,
    'latitude': latitude,
    'longitude': longitude,
    'depth': depth,
    'originTime': origin.toIso8601String(),
    'shockTime': origin.toIso8601String(),
    'createTime': updated?.toIso8601String(),
    'updateTime': updated?.toIso8601String(),
    'magnitude': magnitude,
    'maxIntensity': intensity,
  };

  QuakeMessage get quake => QuakeMessage(
    source: QuakeSourceType.emsc,
    eventId: eventId,
    location: location,
    magnitude: magnitude,
    latitude: latitude,
    longitude: longitude,
    depth: depth,
    originTime: origin.toLocal(),
    reportTime: updated?.toLocal(),
    timeZone: DateTime.now().timeZoneOffset.inMinutes ~/ 60,
    isHistory: true,
    maxIntensity: intensity,
    reviewType: '自动测定',
    infoTypeName: props['auth']?.toString() ?? 'EMSC',
    isInfoEvent: true,
  );
}
