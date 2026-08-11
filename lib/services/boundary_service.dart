import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

/// 标签级别枚举
/// 
/// 用于区分省市标签的显示级别
enum LabelLevel { province, city }

/// 城市标签类
/// 
/// 存储城市/省份名称和坐标信息
class CityLabel {
  /// 城市/省份名称
  final String name;
  
  /// 坐标位置
  final LatLng coord;
  
  /// 标签级别
  final LabelLevel level;
  
  CityLabel({required this.name, required this.coord, this.level = LabelLevel.city});
}

/// 边界图层类
/// 
/// 存储单个边界图层的配置和几何数据
/// 支持GeoJSON和TopoJSON两种格式
class BoundaryLayer {
  /// 图层名称
  final String name;
  
  /// 资源文件路径
  final String assetPath;
  
  /// TopoJSON对象键名
  final String objectKey;
  
  /// 边框颜色
  final Color borderColor;
  
  /// 填充颜色（可选）
  final Color? fillColor;
  
  /// 边框宽度
  final double borderWidth;
  
  /// 最小显示缩放级别
  final double minZoom;
  
  /// 最大显示缩放级别
  final double maxZoom;
  
  /// 是否为GeoJSON格式
  final bool isGeoJson;

  /// 解析后的多边形列表
  List<Polygon> polygons = [];
  
  /// 解析后的折线列表
  List<Polyline> polylines = [];

  BoundaryLayer({
    required this.name,
    required this.assetPath,
    this.objectKey = '',
    this.borderColor = const Color(0xFFFFFFFF),
    this.fillColor,
    this.borderWidth = 1.0,
    this.minZoom = 3.0,
    this.maxZoom = 18.0,
    this.isGeoJson = false,
  });

  /// 判断在指定缩放级别是否可见
  bool isVisibleAt(double zoom) => zoom >= minZoom && zoom <= maxZoom;
}

/// 边界服务
/// 
/// 该类提供地图边界数据的加载和解析功能。
/// 支持GeoJSON和TopoJSON两种格式。
/// 
/// 主要功能：
/// - 加载全球/国家/省份边界数据
/// - 加载断层线数据
/// - 解析GeoJSON格式
/// - 解析TopoJSON格式
/// - 提供城市标签数据
/// 
/// 支持的图层：
/// - 全球国界
/// - 日本都道府县
/// - 中国省界
/// - 中国断层线
class BoundaryService {
  static final BoundaryService _instance = BoundaryService._internal();
  factory BoundaryService() => _instance;
  BoundaryService._internal();

  /// 已加载的图层列表
  final List<BoundaryLayer> _layers = [];
  
  /// 城市标签列表
  final List<CityLabel> _cityLabels = [];
  
  /// 是否已加载
  bool _isLoaded = false;
  
  /// 是否正在加载
  bool _isLoading = false;
  Future<void>? _loading;

  List<BoundaryLayer> get layers => _layers;
  List<CityLabel> get cityLabels => _cityLabels;
  bool get isLoaded => _isLoaded;

