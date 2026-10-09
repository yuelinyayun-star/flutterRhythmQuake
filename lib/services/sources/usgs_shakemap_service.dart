import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/quake_message.dart';
import '../../models/usgs_shakemap.dart';
import '../../core/utils/quake_time.dart';

/// Observes the existing USGS catalogue; product updates never emit earthquakes.
class UsgsShakeMapService extends ChangeNotifier {
  UsgsShakeMapService({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  final Map<String, QuakeMessage> _events = {};
  final Map<String, int> _summaryVersions = {};
  final Map<String, UsgsShakeMapProduct?> _products = {};
  final Map<String, String> _announced = {};
  final Map<String, UsgsShakeMapFrame> _frames = {};
  final Map<String, Future<UsgsShakeMapProduct?>> _requests = {};
  final Set<String> _refreshing = {}, _baselineIds = {};
  bool _primed = false, _disposed = false;
  int _selectionSerial = 0;
  QuakeMessage? _selected;
  Timer? _autoExpiry;
  UsgsShakeMapFrame? _autoFrame, _manualFrame;
  String? status;
  double _magnitudeFilter = 0;
  UsgsShakeMapFrame? get frame => _selected != null ? _manualFrame : _autoFrame;

  bool _passesMagnitudeFilter(QuakeMessage event) =>
      _magnitudeFilter >= 0 &&
      (_magnitudeFilter == 0 || event.magnitude >= _magnitudeFilter);

  /// Shares USGS's source setting: zero permits all, negative disables it.
  void setMagnitudeFilter(double threshold) {
    if (_disposed || threshold == _magnitudeFilter) return;
    _magnitudeFilter = threshold;
    _hideFilteredFrames();
    final selected = _selected;
    if (selected?.source == QuakeSourceType.usgs &&
        _passesMagnitudeFilter(_resolve(selected!)) &&
        _manualFrame == null) {
      unawaited(select(selected));
    }
  }

  void _hideFilteredFrames() {
    var changed = false;
    final automatic = _autoFrame;
    if (automatic != null &&
        !_passesMagnitudeFilter(_resolve(automatic.event))) {
      _autoFrame = null;
      _autoExpiry?.cancel();
      changed = true;
    }
    final selected = _selected;
    if (selected?.source == QuakeSourceType.usgs &&
        !_passesMagnitudeFilter(_resolve(selected!))) {
      ++_selectionSerial;
      changed = changed || _manualFrame != null || status != null;
      _manualFrame = null;
      status = null;
    }
    if (changed) notifyListeners();
  }

  Future<void> observe(List<QuakeMessage> events) async {
    if (_disposed || events.isEmpty) return;
    final eligible = events
        .where(
          (e) => e.source == QuakeSourceType.usgs && e.usgsDetailUrl != null,
        )
        .toList();
    if (eligible.isEmpty) return;
    final baseline = !_primed;
    _primed = true;
    if (baseline) {
      _baselineIds.addAll(
        eligible
            .where(
              (e) =>
                  e.usgsProductTypes?.split(',').contains('shakemap') == true,
            )
            .map((e) => e.eventId),
      );
    }
    for (final event in eligible) {
      _events[event.eventId] = event;
    }
    _hideFilteredFrames();
    // Metadata is available for every catalogue event. Only ShakeMap products
    // need detail requests, including earthquakes whose information card expired.
    final candidates = eligible
        .where(_passesMagnitudeFilter)
        .where(
          (e) =>
              e.usgsProductTypes?.split(',').contains('shakemap') == true ||
              _products[e.eventId] != null,
        )
        .take(50);
    final refresh = _refreshCandidates(candidates.toList());
    if (_selected != null) {
      final latest = _resolve(_selected!);
      if (latest.usgsUpdated != _selected!.usgsUpdated) {
        unawaited(select(latest));
      }
    }
    final liveIds = eligible.map((e) => e.eventId).toSet();
    if (_selected != null) liveIds.add(_selected!.eventId);
    if (_autoFrame != null) liveIds.add(_autoFrame!.event.eventId);
    _events.removeWhere((key, _) => !liveIds.contains(key));
    _products.removeWhere((key, _) => !liveIds.contains(key));
    _summaryVersions.removeWhere((key, _) => !liveIds.contains(key));
    _announced.removeWhere((key, _) => !liveIds.contains(key));
    _baselineIds.removeWhere((key) => !liveIds.contains(key));
    await refresh;
  }

  Future<void> _refreshCandidates(List<QuakeMessage> events) async {
    // Limit concurrent detail fetches rather than flooding the public endpoint.
    for (var offset = 0; offset < events.length && !_disposed; offset += 3) {
      await Future.wait(
        events.skip(offset).take(3).map((event) async {
          final version = event.usgsUpdated;
          if (version == null ||
              _summaryVersions[event.eventId] == version ||
              !_refreshing.add(event.eventId)) {
            return;
          }
          try {
            final previous = _products[event.eventId];
            final product = await _detail(event);
            if (_disposed) return;
            if (!_passesMagnitudeFilter(_resolve(event))) return;
            if (!_products.containsKey(event.eventId)) return; // failed request
            if (product == null) {
              _summaryVersions[event.eventId] = version;
              _baselineIds.remove(event.eventId);
              _announced.remove(event.eventId);
              _frames.remove(event.eventId);
              if (_autoFrame?.event.eventId == event.eventId) _autoFrame = null;
              if (_selected?.eventId == event.eventId) _manualFrame = null;
              notifyListeners();
              return;
            }
            final firstBaseline = _baselineIds.remove(event.eventId);
            if (firstBaseline ||
                product.identity == _announced[event.eventId] ||
                (previous != null &&
                    product.updated.isBefore(previous.updated))) {
              _summaryVersions[event.eventId] = version;
              _announced[event.eventId] = product.identity;
              return;
            }
            final result = await _loadFrame(event, product);
            if (_disposed ||
                result == null ||
                !_passesMagnitudeFilter(_resolve(event)) ||
                _products[event.eventId]?.identity != product.identity) {
              return;
            }
            _summaryVersions[event.eventId] = version;
            _announced[event.eventId] = product.identity;
            if (result.contours.isEmpty) {
              if (_autoFrame?.event.eventId == event.eventId) {
                _autoFrame = null;
                _autoExpiry?.cancel();
                notifyListeners();
              }
              return;
            }
            // Concurrent updates display the most recently published product.
            if (_autoFrame != null &&
                product.updated.isBefore(_autoFrame!.product.updated)) {
              return;
            }
            _autoFrame = result;
            _autoExpiry?.cancel();
            _autoExpiry = Timer(const Duration(minutes: 2), () {
              if (_disposed) return;
              _autoFrame = null;
              notifyListeners();
            });
            notifyListeners();
          } catch (_) {
            // Retain the previous map and retry on the next catalogue update.
          } finally {
            _refreshing.remove(event.eventId);
          }
        }),
      );
    }
  }

  QuakeMessage _resolve(QuakeMessage event) {
    final exact = _events[event.eventId];
    if (exact != null) return exact;
    // FAN's USGS ID is properties.code, whereas the official list uses id.
    final matches = _events.values.where(
      (e) =>
          e.eventId.endsWith(event.eventId) &&
          QuakeTime.eventInstantUtc(e)
                  .difference(QuakeTime.eventInstantUtc(event))
                  .inMilliseconds
                  .abs() <=
              1000 &&
          (e.latitude - event.latitude).abs() <= 0.011 &&
          (e.longitude - event.longitude).abs() <= 0.011,
    );
    return matches.length == 1 ? matches.single : event;
  }

  Future<void> select(QuakeMessage? event) async {
    final serial = ++_selectionSerial;
    _selected = event;
    status = null;
    if (event == null || event.source != QuakeSourceType.usgs) {
      _manualFrame = null;
      notifyListeners();
      return;
    }
    event = _resolve(event);
    _selected = event;
    if (!_passesMagnitudeFilter(event)) {
      _manualFrame = null;
      notifyListeners();
      return;
    }
    // Keep the current contours during a same-event version refresh.
    if (_manualFrame?.event.eventId != event.eventId) {
      _manualFrame = _frames[event.eventId];
    }
    status = '正在加载 USGS ShakeMap';
    notifyListeners();
    try {
      final product = await _detail(event, force: true);
      if (_disposed || serial != _selectionSerial) return;
      if (!_passesMagnitudeFilter(_resolve(event))) return;
      if (product == null) {
        _manualFrame = null;
        status = _products.containsKey(event.eventId)
            ? 'USGS 尚未提供 ShakeMap'
            : 'USGS ShakeMap 加载失败，点击列表可重试';
      } else {
        final result = await _loadFrame(event, product);
        if (_disposed || serial != _selectionSerial) return;
        if (result != null) _manualFrame = result;
        status = product.contoursUrl == null
            ? 'USGS 本版尚未提供 MMI 等烈度线'
            : result == null
            ? 'USGS ShakeMap 加载失败，点击列表可重试'
            : result.contours.isEmpty
            ? 'USGS 本版无可绘制的 MMI 等烈度线'
            : null;
      }
    } catch (_) {
      if (_disposed || serial != _selectionSerial) return;
      status = 'USGS ShakeMap 加载失败，点击列表可重试';
    }
    if (!_disposed && serial == _selectionSerial) notifyListeners();
  }

  Future<UsgsShakeMapProduct?> _detail(
    QuakeMessage event, {
    bool force = false,
  }) {
    final pending = _requests[event.eventId];
    if (pending != null) return pending;
    if (!force &&
        _summaryVersions[event.eventId] == event.usgsUpdated &&
        _products.containsKey(event.eventId)) {
      return Future.value(_products[event.eventId]);
    }
    final request = _fetchDetail(event);
    _requests[event.eventId] = request;
    unawaited(
      request.then<void>(
        (_) => _requests.remove(event.eventId),
        onError: (Object error, StackTrace stack) {
          _requests.remove(event.eventId);
        },
      ),
    );
    return request;
  }

  Future<UsgsShakeMapProduct?> _fetchDetail(QuakeMessage event) async {
    try {
      final uri = event.usgsDetailUrl != null
          ? Uri.parse(event.usgsDetailUrl!)
          : Uri.https('earthquake.usgs.gov', '/fdsnws/event/1/query', {
              'format': 'geojson',
              'eventid': event.eventId,
            });
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 20));
      if (_disposed) return null;
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('USGS detail');
      }
      final properties = decoded['properties'];
      if (properties is! Map ||
          (decoded['id'] != event.eventId &&
              properties['code'] != event.eventId &&
              properties['ids']
                      ?.toString()
                      .split(',')
                      .contains(event.eventId) !=
                  true)) {
        throw const FormatException('USGS event identity');
      }
      final product = UsgsShakeMapProduct.fromDetail(decoded);
      final previous = _products[event.eventId];
      if (previous != null &&
          product != null &&
          product.updated.isBefore(previous.updated)) {
        return previous;
      }
      _products[event.eventId] = product;
      return product;
    } catch (_) {
      rethrow;
    }
  }

  Future<UsgsShakeMapFrame?> _loadFrame(
    QuakeMessage event,
    UsgsShakeMapProduct product,
  ) async {
    final cached = _frames[event.eventId];
    if (cached?.product.identity == product.identity) return cached;
    try {
      final url = product.contoursUrl;
      if (url == null) return null;
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 20));
      if (_disposed || response.statusCode != 200) return null;
      final raw = jsonDecode(utf8.decode(response.bodyBytes));
      if (raw is! Map<String, dynamic>) return null;
      final contours = UsgsMmiContour.parse(raw);
      if (_disposed || _products[event.eventId]?.identity != product.identity) {
        return null;
      }
      final frame = UsgsShakeMapFrame(
        event: event,
        product: product,
        contours: contours,
      );
      _frames.remove(event.eventId);
      _frames[event.eventId] = frame;
      while (_frames.length > 20) {
        _frames.remove(_frames.keys.first);
      }
      return frame;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _selectionSerial++;
    _autoExpiry?.cancel();
    _client.close();
    super.dispose();
  }
}
