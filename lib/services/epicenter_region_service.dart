import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Loads compact offline data used to turn epicenter coordinates into names.
class EpicenterRegionService {
  EpicenterRegionService._();

  static final EpicenterRegionService instance = EpicenterRegionService._();

  static const _chinaAsset = 'assets/regions/china_place_index.bin';
  static const _chinaAdminAsset = 'assets/regions/china_admin_regions.bin';
  static const _cwaAsset = 'assets/regions/cwa_epicenter_regions.bin';
  static const _japanLandAsset = 'assets/regions/japan_land_regions.bin';

  EpicenterRegionResolver? _resolver;
  Future<void>? _loading;

  bool get isLoaded => _resolver != null;

  Future<void> load({AssetBundle? bundle}) {
    if (_resolver != null) return Future.value();
    return _loading ??= _load(bundle ?? rootBundle);
  }

  Future<void> _load(AssetBundle bundle) async {
    try {
      final china = await bundle.load(_chinaAsset);
      final chinaAdmin = await bundle.load(_chinaAdminAsset);
      final cwa = await bundle.load(_cwaAsset);
      final japanLand = await bundle.load(_japanLandAsset);
      _resolver = EpicenterRegionResolver.fromByteData(
        china: china,
        chinaAdmin: chinaAdmin,
        cwa: cwa,
        japanLand: japanLand,
      );
      debugPrint('Epicenter regions loaded: China/CWA/Japan land mask');
    } catch (error, stackTrace) {
      debugPrint('Epicenter region data load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _loading = null;
    }
  }

  /// Returns a bare region name. Formatting such as "附近" belongs to callers.
  String? lookup(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite) return null;
    if (latitude < -90 || latitude > 90) return null;
    if (longitude < -180 || longitude > 180) return null;
    return _resolver?.lookup(latitude, longitude);
  }

  /// China-only lookup that prefers county/district detail when available.
  String? lookupChinaPlace(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite) return null;
    if (latitude < -90 || latitude > 90) return null;
    if (longitude < -180 || longitude > 180) return null;
    return _resolver?.lookupChinaPlace(latitude, longitude);
  }

  @visibleForTesting
  void setResolverForTesting(EpicenterRegionResolver? resolver) {
    _resolver = resolver;
    _loading = null;
  }
}

/// Pure binary resolver kept separate from Flutter asset loading for testing.
class EpicenterRegionResolver {
  EpicenterRegionResolver._({
    required _ChinaGrid china,
    required _PolygonRegions chinaAdmin,
    required _PolygonRegions cwa,
    required _PolygonRegions japanLand,
  }) : _china = china,
       _chinaAdmin = chinaAdmin,
       _cwa = cwa,
       _japanLand = japanLand;

  factory EpicenterRegionResolver.fromByteData({
    required ByteData china,
    required ByteData chinaAdmin,
    required ByteData cwa,
    required ByteData japanLand,
  }) {
    return EpicenterRegionResolver._(
      china: _ChinaGrid(china),
      chinaAdmin: _PolygonRegions(chinaAdmin),
      cwa: _PolygonRegions(cwa),
      japanLand: _PolygonRegions(japanLand),
    );
  }

  final _ChinaGrid _china;
  final _PolygonRegions _chinaAdmin;
  final _PolygonRegions _cwa;
  final _PolygonRegions _japanLand;

  /// Only polygon-backed regional data may override the global FE fallback.
  String? lookup(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite) return null;
    if (latitude < -90 || latitude > 90) return null;
    if (longitude < -180 || longitude > 180) return null;
    final chinaAdmin = _chinaAdmin.lookup(latitude, longitude);
    if (chinaAdmin != null) return chinaAdmin;

    final chinaGrid = _china.lookup(latitude, longitude);
    if (chinaGrid != null) return chinaGrid;

    // CWA sea polygons overlap a few Japanese islands. Keep Japanese land on
    // the FE grid while still using CWA town/nearshore/sea polygons elsewhere.
    if (_japanLand.lookup(latitude, longitude) != null) return null;
    return _cwa.lookup(latitude, longitude);
  }

  /// China lookup that prefers the most specific place name available.
  ///
  /// Admin polygons are authoritative when they include county/district detail,
  /// but some prefecture polygons only resolve to the parent city. In those
  /// cases the coarse China place grid can still provide county-level names.
  @visibleForTesting
  String? lookupChinaPlace(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite) return null;
    if (latitude < -90 || latitude > 90) return null;
    if (longitude < -180 || longitude > 180) return null;

    final admin = _chinaAdmin.lookup(latitude, longitude);
    final grid = _china.lookup(latitude, longitude);
    if (admin == null || admin.isEmpty) return grid;
    if (grid == null || grid.isEmpty) return admin;
    if (admin == grid) return admin;

    final adminHasCounty = _hasCountySuffix(admin);
    final gridHasCounty = _hasCountySuffix(grid);
    if (!adminHasCounty && gridHasCounty) return grid;
    if (adminHasCounty && !gridHasCounty) return admin;
    return admin.length >= grid.length ? admin : grid;
  }

  static bool _hasCountySuffix(String area) {
    final normalized = area.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return false;
    if (RegExp(r'(?:区|县|旗|自治县|林区)(?!$)').hasMatch(normalized)) {
      return true;
    }
    return '\u5e02'.allMatches(normalized).length >= 2;
  }
}