  /// 默认省份标签
  /// 
  /// 包含中国34个省级行政区及周边国家/地区
  static final List<CityLabel> _defaultProvinceLabels = [
    CityLabel(name: "北京", coord: LatLng(39.93, 116.40), level: LabelLevel.province),
    CityLabel(name: "天津", coord: LatLng(39.14, 117.21), level: LabelLevel.province),
    CityLabel(name: "河北", coord: LatLng(38.05, 114.49), level: LabelLevel.province),
    CityLabel(name: "山西", coord: LatLng(37.87, 112.56), level: LabelLevel.province),
    CityLabel(name: "内蒙古", coord: LatLng(40.82, 111.67), level: LabelLevel.province),
    CityLabel(name: "辽宁", coord: LatLng(41.80, 123.38), level: LabelLevel.province),
    CityLabel(name: "吉林", coord: LatLng(43.88, 125.32), level: LabelLevel.province),
    CityLabel(name: "黑龙江", coord: LatLng(45.80, 126.53), level: LabelLevel.province),
    CityLabel(name: "上海", coord: LatLng(31.25, 121.49), level: LabelLevel.province),
    CityLabel(name: "江苏", coord: LatLng(32.06, 118.80), level: LabelLevel.province),
    CityLabel(name: "浙江", coord: LatLng(30.27, 120.15), level: LabelLevel.province),
    CityLabel(name: "安徽", coord: LatLng(31.87, 117.28), level: LabelLevel.province),
    CityLabel(name: "福建", coord: LatLng(26.05, 119.33), level: LabelLevel.province),
    CityLabel(name: "江西", coord: LatLng(28.68, 115.86), level: LabelLevel.province),
    CityLabel(name: "山东", coord: LatLng(36.65, 117.00), level: LabelLevel.province),
    CityLabel(name: "河南", coord: LatLng(34.76, 113.65), level: LabelLevel.province),
    CityLabel(name: "湖北", coord: LatLng(30.58, 114.30), level: LabelLevel.province),
    CityLabel(name: "湖南", coord: LatLng(28.21, 112.94), level: LabelLevel.province),
    CityLabel(name: "广东", coord: LatLng(23.12, 113.31), level: LabelLevel.province),
    CityLabel(name: "广西", coord: LatLng(22.81, 108.30), level: LabelLevel.province),
    CityLabel(name: "海南", coord: LatLng(20.02, 110.33), level: LabelLevel.province),
    CityLabel(name: "重庆", coord: LatLng(29.54, 106.53), level: LabelLevel.province),
    CityLabel(name: "四川", coord: LatLng(30.57, 104.07), level: LabelLevel.province),
    CityLabel(name: "贵州", coord: LatLng(26.63, 106.71), level: LabelLevel.province),
    CityLabel(name: "云南", coord: LatLng(25.04, 102.68), level: LabelLevel.province),
    CityLabel(name: "西藏", coord: LatLng(29.65, 91.12), level: LabelLevel.province),
    CityLabel(name: "陕西", coord: LatLng(34.34, 108.94), level: LabelLevel.province),
    CityLabel(name: "甘肃", coord: LatLng(36.06, 103.82), level: LabelLevel.province),
    CityLabel(name: "青海", coord: LatLng(36.62, 101.78), level: LabelLevel.province),
    CityLabel(name: "宁夏", coord: LatLng(38.47, 106.27), level: LabelLevel.province),
    CityLabel(name: "新疆", coord: LatLng(43.83, 87.63), level: LabelLevel.province),
    CityLabel(name: "香港", coord: LatLng(22.29, 114.19), level: LabelLevel.province),
    CityLabel(name: "澳门", coord: LatLng(22.19, 113.55), level: LabelLevel.province),
    CityLabel(name: "台湾", coord: LatLng(23.97, 120.96), level: LabelLevel.province),
    CityLabel(name: "東京", coord: LatLng(35.68, 139.65), level: LabelLevel.province),
    CityLabel(name: "北海道", coord: LatLng(43.06, 141.35), level: LabelLevel.province),
    CityLabel(name: "東北", coord: LatLng(38.92, 140.78), level: LabelLevel.province),
    CityLabel(name: "関東", coord: LatLng(36.00, 139.70), level: LabelLevel.province),
    CityLabel(name: "中部", coord: LatLng(35.30, 137.10), level: LabelLevel.province),
    CityLabel(name: "近畿", coord: LatLng(34.85, 135.50), level: LabelLevel.province),
    CityLabel(name: "中国", coord: LatLng(35.86, 104.20), level: LabelLevel.province),
    CityLabel(name: "モンゴル", coord: LatLng(46.87, 103.84), level: LabelLevel.province),
    CityLabel(name: "韓国", coord: LatLng(36.50, 127.90), level: LabelLevel.province),
  ];

