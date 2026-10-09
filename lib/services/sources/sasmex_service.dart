import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'base_source.dart';
import 'sasmex_report_sequence.dart';
import '../../models/quake_message.dart';
import '../../models/source_payload.dart';
import '../../models/source_status.dart';
import '../../models/unified_quake_data.dart';
import '../../utils/catalog_location.dart';

/// RhythmQuake 服务端的 SASMEX 实时中继。
///
/// APP 只连接我们的 WSS。网页使用的 Socket.IO 上游由服务器端处理中继，
/// 不在客户端直接连接网页上游。
class SasmexService extends BaseSourceService {
  static const sourceName = 'SASMEX';
  static const enabledPreferenceKey = 'api_source_sasmex_enabled';
  static const defaultUrl = 'wss://ws.yuelinrhythm.top/sasmex-eew';
  static const adapterOrigin = 8;
  // Stateless decoding starts at report 1; the receiver assigns the persistent
  // local revision sequence without writing it into the source payload.
  static const _defaultReportText = '第1報';
  static const _reportsPreferenceKey = 'sasmex_report_sequence_v1';

  SasmexService({this.url = defaultUrl});

  final String url;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _generation = 0;
  int _retryCount = 0;
  bool _running = false;
  final _reports = SasmexReportSequence();
  SharedPreferences? _prefs;
  Future<void>? _reportsLoaded;
  Future<void> _reportsSaved = Future<void>.value();

  @override
  String get name => sourceName;

  @override
  void connect() {
    if (_running) return;
    _running = true;
    _retryCount = 0;
    unawaited(_open());
  }

