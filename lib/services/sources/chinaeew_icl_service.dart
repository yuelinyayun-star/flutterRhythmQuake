import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/source_status.dart';
import '../../models/unified_quake_data.dart';
import '../quake_event_adapter.dart';
import 'base_source.dart';

class ChinaEewIclService extends BaseSourceService {
  static final ChinaEewIclService _instance = ChinaEewIclService._internal();
  factory ChinaEewIclService() => _instance;
  ChinaEewIclService._internal();

  static const sourceName = 'China_EEW_ICL';
  static const enabledPreferenceKey = 'chinaeew_icl_debug_enabled';
  static final listEndpoint = Uri.parse(
    'https://mobile-new.chinaeew.cn/v1/earlywarnings?start_at=&updates=',
  );
  static const pollInterval = Duration(seconds: 30);
  static const _seenReportLimit = 200;

  http.Client client = http.Client();
  final _stateController = StreamController<void>.broadcast();
  final Map<String, int> _seenReports = {};
  Timer? _pollTimer;
  bool _enabled = false;
  int? _inFlightGeneration;
  bool _hasBaseline = false;
  int _generation = 0;

  SourceStatus status = SourceStatus.disconnected;
  String? lastError;
  DateTime? lastPollAt;
  UnifiedQuakeData? latestListedEvent;
  int receivedReports = 0;
  int listedEvents = 0;

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
    _hasBaseline = false;
    _seenReports.clear();
    final generation = ++_generation;
    _setStatus(SourceStatus.connecting);
    unawaited(_poll(generation));
  }

  Future<void> refresh() async {
    if (!_enabled) return;
    await _poll(_generation);
  }

  Future<void> _poll(int generation) async {
    if (!_enabled ||
        generation != _generation ||
        _inFlightGeneration == generation) {
      return;
    }
    _inFlightGeneration = generation;
    _pollTimer?.cancel();
    try {
      final response = await client
          .get(listEndpoint)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['code'] != 0 || decoded['data'] is! List) {
        throw const FormatException('Invalid ICL warning list');
      }
      if (!_enabled || generation != _generation) return;
      final entries = (decoded['data'] as List).whereType<Map>().toList();
      listedEvents = entries.length;
      latestListedEvent = entries.isEmpty
          ? null
          : QuakeEventAdapter.convertChinaEewIcl(
              Map<String, dynamic>.from(entries.first),
              isSnapshot: true,
            );
      final baseline = !_hasBaseline;
      for (final entry in entries) {
        if (!_enabled || generation != _generation) return;
        final summary = Map<String, dynamic>.from(entry);
        final id = summary['eventId']?.toString();
        final revision = (summary['updates'] as num?)?.toInt();
        if (id == null || id.isEmpty || revision == null || revision < 1) {
          continue;
        }
        final previous = _seenReports[id];
        if (previous != null && revision <= previous) continue;
        _seenReports[id] = revision;
        if (_seenReports.length > _seenReportLimit) {
          final removeCount = _seenReports.length - _seenReportLimit;
          final oldest = _seenReports.keys.take(removeCount).toList();
          _seenReports.removeWhere((key, _) => oldest.contains(key));
        }
        if (baseline || !_isRecent(summary['updateAt'])) continue;
        final body = await _matchingDetail(id, revision) ?? summary;
        if (!_enabled || generation != _generation) return;
        final event = QuakeEventAdapter.convertChinaEewIcl(body);
        if (event == null) continue;
        emitUnified(event);
        receivedReports++;
      }
      _hasBaseline = true;
      lastPollAt = DateTime.now();
      lastError = null;
      _setStatus(SourceStatus.connected);
    } catch (error) {
      if (!_enabled || generation != _generation) return;
      lastError = error is FormatException ? '报文格式未识别' : '预警列表连接失败';
      _setStatus(SourceStatus.error);
    } finally {
      if (_inFlightGeneration == generation) _inFlightGeneration = null;
      if (_enabled && generation == _generation) {
        _pollTimer = Timer(pollInterval, () => unawaited(_poll(generation)));
      }
    }
  }

  Future<Map<String, dynamic>?> _matchingDetail(String id, int revision) async {
    try {
      final uri = Uri.parse('${listEndpoint.origin}/v1/earlywarnings/$id');
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['code'] != 0 || decoded['data'] is! List) {
        return null;
      }
      for (final entry in (decoded['data'] as List).reversed) {
        if (entry is Map && entry['updates'] == revision) {
          return Map<String, dynamic>.from(entry);
        }
      }
    } catch (_) {
      // The list report is still an original ICL EEW report without details.
    }
    return null;
  }

  static bool _isRecent(Object? value) {
    if (value is! num) return false;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      value.toInt(),
      isUtc: true,
    );
    final age = DateTime.now().toUtc().difference(timestamp);
    return age >= const Duration(seconds: -30) &&
        age <= const Duration(minutes: 2);
  }

  @override
  void disconnect() {
    _enabled = false;
    ++_generation;
    _pollTimer?.cancel();
    _pollTimer = null;
    lastError = null;
    _setStatus(SourceStatus.disconnected);
  }
}
