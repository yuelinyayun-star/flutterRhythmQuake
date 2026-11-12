import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../cwa_intensity_prediction.dart';

class TopoJsonRegion {
  final String name;
  final String code;
  final List<List<LatLng>> polygons;
  final List<List<LatLng>> lines;
  LatLng? center;

  TopoJsonRegion({
    required this.name,
    this.code = '',
    required this.polygons,
    this.lines = const [],
    this.center,
  });

  void calculateCenter() {
    final allPoints = [...polygons.expand((p) => p), ...lines.expand((l) => l)];
    if (allPoints.isEmpty) return;
    double sumLat = 0, sumLng = 0;
    for (final point in allPoints) {
      sumLat += point.latitude;
      sumLng += point.longitude;
    }
    center = LatLng(sumLat / allPoints.length, sumLng / allPoints.length);
  }
}

class TopoJsonData {
  final String source;
  final List<TopoJsonRegion> regions;
  final Map<String, TopoJsonRegion> regionMap;

  TopoJsonData({required this.source, required this.regions})
    : regionMap = {for (var r in regions) r.name: r};

  TopoJsonRegion? getRegion(String name) => regionMap[name];

  Map<String, (double, double)> getCenters() {
    return {
      for (var r in regions)
        if (r.center != null) r.name: (r.center!.latitude, r.center!.longitude),
    };
  }
}

class TopoJsonLoader {
  static TopoJsonData? _cnData;
  static TopoJsonData? _jpData;
  static TopoJsonData? _krData;
  static TopoJsonData? _twData;
  static TopoJsonData? _jpTsunamiData;
  static final _loading = <String, Future<TopoJsonData?>>{};

  static TopoJsonData? get cnData => _cnData;
  static TopoJsonData? get jpData => _jpData;
  static TopoJsonData? get krData => _krData;
  static TopoJsonData? get twData => _twData;

  static Future<void> loadAll() async {
    await Future.wait([loadCnEew(), loadJpEew(), loadKrEew()]);
  }

  static Future<TopoJsonData?> loadCnEew() => _loadCached(
    'cn',
    'assets/maps/cn.eew.topo.json',
    _cnData,
    (data) => _cnData = data,
  );

  static Future<TopoJsonData?> loadJpEew() => _loadCached(
    'jp',
    'assets/maps/jp.eew.topo.json',
    _jpData,
    (data) => _jpData = data,
  );

  static Future<TopoJsonData?> loadKrEew() => _loadCached(
    'kr',
    'assets/maps/kr.eew.topo.json',
    _krData,
    (data) => _krData = data,
  );

  static Future<TopoJsonData?> loadTwEew() async {
    if (_twData != null) return _twData;
    final data = await loadCnEew();
    if (data == null) return null;
    return _twData ??= TopoJsonData(
      source: 'tw',
      regions: data.regions
          .where(
            (region) => CwaIntensityPrediction.counties.contains(
              CwaIntensityPrediction.canonicalCounty(region.name),
            ),
          )
          .toList(growable: false),
    );
  }

  static Future<TopoJsonData?> loadJpTsunami() => _loadCached(
    'jp_tsunami',
    'assets/maps/jp.tsunami.topo.json',
    _jpTsunamiData,
    (data) => _jpTsunamiData = data,
  );

  static Future<TopoJsonData?> _loadCached(
    String source,
    String asset,
    TopoJsonData? cached,
    void Function(TopoJsonData) save,
  ) {
    if (cached != null) return Future.value(cached);
    return _loading.putIfAbsent(
      source,
      () => _readAsset(
        source,
        asset,
        save,
      ).whenComplete(() {
        _loading.remove(source);
      }),
    );
  }

  static Future<TopoJsonData?> _readAsset(
    String source,
    String asset,
    void Function(TopoJsonData) save,
  ) async {
    try {
      final jsonStr = await rootBundle.loadString(asset, cache: false);
      final data = parse(jsonStr, source: source);
      if (data != null) save(data);
      return data;
    } catch (e) {
      print('TopoJSON $source 加载失败: $e');
      return null;
    }
  }