  /// 默认城市标签
  /// 
  /// 包含中国主要城市及周边重要城市
  static final List<CityLabel> _defaultCityLabels = [
    CityLabel(name: "广州", coord: LatLng(23.12, 113.31)),
    CityLabel(name: "深圳", coord: LatLng(22.55, 114.03)),
    CityLabel(name: "杭州", coord: LatLng(30.27, 120.15)),
    CityLabel(name: "南京", coord: LatLng(32.06, 118.80)),
    CityLabel(name: "武汉", coord: LatLng(30.58, 114.30)),
    CityLabel(name: "成都", coord: LatLng(30.57, 104.07)),
    CityLabel(name: "西安", coord: LatLng(34.34, 108.94)),
    CityLabel(name: "兰州", coord: LatLng(36.06, 103.82)),
    CityLabel(name: "昆明", coord: LatLng(25.04, 102.68)),
    CityLabel(name: "贵阳", coord: LatLng(26.63, 106.71)),
    CityLabel(name: "南宁", coord: LatLng(22.81, 108.30)),
    CityLabel(name: "海口", coord: LatLng(20.02, 110.33)),
    CityLabel(name: "长沙", coord: LatLng(28.21, 112.94)),
    CityLabel(name: "南昌", coord: LatLng(28.68, 115.86)),
    CityLabel(name: "福州", coord: LatLng(26.05, 119.33)),
    CityLabel(name: "合肥", coord: LatLng(31.87, 117.28)),
    CityLabel(name: "郑州", coord: LatLng(34.76, 113.65)),
    CityLabel(name: "济南", coord: LatLng(36.65, 117.00)),
    CityLabel(name: "太原", coord: LatLng(37.87, 112.56)),
    CityLabel(name: "石家庄", coord: LatLng(38.05, 114.49)),
    CityLabel(name: "沈阳", coord: LatLng(41.80, 123.38)),
    CityLabel(name: "长春", coord: LatLng(43.88, 125.32)),
    CityLabel(name: "哈尔滨", coord: LatLng(45.80, 126.53)),
    CityLabel(name: "呼和浩特", coord: LatLng(40.82, 111.67)),
    CityLabel(name: "乌鲁木齐", coord: LatLng(43.83, 87.63)),
    CityLabel(name: "拉萨", coord: LatLng(29.65, 91.12)),
    CityLabel(name: "西宁", coord: LatLng(36.62, 101.78)),
    CityLabel(name: "银川", coord: LatLng(38.47, 106.27)),
    CityLabel(name: "大连", coord: LatLng(38.92, 121.62)),
    CityLabel(name: "青岛", coord: LatLng(36.07, 120.38)),
    CityLabel(name: "厦门", coord: LatLng(24.49, 118.10)),
    CityLabel(name: "台北", coord: LatLng(25.04, 121.51)),
    CityLabel(name: "大阪", coord: LatLng(34.69, 135.50)),
    CityLabel(name: "福岡", coord: LatLng(33.59, 130.40)),
    CityLabel(name: "札幌", coord: LatLng(43.06, 141.35)),
    CityLabel(name: "仙台", coord: LatLng(38.26, 140.87)),
    CityLabel(name: "名古屋", coord: LatLng(35.18, 136.91)),
    CityLabel(name: "広島", coord: LatLng(34.39, 132.46)),
    CityLabel(name: "首尔", coord: LatLng(37.57, 126.98)),
    CityLabel(name: "平壤", coord: LatLng(39.04, 125.76)),
    CityLabel(name: "釜山", coord: LatLng(35.18, 129.08)),
  ];

