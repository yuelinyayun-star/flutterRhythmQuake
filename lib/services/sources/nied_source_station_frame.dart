import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'nied_gif_observation.dart';
import 'nied_monitor.dart';

const _integerStride = 14;
const _doubleStride = 2;

/// Inference consumes current KA results, not the KA calculation history.
/// This transport preserves original dynamic values and map entry ordering.
/// Static catalogue fields are sent only on a catalogue revision.
class NiedSourceStationFrame {
  NiedSourceStationFrame._(
    this.catalogueVersion,
    this._catalogue,
    this._integers,
    this._doubles,
    this._reasons,
    this._observations,
    this._qualityFlags,
  );

  final int catalogueVersion;
  final List<_StationDefinition>? _catalogue;
  final Int64List _integers;
  final Float64List _doubles;
  final List<String> _reasons;
  final List<(int, NiedGifLayer, NiedGifObservation)> _observations;
  final List<(int, NiedGifLayer, Set<String>)> _qualityFlags;

  int get stationCount => _reasons.length;
  bool get includesCatalogue => _catalogue != null;
  int get numericBytes => _integers.lengthInBytes + _doubles.lengthInBytes;
}

class _StationDefinition {
  _StationDefinition(NiedStation station)
    : id = station.id,
      code = station.code,
      name = station.name,
      coordinate = station.coordinate,
      network = station.network,
      prefecture = station.prefecture,
      scanReliable = station.scanReliable,
      pixelClusterId = station.pixelClusterId;

  _StationDefinition.fromRaw(Map raw)
    : id = _rawInt(raw['id']) ?? 0,
      code = raw['code']?.toString() ?? '',
      name = raw['name']?.toString() ?? '',
      coordinate = _rawCoordinate(raw['coordinate']),
      network = raw['network']?.toString() ?? '',
      prefecture = raw['prefecture']?.toString() ?? '',
      scanReliable = raw['scanReliable'] != false,
      pixelClusterId = raw['pixelClusterId']?.toString();

  final int id;
  final String code, name, network, prefecture;
  final LatLng coordinate;
  final bool scanReliable;
  final String? pixelClusterId;

  bool matches(NiedStation station) =>
      id == station.id &&
      code == station.code &&
      name == station.name &&
      coordinate.latitude == station.coordinate.latitude &&
      coordinate.longitude == station.coordinate.longitude &&
      network == station.network &&
      prefecture == station.prefecture &&
      scanReliable == station.scanReliable &&
      pixelClusterId == station.pixelClusterId;

  bool matchesRaw(Map raw) {
    final coordinate = _rawCoordinate(raw['coordinate']);
    return id == (_rawInt(raw['id']) ?? 0) &&
        code == (raw['code']?.toString() ?? '') &&
        name == (raw['name']?.toString() ?? '') &&
        this.coordinate.latitude == coordinate.latitude &&
        this.coordinate.longitude == coordinate.longitude &&
        network == (raw['network']?.toString() ?? '') &&
        prefecture == (raw['prefecture']?.toString() ?? '') &&
        scanReliable == (raw['scanReliable'] != false) &&
        pixelClusterId == raw['pixelClusterId']?.toString();
  }

  NiedStation createStation() => NiedStation(
    id: id,
    code: code,
    name: name,
    coordinate: coordinate,
    network: network,
    prefecture: prefecture,
    scanReliable: scanReliable,
    pixelClusterId: pixelClusterId,
    expireSeconds: NiedStation.kaExpireSeconds,
  )..recentLevel = const <int>[];
}

class NiedSourceStationEncoder {
  List<_StationDefinition>? _catalogue;
  int _version = 0;

  void reset() => _catalogue = null;