class _ChinaGrid {
  _ChinaGrid(this._data) {
    _expectMagic(_data, 'CPR1');
    _expectVersion(_data);
    _latMin = _data.getFloat64(8, Endian.little);
    _lonMin = _data.getFloat64(16, Endian.little);
    _latStep = _data.getFloat64(24, Endian.little);
    _lonStep = _data.getFloat64(32, Endian.little);
    _rows = _data.getUint32(40, Endian.little);
    _cols = _data.getUint32(44, Endian.little);
    final nameCount = _data.getUint32(48, Endian.little);
    final stringOffset = _data.getUint32(52, Endian.little);
    _gridOffset = _data.getUint32(56, Endian.little);
    final tableLength = _data.getUint32(60, Endian.little);
    _missingRegion = _data.getUint32(64, Endian.little);
    if (_rows * _cols != tableLength ||
        _gridOffset + tableLength * 2 > _data.lengthInBytes) {
      throw const FormatException('Invalid China region grid');
    }
    _names = _readStrings(_data, stringOffset, nameCount);
  }

  final ByteData _data;
  late final double _latMin;
  late final double _lonMin;
  late final double _latStep;
  late final double _lonStep;
  late final int _rows;
  late final int _cols;
  late final int _gridOffset;
  late final int _missingRegion;
  late final List<String> _names;

  String? lookup(double latitude, double longitude) {
    final row = ((latitude - _latMin) / _latStep).floor();
    final col = ((longitude - _lonMin) / _lonStep).floor();
    if (row < 0 || row >= _rows || col < 0 || col >= _cols) return null;
    final index = row * _cols + col;
    final region = _data.getUint16(_gridOffset + index * 2, Endian.little);
    if (region == _missingRegion || region >= _names.length) return null;
    final name = _names[region];
    return name.isEmpty ? null : name;
  }
}

class _PolygonRegions {
  _PolygonRegions(this._data) {
    _expectMagic(_data, 'CWR1');
    _expectVersion(_data);
    _featureCount = _data.getUint32(8, Endian.little);
    _polygonCount = _data.getUint32(12, Endian.little);
    _ringCount = _data.getUint32(16, Endian.little);
    _pointCount = _data.getUint32(20, Endian.little);
    final nameCount = _data.getUint32(24, Endian.little);
    final stringOffset = _data.getUint32(28, Endian.little);
    _featureOffset = _data.getUint32(32, Endian.little);
    _polygonOffset = _data.getUint32(36, Endian.little);
    _ringOffset = _data.getUint32(40, Endian.little);
    _pointOffset = _data.getUint32(44, Endian.little);
    _featureSize = _data.getUint32(48, Endian.little);
    _polygonSize = _data.getUint32(52, Endian.little);
    _ringSize = _data.getUint32(56, Endian.little);
    if (_featureSize < 32 || _polygonSize < 8 || _ringSize < 8) {
      throw const FormatException('Invalid polygon region record sizes');
    }
    if (_featureOffset + _featureCount * _featureSize > _data.lengthInBytes ||
        _polygonOffset + _polygonCount * _polygonSize > _data.lengthInBytes ||
        _ringOffset + _ringCount * _ringSize > _data.lengthInBytes ||
        _pointOffset + _pointCount * 8 > _data.lengthInBytes) {
      throw const FormatException('Invalid polygon region offsets');
    }
    _names = _readStrings(_data, stringOffset, nameCount);
  }

  final ByteData _data;
  late final int _featureCount;
  late final int _polygonCount;
  late final int _ringCount;
  late final int _pointCount;
  late final int _featureOffset;
  late final int _polygonOffset;
  late final int _ringOffset;
  late final int _pointOffset;
  late final int _featureSize;
  late final int _polygonSize;
  late final int _ringSize;
  late final List<String> _names;

  String? lookup(double latitude, double longitude) {
    String? bestName;
    var bestArea = double.infinity;
    var bestOrder = 0x7fffffff;
    for (var index = 0; index < _featureCount; index++) {
      final offset = _featureOffset + index * _featureSize;
      final latMin = _data.getFloat32(offset, Endian.little);
      final latMax = _data.getFloat32(offset + 4, Endian.little);
      final lonMin = _data.getFloat32(offset + 8, Endian.little);
      final lonMax = _data.getFloat32(offset + 12, Endian.little);
      if (latitude < latMin ||
          latitude > latMax ||
          longitude < lonMin ||
          longitude > lonMax) {
        continue;
      }
      final nameIndex = _data.getUint32(offset + 16, Endian.little);
      final polygonStart = _data.getUint32(offset + 20, Endian.little);
      final polygonLength = _data.getUint32(offset + 24, Endian.little);
      final order = _data.getUint32(offset + 28, Endian.little);
      if (nameIndex >= _names.length ||
          polygonStart + polygonLength > _polygonCount ||
          !_containsFeature(latitude, longitude, polygonStart, polygonLength)) {
        continue;
      }
      final area = (latMax - latMin) * (lonMax - lonMin);
      if (area < bestArea || (area == bestArea && order < bestOrder)) {
        bestArea = area;
        bestOrder = order;
        bestName = _names[nameIndex];
      }
    }
    return bestName == null || bestName.isEmpty ? null : bestName;
  }