  Future<void> _open() async {
    final generation = ++_generation;
    onStatusChanged?.call(SourceStatus.connecting);
    _closeSocket();
    try {
      await _loadReports();
      if (!_running || generation != _generation) return;
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 20));
      if (!_current(channel, generation)) return;
      _retryCount = 0;
      onStatusChanged?.call(SourceStatus.connected);
      _startPing(channel, generation);
      _subscription = channel.stream.listen(
        (message) => _receive(channel, generation, message),
        onError: (Object _) => _fail(channel, generation),
        onDone: () => _fail(channel, generation),
        cancelOnError: true,
      );
    } catch (_) {
      _fail(null, generation);
    }
  }

  void _receive(WebSocketChannel channel, int generation, dynamic message) {
    if (!_current(channel, generation)) return;
    try {
      final text = message is String
          ? message
          : utf8.decode(message as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final frame = Map<String, dynamic>.from(decoded);
      final event = _acceptRelayFrame(frame);
      if (event == null) return;
      emitUnified(event);
      onStatusChanged?.call(SourceStatus.connected);
    } catch (_) {
      // Invalid frames do not terminate a healthy connection.
    }
  }

  Future<void> _loadReports() => _reportsLoaded ??= (() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Android foreground/background isolates share state.
    _prefs = prefs;
    final encoded = prefs.getString(_reportsPreferenceKey);
    if (encoded == null) return;
    try {
      _reports.restore(encoded);
    } catch (error) {
      debugPrint('SASMEX: invalid saved report sequence: $error');
    }
  })();

  UnifiedQuakeData? _acceptRelayFrame(Map<String, dynamic> frame) {
    final decoded = parseRelayFrame(frame);
    if (decoded == null) return null;
    final before = _reports.encode();
    final accepted = _reports.accept(decoded);
    if (accepted == null) return null;
    final encoded = _reports.encode();
    if (encoded != before) {
      // Serialize writes so a preceding report cannot overwrite the latest one.
      _reportsSaved = _reportsSaved
          .then((_) async {
            final saved = await _prefs!.setString(
              _reportsPreferenceKey,
              encoded,
            );
            if (!saved) debugPrint('SASMEX: report sequence was not saved');
          })
          .catchError((Object error) {
            debugPrint('SASMEX: report sequence save failed: $error');
          });
    }
    return accepted;
  }

  @visibleForTesting
  Future<UnifiedQuakeData?> acceptRelayFrameForTest(
    Map<String, dynamic> frame,
  ) async {
    await _loadReports();
    return _acceptRelayFrame(frame);
  }

  @visibleForTesting
  Future<void> flushReportsForTest() => _reportsSaved;

  @visibleForTesting
  static UnifiedQuakeData? parseRelayFrame(Map<String, dynamic> frame) {
    final type = frame['type'];
    if (type != 'update' && type != 'snapshot' && type != 'query_response') {
      return null;
    }
    final data = frame['Data'];
    if (data is! Map) return null;
    final body = Map<String, dynamic>.from(data);
    final event = parseRelayEvent(body);
    if (event == null) return null;
    final hasCoordinates =
        event.latitude.isFinite &&
        event.longitude.isFinite &&
        event.latitude.abs() <= 90 &&
        event.longitude.abs() <= 180;
    final originalLocation =
        _string(body['region'] ?? body['place'] ?? body['location']) ?? '';
    return UnifiedQuakeData(
      source: 'sasmex',
      origin: adapterOrigin,
      eventId: event.eventId,
      isEew: true,
      timeZone: 0,
      titleText: event.infoTypeName!,
      reportNumText: _defaultReportText,
      useShindo: false,
      maxIntensity: '-',
      className: event.isWarn ? 'red' : 'yellow',
      hypocenter: catalogDisplayLocation(
        originalLocation,
        hasCoordinates ? event.latitude : null,
        hasCoordinates ? event.longitude : null,
      ),
      originTime: event.originTime,
      reportTime: event.reportTime,
      lat: hasCoordinates ? event.latitude : null,
      lng: hasCoordinates ? event.longitude : null,
      isWarn: event.isWarn,
      apiTypeLabel: 'Rhythm',
      isSnapshot: type != 'update',
      hasReportSequence: false,
      useSourceTimeForExpiry: true,
      arrivedAt: DateTime.now(),
      sourcePayload: snapshotSourcePayload(body),
    );
  }

  @visibleForTesting
  static QuakeMessage? parseRelayEvent(Map<String, dynamic> data) {
    if (data['type'] == 'heartbeat' ||
        data['isSimulation'] == true ||
        data['isReplay'] == true) {
      return null;
    }
    final eventId = _string(data['eventId'] ?? data['id']);
    final originTime =
        _parseTime(data['epochMs']) ??
        _parseIsoTime(data['sent']) ??
        _parseIsoTime(data['updated']);
    if (eventId == null || originTime == null) return null;

    final severity = _string(data['severity'])?.toLowerCase();
    final isWarn = severity == 'severe';
    final location =
        _string(data['region'] ?? data['place'] ?? data['location']) ??
        _string(data['event']) ??
        _string(data['description']) ??
        'SASMEX';

    return QuakeMessage(
      source: QuakeSourceType.sasmex,
      eventId: eventId,
      location: location,
      magnitude: -1,
      latitude: _number(data['lat']) ?? double.nan,
      longitude: _number(data['lng']) ?? double.nan,
      depth: -1,
      originTime: originTime,
      maxIntensity: null,
      isInfoEvent: false,
      isWarn: isWarn,
      reportTime: _parseIsoTime(data['updated']) ?? _parseIsoTime(data['sent']),
      timeZone: 0,
      infoTypeName: displayTitle(severity: severity),
      reportNumText: _defaultReportText,
      apiTypeLabel: 'Rhythm',
    );
  }

  /// 对齐网页全局警报：Severe 不依赖用户位置或测站距离。
  @visibleForTesting
  static String displayTitle({required String? severity}) {
    final normalized = severity?.trim().toLowerCase();
    if (normalized == 'severe') {
      return 'SASMEX 地震警报';
    }
    return 'SASMEX 地震检出';
  }

  static DateTime? _parseTime(dynamic value) {
    final number = _number(value);
    if (number == null) return null;
    final milliseconds = number.abs() < 100000000000
        ? (number * 1000).round()
        : number.round();
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  static DateTime? _parseIsoTime(dynamic value) {
    final text = _string(value);
    if (text == null) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static double? _number(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    final parsed = double.tryParse(value?.toString().trim() ?? '');
    return parsed?.isFinite == true ? parsed : null;
  }

  static String? _string(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  bool _current(WebSocketChannel channel, int generation) =>
      _running && generation == _generation && identical(_channel, channel);

  void _startPing(WebSocketChannel channel, int generation) {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_current(channel, generation)) {
        channel.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _fail(WebSocketChannel? channel, int generation) {
    if (!_running || generation != _generation) return;
    if (channel != null && !identical(_channel, channel)) return;
    _closeSocket();
    onStatusChanged?.call(SourceStatus.error);
    final delay = Duration(seconds: (3 + _retryCount++).clamp(3, 15));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_running) unawaited(_open());
    });
  }

  void _closeSocket() {
    _pingTimer?.cancel();
    _pingTimer = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.sink.close());
  }

  @override
  void disconnect() {
    _running = false;
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeSocket();
    onStatusChanged?.call(SourceStatus.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