  /// 初始化图层配置
  void _initLayers() {
    if (_layers.isNotEmpty) return;
    _cityLabels.clear();
    _cityLabels.addAll(_defaultProvinceLabels);
    _cityLabels.addAll(_defaultCityLabels);

    _layers.addAll([
      BoundaryLayer(
        name: "全球",
        assetPath: 'assets/maps/world_countries.geojson',
        borderColor: const Color(0xFF555555),
        borderWidth: 1.0,
        fillColor: const Color(0xFFD0D0D8),
        minZoom: 3.0,
        maxZoom: 18.0,
        isGeoJson: true,
      ),
      BoundaryLayer(
        name: "日本都道府県",
        assetPath: 'assets/maps/japan_prefectures.geojson',
        borderColor: const Color(0xFF1A1A1A),
        borderWidth: 1.0,
        fillColor: const Color(0xFFD0D0D8),
        minZoom: 3.0,
        maxZoom: 18.0,
        isGeoJson: true,
      ),
      BoundaryLayer(
        name: "中国省界",
        assetPath: 'assets/maps/中华人民共和国.geojson',
        borderColor: const Color(0xFF1A1A1A),
        borderWidth: 1.5,
        fillColor: const Color(0xFFD0D0D8),
        minZoom: 3.0,
        maxZoom: 18.0,
        isGeoJson: true,
      ),
      // Fault layer intentionally omitted: minZoom was 99 (never drawn).
    ]);
  }

  /// 加载所有边界数据
  /// 
  /// 遍历所有图层配置，加载并解析对应的地图文件
  Future<void> load() {
    if (_isLoaded) return Future.value();
    return _loading ??= _loadAll().whenComplete(() {
      _loading = null;
    });
  }

  Future<void> _loadAll() async {
    if (_isLoaded || _isLoading) return;
    _isLoading = true;
    _initLayers();

    await Future.wait(_layers.map((layer) async {
      try {
        final jsonStr = await rootBundle.loadString(layer.assetPath);
        if (layer.isGeoJson) {
          parseGeoJson(jsonStr, layer);
        } else {
          parseTopoJson(jsonStr, layer);
        }
        debugPrint(
          '${layer.name}: ${layer.polygons.length} 多边形 + ${layer.polylines.length} 线段 [zoom ${layer.minZoom}-${layer.maxZoom}]',
        );
      } catch (e) {
        debugPrint('Failed to load ${layer.assetPath}: $e');
      }
    }));

    _isLoading = false;
    _isLoaded = true;
    debugPrint('边界层加载完成，共 ${_layers.length} 层');
  }

  @visibleForTesting
  void resetForTesting() {
    _layers.clear();
    _cityLabels.clear();
    _isLoaded = false;
    _isLoading = false;
    _loading = null;
  }

  /// 解析GeoJSON格式
  /// 
  /// 支持的几何类型：
  /// - Polygon: 单个多边形
  /// - MultiPolygon: 多个多边形
  /// - LineString: 单条线
  /// - MultiLineString: 多条线
  void parseGeoJson(String jsonStr, BoundaryLayer layer) {
    final data = json.decode(jsonStr);
    if (data['type'] != 'FeatureCollection') {
      debugPrint('${layer.name}: 不是GeoJSON FeatureCollection格式');
      return;
    }

    final features = data['features'] as List?;
    if (features == null) return;

    final excludeNames = <String>{
      'Japan', 'Taiwan',
      '日本', '台湾',
      'JPN', 'TWN',
    };

    for (var feature in features) {
      final props = feature['properties'];
      if (props is Map) {
        final name = props['name']?.toString() ?? props['NAME']?.toString() ?? '';
        final isoA3 = props['ISO_A3']?.toString() ?? props['iso_a3']?.toString() ?? '';
        if (excludeNames.contains(name) || excludeNames.contains(isoA3)) continue;
      }

      final geom = feature['geometry'];
      if (geom is! Map) continue;
      final geomType = geom['type'];
      final coords = geom['coordinates'];

      switch (geomType) {
        case 'Polygon':
          _processGeoJsonPolygon(coords, layer);
          break;
        case 'MultiPolygon':
          if (coords is List) {
            for (var polyCoords in coords) {
              _processGeoJsonPolygon(polyCoords, layer);
            }
          }
          break;
        case 'LineString':
          _processGeoJsonLineString(coords, layer);
          break;
        case 'MultiLineString':
          if (coords is List) {
            for (var lineCoords in coords) {
              _processGeoJsonLineString(lineCoords, layer);
            }
          }
          break;
      }
    }
  }