  static TopoJsonData? parse(String jsonStr, {required String source}) {
    try {
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      return _parseTopoJson(data, source);
    } catch (e) {
      print('TopoJSON 解析错误: $e');
      return null;
    }
  }

  static TopoJsonData _parseTopoJson(Map<String, dynamic> data, String source) {
    final rawArcs = data['arcs'] as List;

    final transform = data['transform'] as Map<String, dynamic>?;
    final scale = (transform?['scale'] as List?) ?? [1.0, 1.0];
    final translate = (transform?['translate'] as List?) ?? [0.0, 0.0];
    final scaleX = scale[0].toDouble();
    final scaleY = scale[1].toDouble();
    final translateX = translate[0].toDouble();
    final translateY = translate[1].toDouble();

    final absoluteArcs = _decodeArcsToAbsolute(
      rawArcs,
      scaleX,
      scaleY,
      translateX,
      translateY,
    );

    final regions = <TopoJsonRegion>[];
    final objects = data['objects'] as Map<String, dynamic>;

    for (final objEntry in objects.entries) {
      final obj = objEntry.value as Map<String, dynamic>;
      final geometries = obj['geometries'] as List;

      for (final geom in geometries) {
        final props = geom['properties'] as Map<String, dynamic>?;
        final name = props?['name'] as String? ?? '';
        final type = geom['type'] as String;

        List<List<LatLng>> polygons = [];
        List<List<LatLng>> lines = [];

        if (type == 'Polygon') {
          final rings = geom['arcs'] as List;
          for (final ring in rings) {
            final points = _stitchArcRefs(ring as List, absoluteArcs);
            if (points.length >= 3) polygons.add(points);
          }
        } else if (type == 'MultiPolygon') {
          final polygonList = geom['arcs'] as List;
          for (final polygon in polygonList) {
            final rings = polygon as List;
            for (final ring in rings) {
              final points = _stitchArcRefs(ring as List, absoluteArcs);
              if (points.length >= 3) polygons.add(points);
            }
          }
        } else if (type == 'LineString') {
          final points = _stitchArcRefs(geom['arcs'] as List, absoluteArcs);
          if (points.length >= 2) lines.add(points);
        } else if (type == 'MultiLineString') {
          final arcList = geom['arcs'] as List;
          for (final arcRef in arcList) {
            final points = _stitchArcRefs(arcRef as List, absoluteArcs);
            if (points.length >= 2) lines.add(points);
          }
        } else {
          continue;
        }

        final code = props?['code']?.toString() ?? '';
        final region = TopoJsonRegion(
          name: name,
          code: code,
          polygons: polygons,
          lines: lines,
        );
        region.calculateCenter();
        regions.add(region);
      }
    }

    return TopoJsonData(source: source, regions: regions);
  }

  static List<List<LatLng>> _decodeArcsToAbsolute(
    List rawArcs,
    double scaleX,
    double scaleY,
    double translateX,
    double translateY,
  ) {
    final result = <List<LatLng>>[];

    for (final rawArc in rawArcs) {
      final arc = rawArc as List;
      final points = <LatLng>[];
      double x = translateX;
      double y = translateY;

      for (final point in arc) {
        final p = point as List;
        x += p[0].toDouble() * scaleX;
        y += p[1].toDouble() * scaleY;
        points.add(LatLng(y, x));
      }

      result.add(points);
    }

    return result;
  }

  static List<LatLng> _stitchArcRefs(
    List arcRefs,
    List<List<LatLng>> absoluteArcs,
  ) {
    final points = <LatLng>[];

    for (final arcRef in arcRefs) {
      final ref = arcRef as int;
      final arcIndex = ref >= 0 ? ref : -ref - 1;
      final arc = absoluteArcs[arcIndex];

      if (ref >= 0) {
        for (int i = 0; i < arc.length; i++) {
          points.add(arc[i]);
        }
      } else {
        for (int i = arc.length - 1; i >= 0; i--) {
          points.add(arc[i]);
        }
      }
    }

    return points;
  }

  static void clearCache() {
    _cnData = null;
    _jpData = null;
    _krData = null;
    _twData = null;
    _jpTsunamiData = null;
  }
}
