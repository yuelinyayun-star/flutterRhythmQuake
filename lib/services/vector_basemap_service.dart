import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class VectorMapPolygon {
  const VectorMapPolygon(this.name, this.rings);
  final String name;
  final List<List<LatLng>> rings;
}

class VectorMapDataset {
  const VectorMapDataset(this.polygons, this.borders);
  final List<VectorMapPolygon> polygons;
  final List<List<LatLng>> borders;
}

/// Decode original topology without dropping holes, small islands, or unnamed
/// features. Only referenced shared arcs are drawn, once per dataset.
VectorMapDataset parseVectorBasemap(String source) {
  final data = jsonDecode(source) as Map<String, dynamic>;
  if (data['type'] != 'Topology') {
    throw const FormatException('Expected basemap Topology');
  }
  final transform = data['transform'] as Map?;
  final arcs = (data['arcs'] as List)
      .map((raw) {
        num x = 0, y = 0;
        return List<LatLng>.unmodifiable(
          (raw as List).map((pair) {
            if (transform == null) {
              return LatLng(
                (pair[1] as num).toDouble(),
                (pair[0] as num).toDouble(),
              );
            }
            x += pair[0] as num;
            y += pair[1] as num;
            return LatLng(
              (y * (transform['scale'][1] as num) +
                      (transform['translate'][1] as num))
                  .toDouble(),
              (x * (transform['scale'][0] as num) +
                      (transform['translate'][0] as num))
                  .toDouble(),
            );
          }),
        );
      })
      .toList(growable: false);
  final used = <int>{};
  List<LatLng> ring(List indices) {
    final points = <LatLng>[];
    for (final raw in indices) {
      final index = raw as int;
      final absolute = index < 0 ? ~index : index;
      used.add(absolute);
      final arc = arcs[absolute];
      if (points.isNotEmpty) points.removeLast();
      points.addAll(index < 0 ? arc.reversed : arc);
    }
    if (points.isEmpty) throw const FormatException('Empty basemap ring');
    while (points.length < 4) {
      points.add(points.first);
    }
    return List.unmodifiable(points);
  }

  final polygons = <VectorMapPolygon>[];
  void polygon(String name, List rings) {
    if (rings.isEmpty) {
      throw const FormatException('Missing basemap outer ring');
    }
    polygons.add(
      VectorMapPolygon(
        name,
        List.unmodifiable(rings.map((r) => ring(r as List))),
      ),
    );
  }

  void geometry(Map g) {
    final name = (g['properties'] as Map?)?['name']?.toString() ?? '';
    switch (g['type']) {
      case 'GeometryCollection':
        for (final child in g['geometries'] as List) {
          geometry(child as Map);
        }
      case 'Polygon':
        polygon(name, g['arcs'] as List);
      case 'MultiPolygon':
        for (final rings in g['arcs'] as List) {
          polygon(name, rings as List);
        }
      default:
        throw FormatException('Unsupported basemap geometry: ${g['type']}');
    }
  }

  geometry(data['objects']['region'] as Map);
  final indices = used.toList()..sort();
  return VectorMapDataset(
    List.unmodifiable(polygons),
    List.unmodifiable(indices.map((i) => arcs[i])),
  );
}

List<VectorMapDataset> _parseAll(List<String> sources) =>
    List.unmodifiable(sources.map(parseVectorBasemap));

class VectorBasemapService {
  VectorBasemapService({Future<String> Function(String)? loadAsset})
    : _loadAsset = loadAsset ?? rootBundle.loadString;

  // Preserve KA's composition: global, then Japan, then China on top.
  static const assetPaths = [
    'assets/maps/ka/medium.global.modified.topo.json',
    'assets/maps/ka/jp.pref.topo.json',
    'assets/maps/ka/cn.province.topo.json',
  ];
  static final instance = VectorBasemapService();
  final Future<String> Function(String) _loadAsset;
  Future<List<VectorMapDataset>>? _loading;

  Future<List<VectorMapDataset>> load() =>
      _loading ??= _load().catchError((Object error) {
        _loading = null;
        throw error;
      });

  Future<List<VectorMapDataset>> _load() async {
    final sources = await Future.wait(assetPaths.map(_loadAsset));
    return compute(_parseAll, sources);
  }
}
