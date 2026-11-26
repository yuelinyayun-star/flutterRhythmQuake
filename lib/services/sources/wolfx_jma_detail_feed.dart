import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/unified_quake_data.dart';
import '../quake_event_adapter.dart';
import 'source_http_client.dart';
import 'wolfx_jma_detail_decoder.dart';

/// Wolfx publishes detailed JMA reports over HTTP independently of its socket.
class WolfxJmaDetailFeed {
  WolfxJmaDetailFeed({
    this.onReport,
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? createSourceHttpClient(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now;

  static final _uri = Uri.https('api.wolfx.jp', '/jma_earthquake_detail.json');
  static const refreshInterval = Duration(seconds: 10);

  final void Function(UnifiedQuakeData)? onReport;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final Set<(String, String)> _seen = {};
  Timer? _timer;
  String? _etag;
  String? _digest;
  bool _hasSnapshot = false;
  Future<void>? _request;
  DateTime? _lastSnapshotAt;
  Map<(String, String), UnifiedQuakeData> _observations = const {};
  int _generation = 0;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(fetchNow()));
    unawaited(fetchNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _generation++;
  }

  void dispose() {
    stop();
    if (_ownsClient) _client.close();
  }

  /// Read a live snapshot or wait for the poll already in progress.
  Future<List<UnifiedQuakeData>>? runningObservationSnapshot() {
    if (_timer == null) return null;
    final request = _request;
    if (request == null && !_hasFreshSnapshot) return null;
    final generation = _generation;
    return request == null
        ? Future.value(_observations.values.toList(growable: false))
        : request.then(
            (_) => generation == _generation
                ? _observations.values.toList(growable: false)
                : const [],
          );
  }

  bool get _hasFreshSnapshot {
    final at = _lastSnapshotAt;
    return at != null && _now().difference(at) < refreshInterval;
  }

  /// An on-demand map reader uses its own feed without a live report callback.
  Future<List<UnifiedQuakeData>> observedReports() async {
    final generation = _generation;
    if (_request != null || !_hasFreshSnapshot) {
      await fetchNow();
    }
    return generation == _generation
        ? _observations.values.toList(growable: false)
        : const [];
  }

  @visibleForTesting
  Future<void> fetchNow() => _request ??= _fetch().whenComplete(() {
    _request = null;
  });

  Future<void> _fetch() async {
    final generation = _generation;
    try {
      final response = await _client
          .get(_uri, headers: {if (!kIsWeb) 'If-None-Match': ?_etag})
          .timeout(const Duration(seconds: 8));
      if (_generation != generation) return;
      if (response.statusCode == 304) {
        _lastSnapshotAt = _now();
        return;
      }
      if (response.statusCode != 200) {
        debugPrint('Wolfx JMA detail HTTP ${response.statusCode}');
        return;
      }
      final data = decodeWolfxJmaDetail(response.bodyBytes);
      final digest = data['md5'];
      if (digest is! String || digest.isEmpty || digest != _digest) {
        _updateSnapshot((data['reports'] as List).cast<Map<String, dynamic>>());
        if (_generation != generation) return;
        _digest = digest is String ? digest : null;
      }
      _etag = response.headers['etag'];
      _hasSnapshot = true;
      _lastSnapshotAt = _now();
    } catch (error) {
      if (_generation == generation) {
        debugPrint('Wolfx JMA detail error: $error');
      }
    }
  }

  void _updateSnapshot(List<Map<String, dynamic>> rows) {
    final generation = _generation;
    final observations = <(String, String), UnifiedQuakeData>{};
    final pending = <({(String, String) key, UnifiedQuakeData event})>[];
    for (final row in rows) {
      final report = row['report'] as Map<String, dynamic>;
      final key = (row['eventId'] as String, report['id'] as String);
      final seen = _seen.contains(key);
      final previous = _observations[key];
      if (previous != null) {
        observations[key] = previous;
        if (seen || onReport == null) continue;
      }
      if (report['product'] == 'VXSE62' && (seen || onReport == null)) continue;
      final event = QuakeEventAdapter.convertWolfxJmaDetail(
        row,
        isSnapshot: !_hasSnapshot,
      );
      if (event != null &&
          !event.isJmaLpgm &&
          !event.isCanceled &&
          event.warnArea.isNotEmpty) {
        observations[key] = event;
      }
      if (onReport == null || seen) continue;
      if (event == null || !_isCurrentObservation(event)) {
        _seen.add(key);
      } else {
        pending.add((key: key, event: event));
      }
    }
    _observations = observations;
    pending.sort((left, right) {
      final a =
          left.event.jmaLpgmBulletin?.freshnessTime ?? left.event.reportTime;
      final b =
          right.event.jmaLpgmBulletin?.freshnessTime ?? right.event.reportTime;
      if (a == null) return b == null ? 0 : -1;
      if (b == null) return 1;
      return a.compareTo(b);
    });
    for (final row in pending) {
      if (_generation != generation) return;
      if (_seen.add(row.key)) onReport?.call(row.event);
    }
    while (_seen.length > 1024) {
      _seen.remove(_seen.first);
    }
  }

  bool _isCurrentObservation(UnifiedQuakeData event) {
    final bulletin = event.jmaLpgmBulletin;
    if (bulletin == null) return true;
    final stamp = bulletin.freshnessTime;
    if (stamp == null) return false;
    final now = _now();
    return bulletin.isCanceled
        ? now.difference(stamp) <= const Duration(minutes: 1)
        : bulletin.isActive(now: now);
  }
}