  bool _containsFeature(
    double latitude,
    double longitude,
    int polygonStart,
    int polygonLength,
  ) {
    for (
      var index = polygonStart;
      index < polygonStart + polygonLength;
      index++
    ) {
      final polygon = _polygonOffset + index * _polygonSize;
      final ringStart = _data.getUint32(polygon, Endian.little);
      final ringLength = _data.getUint32(polygon + 4, Endian.little);
      if (ringLength == 0 || ringStart + ringLength > _ringCount) continue;
      if (!_containsRing(latitude, longitude, ringStart)) continue;
      var insideHole = false;
      for (var hole = 1; hole < ringLength; hole++) {
        if (_containsRing(latitude, longitude, ringStart + hole)) {
          insideHole = true;
          break;
        }
      }
      if (!insideHole) return true;
    }
    return false;
  }

  bool _containsRing(double latitude, double longitude, int ringIndex) {
    final ring = _ringOffset + ringIndex * _ringSize;
    final pointStart = _data.getUint32(ring, Endian.little);
    final pointLength = _data.getUint32(ring + 4, Endian.little);
    if (pointLength < 3 || pointStart + pointLength > _pointCount) return false;

    var inside = false;
    var previous = pointLength - 1;
    for (var current = 0; current < pointLength; current++) {
      final currentPoint = _pointOffset + (pointStart + current) * 8;
      final previousPoint = _pointOffset + (pointStart + previous) * 8;
      final currentLon = _data.getFloat32(currentPoint, Endian.little);
      final currentLat = _data.getFloat32(currentPoint + 4, Endian.little);
      final previousLon = _data.getFloat32(previousPoint, Endian.little);
      final previousLat = _data.getFloat32(previousPoint + 4, Endian.little);

      if (_isOnSegment(
        longitude,
        latitude,
        previousLon,
        previousLat,
        currentLon,
        currentLat,
      )) {
        return true;
      }
      final crosses = (currentLat > latitude) != (previousLat > latitude);
      if (crosses) {
        final intersection =
            (previousLon - currentLon) *
                (latitude - currentLat) /
                (previousLat - currentLat) +
            currentLon;
        if (longitude < intersection) inside = !inside;
      }
      previous = current;
    }
    return inside;
  }
}

List<String> _readStrings(ByteData data, int offset, int count) {
  final offsetTableBytes = (count + 1) * 4;
  if (offset < 0 || offset + offsetTableBytes > data.lengthInBytes) {
    throw const FormatException('Invalid string table offset');
  }
  final bytesStart = offset + offsetTableBytes;
  final endOffset = data.getUint32(offset + count * 4, Endian.little);
  if (bytesStart + endOffset > data.lengthInBytes) {
    throw const FormatException('Invalid string table length');
  }
  final source = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final names = <String>[];
  for (var index = 0; index < count; index++) {
    final start = data.getUint32(offset + index * 4, Endian.little);
    final end = data.getUint32(offset + (index + 1) * 4, Endian.little);
    if (start > end || end > endOffset) {
      throw const FormatException('Invalid string table entry');
    }
    names.add(
      utf8.decode(source.sublist(bytesStart + start, bytesStart + end)),
    );
  }
  return List.unmodifiable(names);
}

void _expectMagic(ByteData data, String expected) {
  if (data.lengthInBytes < 8) throw const FormatException('Asset is too short');
  final source = data.buffer.asUint8List(data.offsetInBytes, 4);
  if (ascii.decode(source) != expected) {
    throw FormatException('Unexpected region asset magic, expected $expected');
  }
}

void _expectVersion(ByteData data) {
  if (data.getUint32(4, Endian.little) != 1) {
    throw const FormatException('Unsupported region asset version');
  }
}

bool _isOnSegment(
  double x,
  double y,
  double x1,
  double y1,
  double x2,
  double y2,
) {
  const epsilon = 1e-6;
  final cross = (x - x1) * (y2 - y1) - (y - y1) * (x2 - x1);
  if (cross.abs() > epsilon) return false;
  return x >= (x1 < x2 ? x1 : x2) - epsilon &&
      x <= (x1 > x2 ? x1 : x2) + epsilon &&
      y >= (y1 < y2 ? y1 : y2) - epsilon &&
      y <= (y1 > y2 ? y1 : y2) + epsilon;
}
