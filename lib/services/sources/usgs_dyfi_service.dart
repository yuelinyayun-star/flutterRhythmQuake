import 'source_http_client.dart';
import 'dart:async';
import 'api_json_decoder.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/utils/quake_time.dart';
import '../../models/quake_message.dart';
import '../../models/usgs_dyfi.dart';
import '../native_dyfi_grid.dart';

/// DYFI products observe the official catalogue, independently of quake alerts.
class UsgsDyfiService extends ChangeNotifier {
  UsgsDyfiService({http.Client? client})
    : _client = client ?? createSourceHttpClient();
  final http.Client _client;
  final Map<String, QuakeMessage> _events = {};
  final Map<String, UsgsDyfiFrame> _frames = {};
  final Map<String, int?> _versions = {};
  final Map<String, String> _announced = {}, _errors = {};
  final Map<String, Future<UsgsDyfiFrame?>> _requests = {};
  final Set<String> _baseline = {};
  bool _primed = false, _disposed = false, _showSelected = true;
  double _threshold = 0;
  int _selectionSerial = 0;
  QuakeMessage? _selected;
  UsgsDyfiFrame? _automatic, _manual;
  Timer? _expiry;
  String? status;
  UsgsDyfiFrame? get automaticFrame => _automatic;
  UsgsDyfiFrame? get manualFrame => _manual;
  UsgsDyfiFrame? get frame => _selected != null ? _manual : _automatic;
  bool _passes(QuakeMessage e) =>
      _threshold >= 0 && (_threshold == 0 || e.magnitude >= _threshold);

  QuakeMessage _resolve(QuakeMessage event) {
    final exact = _events[event.eventId];
    if (exact != null) return exact;
    final matches = _events.values.where(
      (e) =>
          e.eventId.endsWith(event.eventId) &&
          QuakeTime.eventInstantUtc(e)
                  .difference(QuakeTime.eventInstantUtc(event))
                  .inMilliseconds
                  .abs() <=
              1000 &&
          (e.latitude - event.latitude).abs() <= .011 &&
          (e.longitude - event.longitude).abs() <= .011,
    );
    return matches.length == 1 ? matches.single : event;
  }

  UsgsDyfiFrame? frameFor(QuakeMessage event) {
    final resolved = _resolve(event);
    return _passes(resolved) ? _frames[resolved.eventId] : null;
  }

  String? errorFor(QuakeMessage event) => _errors[_resolve(event).eventId];

  void setMagnitudeFilter(double threshold) {
    if (_disposed || threshold == _threshold) return;
    _threshold = threshold;
    if (_automatic != null && !_passes(_resolve(_automatic!.event))) {
      _automatic = null;
      _expiry?.cancel();
    }
    if (_selected != null && !_passes(_resolve(_selected!))) {
      ++_selectionSerial;
      _manual = null;
      status = null;
    } else if (_selected != null && _showSelected && _manual == null) {
      unawaited(select(_selected));
    }
    notifyListeners();
  }

  Future<void> observe(List<QuakeMessage> events) async {
    if (_disposed) return;
    final eligible = events
        .where(
          (e) => e.source == QuakeSourceType.usgs && e.usgsDetailUrl != null,
        )
        .toList();
    if (eligible.isEmpty) return;
    if (!_primed) {
      _primed = true;
      _baseline.addAll(
        eligible
            .where(
              (e) => e.usgsProductTypes?.split(',').contains('dyfi') == true,
            )
            .map((e) => e.eventId),
      );
    }
    for (final e in eligible) {
      final old = _events[e.eventId];
      if (old == null || (e.usgsUpdated ?? 0) >= (old.usgsUpdated ?? 0)) {
        _events[e.eventId] = e;
      }
    }
    if (_automatic != null && !_passes(_resolve(_automatic!.event))) {
      _automatic = null;
      _expiry?.cancel();
      notifyListeners();
    }
    if (_manual != null && !_passes(_resolve(_manual!.event))) {
      ++_selectionSerial;
      _manual = null;
      status = null;
      notifyListeners();
    }
    final candidates = eligible
        .map(_resolve)
        .where(_passes)
        .where(
          (e) =>
              e.usgsProductTypes?.split(',').contains('dyfi') == true ||
              _frames.containsKey(e.eventId),
        )
        .take(50)
        .toList();
    for (
      var offset = 0;
      offset < candidates.length && !_disposed;
      offset += 3
    ) {
      await Future.wait(candidates.skip(offset).take(3).map(_refresh));
    }
    final keep = eligible.map((e) => e.eventId).toSet();
    if (_selected != null) keep.add(_resolve(_selected!).eventId);
    if (_automatic != null) keep.add(_automatic!.event.eventId);
    _events.removeWhere((id, _) => !keep.contains(id));
    _frames.removeWhere((id, _) => !keep.contains(id));
    _versions.removeWhere((id, _) => !keep.contains(id));
    _announced.removeWhere((id, _) => !keep.contains(id));
    _errors.removeWhere((id, _) => !keep.contains(id));
    _baseline.removeWhere((id) => !keep.contains(id));
  }

