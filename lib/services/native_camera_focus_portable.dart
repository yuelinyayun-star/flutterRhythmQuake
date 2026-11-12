import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

/// Compatibility for platforms without the Windows Rust library. Production
/// Windows dispatch is in native_camera_focus_io.dart and never falls back.
abstract final class NativeCameraFocus {
  static bool get supported => false;
  static int get calls => 0;
  static int get outputs => 0;
  static Map<String, dynamic> prepareGeometry(Float64List coordinates) {
    if (coordinates.length.isOdd || coordinates.length ~/ 2 > 2000000) {
      throw ArgumentError('Invalid camera geometry pair count');
    }
    final indices = <int>[], longitudes = <double>[];
    var south = double.infinity, north = double.negativeInfinity;
    for (var i = 0; i < coordinates.length; i += 2) {
      final lat = coordinates[i], lng = coordinates[i + 1];
      if (!lat.isFinite || lat.abs() > 90 || !lng.isFinite) continue;
      indices.add(i ~/ 2);
      if (lat < south) south = lat;
      if (lat > north) north = lat;
      var positive = lng.remainder(360);
      if (positive < 0) positive += 360;
      longitudes.add(positive);
    }
    if (indices.isEmpty) return {'indices': <int>[], 'view': null};
    longitudes.sort();
    var largestGap = -1.0, largestIndex = 0;
    for (var i = 0; i < longitudes.length; i++) {
      final next = i == longitudes.length - 1
          ? longitudes.first + 360
          : longitudes[i + 1];
      final gap = next - longitudes[i];
      if (gap > largestGap) {
        largestGap = gap;
        largestIndex = i;
      }
    }
    final startIndex = (largestIndex + 1) % longitudes.length;
    final start = longitudes[startIndex];
    final end = longitudes[largestIndex] + (startIndex == 0 ? 0 : 360);
    return {
      'indices': indices,
      'view': {
        'latitude': (south + north) / 2,
        'longitude': (start + end) / 2,
        'latDiff': north - south,
        'lngDiff': end - start,
      },
    };
  }

  static dynamic prepare(Map<String, dynamic> v) {
    List<List<double>> boundsOf(Iterable<dynamic> points) {
      var south = double.infinity, north = double.negativeInfinity;
      var west = double.infinity, east = double.negativeInfinity;
      for (final point in points) {
        final lat = (point[0] as num).toDouble(),
            lng = (point[1] as num).toDouble();
        if (!lat.isFinite || !lng.isFinite) {
          throw ArgumentError('Invalid rendered coordinate');
        }
        south = math.min(south, lat);
        north = math.max(north, lat);
        west = math.min(west, lng);
        east = math.max(east, lng);
      }
      return south.isFinite
          ? [
              [south, west],
              [south, east],
              [north, west],
              [north, east],
            ]
          : [];
    }

    switch (v['op']) {
      case 'eventCameraTarget':
        final diff =
            math.max(v['latDiff'] as num, v['lngDiff'] as num) +
            (v['padding'] as num) * 2;
        final coarse = diff > 20
            ? 3.0
            : diff > 10
            ? 4.0
            : diff > 5
            ? 5.0
            : diff > 2
            ? 6.0
            : diff > 1
            ? 7.0
            : 8.0;
        return {
          'latitude': v['latitude'],
          'longitude': v['longitude'],
          'zoom':
              v['fittedZoom'] ??
              coarse.clamp(v['minZoom'] as num, v['maxZoom'] as num),
        };
      case 'renderedRegionBounds':
        final result = <String, List<List<double>>>{};
        for (final region in v['regions'] as List) {
          final name = region['name'] as String;
          result[name] = boundsOf([
            ...?result[name],
            ...region['points'] as List,
          ]);
        }
        return result;
      case 'informationFillBounds':
        if (v['isEew'] == true) return [];
        final names = <String>{};
        if (v['namedRegions'] == true) {
          final text = v['warnArea'] as String;
          if (text.isNotEmpty) {
            final rows = jsonDecode(text);
            if (rows is List) {
              for (final row in rows) {
                if (row is Map && row['name'] is String) {
                  names.add(row['name'] as String);
                }
              }
            }
          }
        }
        final all =
            v['namedRegions'] != true ||
            (names.isEmpty && v['representative'] == true);
        return boundsOf(
          (v['regions'] as Map).entries
              .where((e) => all || names.contains(e.key))
              .expand((e) => e.value as List),
        );
      case 'informationAnchor':
        final p2p =
            v['source'] == 'p2pJmaEqlist' ||
            (v['source'] == 'jmaEqlist' && v['origin'] == 2);
        final special =
            const ['ScalePrompt', 'Destination'].contains(v['issueType']) ||
            ((v['issueType'] == null || v['issueType'] == '') &&
                const ['震度速報', '震源に関する情報'].contains(v['title']));
        return v['locatable'] == true &&
            v['isEew'] != true &&
            (v['source'] == 'nowQuakeCencIr' ||
                (p2p && !special) ||
                (v['hasInformationFill'] == true && !special));
      case 'groupAnchor':
        return v['hasProduct'] == true || v['stationFit'] == true;
      case 'retainInformationGroup':
        return v['sameViewport'] == true &&
            v['hasPreviousMember'] == true &&
            v['allVisible'] == true;
      case 'fitAnchor':
        final width = (v['width'] as num).toDouble();
        final height = (v['height'] as num).toDouble();
        if (width <= 0 || height <= 0) return null;
        final angle = (v['rotation'] as num).toDouble();
        final cos = math.cos(angle), sin = math.sin(angle);
        var halfWidth = 0.0, halfHeight = 0.0;
        for (final pair in v['offsets'] as List) {
          final x = (pair[0] as num).toDouble(),
              y = (pair[1] as num).toDouble();
          halfWidth = math.max(halfWidth, (x * cos + y * sin).abs());
          halfHeight = math.max(halfHeight, (-x * sin + y * cos).abs());
        }
        final scale = math.min(
          halfWidth == 0 ? double.infinity : width / (2 * halfWidth),
          halfHeight == 0 ? double.infinity : height / (2 * halfHeight),
        );
        final zoom =
            (scale.isFinite
                    ? math.log((v['currentScale'] as num) * scale / 256) /
                          math.ln2
                    : (v['maxZoom'] as num).toDouble())
                .clamp(v['minZoom'] as num, v['maxZoom'] as num)
                .toDouble();
        final px = v['paddingX'] as num, py = v['paddingY'] as num;
        return {
          'zoom': zoom,
          'offsetX': px * cos - py * sin,
          'offsetY': px * sin + py * cos,
        };
      default:
        throw ArgumentError('Unknown camera focus operation');
    }
  }
}