  /// 处理GeoJSON多边形
  void _processGeoJsonPolygon(dynamic ringsData, BoundaryLayer layer) {
    if (ringsData is! List || ringsData.isEmpty) return;

    final outerRing = _geoJsonCoordsToPoints(ringsData[0]);
    if (outerRing.length < 4) return;

    if (layer.fillColor != null) {
      final holes = <List<LatLng>>[];
      for (int i = 1; i < ringsData.length; i++) {
        final holeRing = _geoJsonCoordsToPoints(ringsData[i]);
        if (holeRing.length >= 4) holes.add(holeRing);
      }
      layer.polygons.add(Polygon(
        points: outerRing,
        holePointsList: holes.isNotEmpty ? holes : null,
        borderColor: const Color(0x00000000),
        borderStrokeWidth: 0,
        color: layer.fillColor!,
      ));
    }

    for (var ring in ringsData) {
      final ringPts = _geoJsonCoordsToPoints(ring);
      if (ringPts.length >= 2) {
        layer.polylines.add(Polyline(
          points: ringPts,
          color: layer.borderColor,
          strokeWidth: layer.borderWidth,
        ));
      }
    }
  }

  /// 处理GeoJSON线段
  void _processGeoJsonLineString(dynamic coords, BoundaryLayer layer) {
    final pts = _geoJsonCoordsToPoints(coords);
    if (pts.length >= 2) {
      layer.polylines.add(Polyline(
        points: pts,
        color: layer.borderColor,
        strokeWidth: layer.borderWidth,
      ));
    }
  }

