import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class ChinaFaultLine {
  const ChinaFaultLine({
    required this.name,
    required this.age,
    required this.points,
  });
  final String name;
  final String age;
  final List<LatLng> points;
}

/// Decode the original KA TopoJSON without modifying or simplifying source data.
List<ChinaFaultLine> parseChinaFaults(String source) {
  final data = jsonDecode(source) as Map<String, dynamic>;
  if (data['type'] != 'Topology') {
    throw const FormatException('Expected Topology');
  }
  final transform = data['transform'] as Map?;
  final arcs = (data['arcs'] as List)
      .map((raw) {
        num x = 0, y = 0;
        return (raw as List)
            .map((item) {
              if (transform == null) {
                return LatLng(
                  (item[1] as num).toDouble(),
                  (item[0] as num).toDouble(),
                );
              }
              x += item[0] as num;
              y += item[1] as num;
              return LatLng(
                (y * (transform['scale'][1] as num) +
                        (transform['translate'][1] as num))
                    .toDouble(),
                (x * (transform['scale'][0] as num) +
                        (transform['translate'][0] as num))
                    .toDouble(),
              );
            })
            .toList(growable: false);
      })
      .toList(growable: false);
  final result = <ChinaFaultLine>[];
  void line(List indices, Map properties) {
    final points = <LatLng>[];
    for (final raw in indices) {
      final index = raw as int;
      // TopoJSON reversals use one's complement, not absolute value.
      final arc = arcs[index < 0 ? ~index : index];
      final ordered = index < 0 ? arc.reversed : arc;
      if (points.isNotEmpty) points.removeLast();
      points.addAll(ordered);
    }
    if (points.length < 2) return;
    result.add(
      ChinaFaultLine(
        name: properties['name']?.toString() ?? '',
        age: properties['age']?.toString() ?? '',
        points: List.unmodifiable(points),
      ),
    );
  }

  void geometry(Map value) {
    final properties = value['properties'] as Map? ?? const {};
    switch (value['type']) {
      case null:
        break;
      case 'GeometryCollection':
        for (final child in value['geometries'] as List) {
          geometry(child as Map);
        }
      case 'LineString':
        line(value['arcs'] as List, properties);
      case 'MultiLineString':
        for (final indices in value['arcs'] as List) {
          line(indices as List, properties);
        }
      default:
        throw FormatException('Unsupported fault geometry: ${value['type']}');
    }
  }

  geometry(data['objects']['region'] as Map);
  return List.unmodifiable(result);
}

class ChinaFaultService {
  ChinaFaultService({Future<String> Function()? loadAsset})
    : _loadAsset = loadAsset ?? (() => rootBundle.loadString(assetPath));

  static const assetPath = 'assets/maps/cn.fault.topo.json';
  static final instance = ChinaFaultService();
  final Future<String> Function() _loadAsset;
  Future<List<ChinaFaultLine>>? _loading;

  Future<List<ChinaFaultLine>> load() =>
      _loading ??= _load().catchError((Object error) {
        _loading = null;
        throw error;
      });

  Future<List<ChinaFaultLine>> _load() async =>
      compute(parseChinaFaults, await _loadAsset());
}