  NiedSourceStationFrame captureRaw(dynamic raw) {
    final items = raw is List
        ? raw.whereType<Map>().where(_isValidRawStation).toList(growable: false)
        : const <Map>[];
    var changed = _catalogue == null || _catalogue!.length != items.length;
    if (!changed) {
      for (var index = 0; index < items.length; index++) {
        if (!_catalogue![index].matchesRaw(items[index])) {
          changed = true;
          break;
        }
      }
    }
    if (changed) {
      _catalogue = [for (final item in items) _StationDefinition.fromRaw(item)];
      _version++;
    }
    final integers = Int64List(items.length * _integerStride);
    final doubles = Float64List(items.length * _doubleStride);
    final reasons = List<String>.filled(items.length, '', growable: false);
    final observations = <(int, NiedGifLayer, NiedGifObservation)>[];
    final qualityFlags = <(int, NiedGifLayer, Set<String>)>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final offset = index * _integerStride;
      integers[offset] = _rawInt(item['level']) ?? -1;
      integers[offset + 1] = _rawInt(item['thresholdCode']) ?? 320;
      integers[offset + 2] = _rawInt(item['ascend']) ?? 0;
      integers[offset + 3] = _rawInt(item['triggerStamp']) ?? 0;
      integers[offset + 4] =
          _rawInt(item['expireSeconds']) ?? NiedStation.kaExpireSeconds;
      integers[offset + 5] =
          _rawInt(item['defaultExpireSeconds']) ?? integers[offset + 4];
      final abnormal = _rawInt(item['abnormalUpdateCount']);
      integers[offset + 6] = abnormal ?? 0;
      integers[offset + 7] = _rawInt(item['detectState']) ?? 0;
      integers[offset + 8] = _rawInt(item['pixelX']) ?? 0;
      integers[offset + 9] = _rawInt(item['pixelY']) ?? 0;
      var flags = item['isActive'] == true ? 1 : 0;
      if (abnormal != null) flags |= 2;
      flags = _writeRawTime(
        integers,
        offset + 10,
        flags,
        item['lastUpdate'],
        4,
      );
      flags = _writeRawTime(
        integers,
        offset + 11,
        flags,
        item['lastDataTime'],
        16,
      );
      flags = _writeRawTime(
        integers,
        offset + 12,
        flags,
        item['lastReceivedAt'],
        64,
      );
      integers[offset + 13] = flags;
      doubles[index * _doubleStride] =
          _rawDouble(item['calibrationFactor']) ?? 1.0;
      doubles[index * _doubleStride + 1] = _rawDouble(item['activity']) ?? 0.0;
      reasons[index] = item['detectReason']?.toString() ?? '';
      final rawObservations = item['gifObservations'];
      if (rawObservations is List) {
        for (final rawObservation in rawObservations.whereType<Map>()) {
          final observation = _rawObservation(rawObservation);
          if (observation != null) {
            observations.add((index, observation.$1, observation.$2));
          }
        }
      }
      final rawQuality = item['gifLayerQualityFlags'];
      if (rawQuality is Map) {
        for (final entry in rawQuality.entries) {
          final layer = _rawLayer(entry.key);
          final values = entry.value;
          if (layer != null && values is List) {
            qualityFlags.add((
              index,
              layer,
              values.map((value) => value.toString()).toSet(),
            ));
          }
        }
      }
    }
    return NiedSourceStationFrame._(
      _version,
      changed ? _catalogue : null,
      integers,
      doubles,
      reasons,
      observations,
      qualityFlags,
    );
  }

  NiedSourceStationFrame capture(
    List<NiedStation> stations, {
    bool includeCatalogue = false,
  }) {
    var changed = _catalogue == null || _catalogue!.length != stations.length;
    if (!changed) {
      for (var index = 0; index < stations.length; index++) {
        if (!_catalogue![index].matches(stations[index])) {
          changed = true;
          break;
        }
      }
    }
    if (changed) {
      _catalogue = [
        for (final station in stations) _StationDefinition(station),
      ];
      _version++;
    }
    final integers = Int64List(stations.length * _integerStride);
    final doubles = Float64List(stations.length * _doubleStride);
    final reasons = List<String>.filled(stations.length, '', growable: false);
    final observations = <(int, NiedGifLayer, NiedGifObservation)>[];
    final qualityFlags = <(int, NiedGifLayer, Set<String>)>[];
    for (var index = 0; index < stations.length; index++) {
      final station = stations[index];
      final offset = index * _integerStride;
      integers[offset] = station.level;
      integers[offset + 1] = station.thresholdCode;
      integers[offset + 2] = station.ascend;
      integers[offset + 3] = station.triggerStamp;
      integers[offset + 4] = station.expireSeconds;
      integers[offset + 5] = station.defaultExpireSeconds;
      integers[offset + 6] = station.abnormalUpdateCount ?? 0;
      integers[offset + 7] = station.detectState;
      integers[offset + 8] = station.pixelX;
      integers[offset + 9] = station.pixelY;
      var flags =
          (station.isActive ? 1 : 0) |
          (station.abnormalUpdateCount != null ? 2 : 0);
      flags = _writeTime(integers, offset + 10, flags, station.lastUpdate, 4);
      flags = _writeTime(
        integers,
        offset + 11,
        flags,
        station.lastDataTime,
        16,
      );
      flags = _writeTime(
        integers,
        offset + 12,
        flags,
        station.lastReceivedAt,
        64,
      );
      integers[offset + 13] = flags;
      doubles[index * _doubleStride] = station.calibrationFactor;
      doubles[index * _doubleStride + 1] = station.activity;
      reasons[index] = station.detectReason;
      for (final entry in station.gifObservations.entries) {
        observations.add((index, entry.key, entry.value));
      }
      for (final entry in station.gifLayerQualityFlags.entries) {
        qualityFlags.add((index, entry.key, Set.of(entry.value)));
      }
    }
    return NiedSourceStationFrame._(
      _version,
      changed || includeCatalogue ? _catalogue : null,
      integers,
      doubles,
      reasons,
      observations,
      qualityFlags,
    );
  }
}

/// Lives exclusively in the worker. Prior inference timers are cancelled before
/// replacing their frame's input, so they cannot mutate a subsequent frame.
class NiedSourceStationDecoder {
  List<NiedStation> _stations = const [];
  int? _version;