  Future<void> _refresh(QuakeMessage event) async {
    final id = event.eventId;
    if (_versions.containsKey(id) && _versions[id] == event.usgsUpdated) return;
    try {
      final result = await _request(event);
      if (_disposed || !_passes(_resolve(event))) return;
      _versions[id] = event.usgsUpdated;
      final baseline = _baseline.remove(id);
      if (result == null) {
        _announced.remove(id);
        if (_automatic?.event.eventId == id) {
          _automatic = null;
          _expiry?.cancel();
        }
        if (_manual?.event.eventId == id) _manual = null;
      } else {
        if (_showSelected &&
            _selected != null &&
            _resolve(_selected!).eventId == id) {
          _manual = result;
          status = null;
        }
        if (!baseline && _announced[id] != result.product.identity) {
          if (_automatic == null ||
              !result.product.updated.isBefore(_automatic!.product.updated)) {
            _automatic = result;
            _expiry?.cancel();
            _expiry = Timer(const Duration(minutes: 2), () {
              if (_disposed) return;
              _automatic = null;
              notifyListeners();
            });
          }
        }
        _announced[id] = result.product.identity;
      }
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      _errors[id] = 'DYFI 加载失败，点击可重试';
      notifyListeners();
    }
  }

  Future<void> select(QuakeMessage? event, {bool showProduct = true}) async {
    final serial = ++_selectionSerial;
    _selected = event;
    _showSelected = showProduct;
    status = null;
    if (event == null || event.source != QuakeSourceType.usgs || !showProduct) {
      _manual = null;
      notifyListeners();
      return;
    }
    event = _resolve(event);
    _selected = event;
    if (!_passes(event)) {
      _manual = null;
      notifyListeners();
      return;
    }
    _manual = _frames[event.eventId];
    status = _manual == null ? '正在加载 USGS DYFI' : null;
    notifyListeners();
    try {
      final result = await _request(event);
      if (_disposed ||
          serial != _selectionSerial ||
          !_passes(_resolve(event))) {
        return;
      }
      _manual = result;
      status = result == null ? 'USGS 尚未提供 DYFI' : null;
    } catch (_) {
      if (_disposed || serial != _selectionSerial) return;
      status = 'DYFI 加载失败，点击可重试';
    }
    if (!_disposed && serial == _selectionSerial) notifyListeners();
  }

  Future<UsgsDyfiFrame?> _request(QuakeMessage event) {
    final pending = _requests[event.eventId];
    if (pending != null) return pending;
    final request = _fetch(event);
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

  Future<UsgsDyfiFrame?> _fetch(QuakeMessage event) async {
    final uri = event.usgsDetailUrl == null
        ? Uri.https('earthquake.usgs.gov', '/fdsnws/event/1/query', {
            'eventid': event.eventId,
            'format': 'geojson',
          })
        : Uri.parse(event.usgsDetailUrl!);
    final detail = await _json(uri);
    if (_disposed) return null;
    final p = detail['properties'];
    if (p is! Map ||
        (detail['id'] != event.eventId &&
            p['code'] != event.eventId &&
            p['ids']?.toString().split(',').contains(event.eventId) != true)) {
      throw const FormatException('USGS DYFI event identity');
    }
    var product = UsgsDyfiProduct.fromDetail(detail);
    final previous = _frames[event.eventId];
    if (product == null) {
      _frames.remove(event.eventId);
      _errors.remove(event.eventId);
      return null;
    }
    if (previous != null &&
        (product.identity == previous.product.identity ||
            product.updated.isBefore(previous.product.updated))) {
      _errors.remove(event.eventId);
      return previous;
    }
    List<UsgsDyfiCell>? cells;
    if (product.gridUrl != null) {
      if (product.gridFormat == 'kmz') {
        final response = await _client
            .get(product.gridUrl!)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw StateError('USGS DYFI HTTP ${response.statusCode}');
        }
        final decoded = await NativeDyfiGrid.decodeKmz(response.bodyBytes);
        cells = UsgsDyfiCell.parse(
          Map<String, dynamic>.from(decoded['geojson'] as Map),
        );
        product = product.withGridResolution(decoded['gridKm'] as int?);
      } else {
        cells = UsgsDyfiCell.parse(await _json(product.gridUrl!));
      }
    }
    if (_disposed) return null;
    final frame = UsgsDyfiFrame(
      event: _resolve(event),
      product: product,
      cells: cells,
    );
    _frames[event.eventId] = frame;
    _errors.remove(event.eventId);
    return frame;
  }

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('USGS DYFI HTTP ${response.statusCode}');
    }
    final json = decodeApiJsonBytes(response.bodyBytes);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('USGS DYFI JSON');
    }
    return json;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_selectionSerial;
    _expiry?.cancel();
    _client.close();
    super.dispose();
  }
}