  /// 将GeoJSON坐标转换为LatLng列表
  List<LatLng> _geoJsonCoordsToPoints(dynamic coords) {
    if (coords is! List || coords.isEmpty) return [];
    final points = <LatLng>[];
    for (var coord in coords) {
      if (coord is! List || coord.length < 2) continue;
      final lng = (coord[0] as num).toDouble();
      final lat = (coord[1] as num).toDouble();
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  /// 解析TopoJSON格式
  /// 
  /// TopoJSON是一种拓扑编码的GeoJSON扩展格式
  /// 通过共享弧段来减小文件大小
  void parseTopoJson(String jsonStr, BoundaryLayer layer) {
    final data = json.decode(jsonStr);
    if (data['type'] != 'Topology') {
      debugPrint('${layer.name}: 不是TopoJSON格式');
      return;
    }

    final rawArcs = data['arcs'] as List;
    final transform = data['transform'];
    final scaleX = transform['scale'][0];
    final scaleY = transform['scale'][1];
    final transX = transform['translate'][0];
    final transY = transform['translate'][1];

    final decodedArcs = rawArcs.map<List<LatLng>>((arc) {
      final points = <LatLng>[];
      double x = 0, y = 0;
      for (var seg in arc) {
        x += (seg[0] as num).toDouble();
        y += (seg[1] as num).toDouble();
        points.add(LatLng(
          y * scaleY + transY,
          x * scaleX + transX,
        ));
      }
      return points;
    }).toList();

    final objects = data['objects'];
    final objKey = layer.objectKey;
    if (objects[objKey] == null) return;

    var geomContainer = objects[objKey];
    if (geomContainer is! Map) return;

    final geomType = geomContainer['type'];
    if (geomType == 'GeometryCollection') {
      final geometries = geomContainer['geometries'] as List?;
      if (geometries == null) return;
      for (var geom in geometries) {
        _processGeometry(geom, decodedArcs, layer);
      }
    } else {
      _processGeometry(geomContainer, decodedArcs, layer);
    }
  }

  /// 处理TopoJSON几何对象
  void _processGeometry(Map geom, List<List<LatLng>> decodedArcs, BoundaryLayer layer) {
    final type = geom['type'];
    final arcsData = geom['arcs'];
    if (arcsData == null) return;

    switch (type) {
      case 'Point':
      case 'MultiPoint':
        break;
      case 'LineString':
        _emitArcsAsPolylines(arcsData, decodedArcs, layer);
        break;
      case 'MultiLineString':
        for (var lineArcs in arcsData) {
          _emitArcsAsPolylines(lineArcs, decodedArcs, layer);
        }
        break;
      case 'Polygon':
        _processPolygon(arcsData, decodedArcs, layer);
        break;
      case 'MultiPolygon':
        for (var polyArcs in arcsData) {
          _processPolygon(polyArcs, decodedArcs, layer);
        }
        break;
      default:
        debugPrint('未知 geometry type: $type');
    }
  }

  /// 处理TopoJSON多边形
  void _processPolygon(List ringsData, List<List<LatLng>> decodedArcs, BoundaryLayer layer) {
    if (ringsData is! List || ringsData.isEmpty) return;

    if (layer.fillColor != null) {
      final outerRing = _buildRingPoints(ringsData[0], decodedArcs);
      if (outerRing.length >= 4) {
        final holes = <List<LatLng>>[];
        for (int i = 1; i < ringsData.length; i++) {
          final holeRing = _buildRingPoints(ringsData[i], decodedArcs);
          if (holeRing.length >= 4) holes.add(holeRing);
        }
        layer.polygons.add(Polygon(
          points: outerRing,
          holePointsList: holes.isNotEmpty ? holes : null,
          borderColor: const Color(0x00000000),
          borderStrokeWidth: 0,
          color: layer.fillColor!,
        ));
      }
    }

    for (var ring in ringsData) {
      _emitArcsAsPolylines(ring, decodedArcs, layer);
    }
  }

  /// 构建环形点列表
  /// 
  /// 将TopoJSON弧段索引转换为实际的坐标点
  List<LatLng> _buildRingPoints(dynamic arcIndices, List<List<LatLng>> decodedArcs) {
    if (arcIndices is! List || arcIndices.isEmpty) return [];

    final points = <LatLng>[];
    const threshold = 2.0;

    for (var idx in arcIndices) {
      final n = (idx is int) ? idx : (idx as num).toInt();
      final absN = n.abs();
      if (absN >= decodedArcs.length) continue;

      var arcPts = decodedArcs[absN];
      if (n < 0) {
        arcPts = arcPts.reversed.toList();
      }

      if (arcPts.isEmpty) continue;

      if (points.isNotEmpty) {
        final lastPt = points.last;
        final firstPt = arcPts.first;
        final dx = (lastPt.longitude - firstPt.longitude).abs();
        final dy = (lastPt.latitude - firstPt.latitude).abs();
        if (dx > threshold || dy > threshold) continue;
        points.removeLast();
      }

      points.addAll(arcPts);
    }

    if (points.length < 3) return [];

    points.add(points.first);
    return points;
  }

  /// 将弧段转换为折线
  void _emitArcsAsPolylines(dynamic arcIndices, List<List<LatLng>> decodedArcs, BoundaryLayer layer) {
    if (arcIndices is! List || arcIndices.isEmpty) return;

    for (var idx in arcIndices) {
      final n = (idx is int) ? idx : (idx as num).toInt();
      final absN = n.abs();
      if (absN >= decodedArcs.length) continue;

      var pts = decodedArcs[absN];
      if (n < 0) {
        pts = pts.reversed.toList();
      }

      if (pts.length < 2) continue;

      layer.polylines.add(Polyline(
        points: pts,
        color: layer.borderColor,
        strokeWidth: layer.borderWidth,
      ));
    }
  }
}