  List<NiedStation> apply(NiedSourceStationFrame frame) {
    if (frame._catalogue case final catalogue?) {
      dispose();
      _stations = [for (final entry in catalogue) entry.createStation()];
      _version = frame.catalogueVersion;
    }
    if (_version != frame.catalogueVersion ||
        _stations.length != frame.stationCount) {
      throw StateError('NIED inference catalogue/frame mismatch');
    }
    // Local DateTime construction consults the Windows time zone. A frame's
    // stations commonly share timestamps; construct each original instant and
    // UTC/local representation once. These caches never outlive this frame.
    final localTimes = <int, DateTime>{}, utcTimes = <int, DateTime>{};
    for (var index = 0; index < _stations.length; index++) {
      final station = _stations[index];
      station.terminate();
      station.activeTimer = null;
      final offset = index * _integerStride;
      final integers = frame._integers;
      final flags = integers[offset + 13];
      station.level = integers[offset];
      station.thresholdCode = integers[offset + 1];
      station.ascend = integers[offset + 2];
      station.triggerStamp = integers[offset + 3];
      station.expireSeconds = integers[offset + 4];
      station.defaultExpireSeconds = integers[offset + 5];
      station.abnormalUpdateCount = flags & 2 == 0
          ? null
          : integers[offset + 6];
      station.detectState = integers[offset + 7];
      station.pixelX = integers[offset + 8];
      station.pixelY = integers[offset + 9];
      station.isActive = flags & 1 != 0;
      station.lastUpdate = _readTime(
        integers,
        offset + 10,
        flags,
        4,
        localTimes,
        utcTimes,
      );
      station.lastDataTime = _readTime(
        integers,
        offset + 11,
        flags,
        16,
        localTimes,
        utcTimes,
      );
      station.lastReceivedAt = _readTime(
        integers,
        offset + 12,
        flags,
        64,
        localTimes,
        utcTimes,
      );
      station.calibrationFactor = frame._doubles[index * _doubleStride];
      station.activity = frame._doubles[index * _doubleStride + 1];
      station.detectReason = frame._reasons[index];
      station.gifObservations.clear();
      station.gifLayerQualityFlags.clear();
    }
    for (final (index, key, value) in frame._observations) {
      _stations[index].gifObservations[key] = value;
    }
    for (final (index, key, value) in frame._qualityFlags) {
      _stations[index].gifLayerQualityFlags[key] = value;
    }
    return _stations;
  }

  void dispose() {
    for (final station in _stations) {
      station.terminate();
    }
    _stations = const [];
    _version = null;
  }
}

int? _rawInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _rawDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

LatLng _rawCoordinate(dynamic value) {
  final map = value is Map ? value : const <dynamic, dynamic>{};
  return LatLng(_rawDouble(map['lat']) ?? 0, _rawDouble(map['lng']) ?? 0);
}

bool _isValidRawStation(Map raw) {
  final coordinate = raw['coordinate'];
  final map = coordinate is Map ? coordinate : const <dynamic, dynamic>{};
  final lat = _rawDouble(map['lat']);
  final lng = _rawDouble(map['lng']);
  return _rawInt(raw['id']) != null &&
      _rawInt(raw['expireSeconds']) != null &&
      lat != null &&
      lng != null &&
      lat.isFinite &&
      lng.isFinite;
}

int _writeRawTime(
  Int64List values,
  int slot,
  int flags,
  dynamic value,
  int bit,
) {
  final time = value is DateTime
      ? value
      : DateTime.tryParse(value?.toString() ?? '');
  if (time == null) return flags;
  values[slot] = time.microsecondsSinceEpoch;
  return flags | bit | (time.isUtc ? bit << 1 : 0);
}

(NiedGifLayer, NiedGifObservation)? _rawObservation(Map raw) {
  final layer = _rawLayer(raw['layer']);
  if (layer == null) return null;
  return (
    layer,
    NiedGifObservation(
      layer: layer,
      colorPosition: _rawDouble(raw['colorPosition']),
      shindo: _rawDouble(raw['shindo']),
      pga: _rawDouble(raw['pga']),
      pgv: _rawDouble(raw['pgv']),
      pgd: _rawDouble(raw['pgd']),
      velocityResponse: _rawDouble(raw['velocityResponse']),
    ),
  );
}

NiedGifLayer? _rawLayer(dynamic value) {
  final id = value?.toString();
  for (final layer in NiedGifLayer.values) {
    if (layer.id == id) return layer;
  }
  return null;
}

int _writeTime(Int64List values, int slot, int flags, DateTime? time, int bit) {
  if (time == null) {
    return flags;
  }
  values[slot] = time.microsecondsSinceEpoch;
  return flags | bit | (time.isUtc ? bit << 1 : 0);
}

DateTime? _readTime(
  Int64List values,
  int slot,
  int flags,
  int bit,
  Map<int, DateTime> localTimes,
  Map<int, DateTime> utcTimes,
) {
  if (flags & bit == 0) return null;
  final isUtc = flags & (bit << 1) != 0;
  final times = isUtc ? utcTimes : localTimes;
  final micros = values[slot];
  final cached = times[micros];
  if (cached != null) return cached;
  return times[micros] = DateTime.fromMicrosecondsSinceEpoch(
    micros,
    isUtc: isUtc,
  );
}
