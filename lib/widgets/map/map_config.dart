/// 地图瓦片配置类
///
/// 该类定义了应用中使用的各种地图瓦片源URL模板。
/// 使用静态常量确保配置的一致性和可维护性。
///
/// 瓦片URL模板说明：
/// - {z}: 缩放级别 (zoom level)
/// - {x}: 横向瓦片索引
/// - {y}: 纵向瓦片索引
/// - {s}: 服务器子域名 (用于并行加载)
/// - {r}: Retina高清标识
class MapConfig {
  static const String vectorBasemapKey = 'kaVector';
  static const String mapboxEewceDarkKey = 'mapboxEewceDark';
  static const String mapboxUsernameKey = 'mapbox_username';
  static const String mapboxStyleIdKey = 'mapbox_style_id';
  static const String mapboxAccessTokenKey = 'mapbox_access_token';
  static const Set<String> _removedBaseTileKeys = {
    'tencentVector',
    'tencentWmts',
    'tencentStaticMap',
    'tencentJsMap',
  };
  static const String _mapboxDefaultUsername = 'mapbox';
  static const String _mapboxDefaultStyleId = 'dark-v11';

  static String _mapboxUsername = _mapboxDefaultUsername;
  static String _mapboxStyleId = _mapboxDefaultStyleId;
  static String _mapboxAccessToken = '';

  static String get mapboxUsername => _mapboxUsername;
  static String get mapboxStyleId => _mapboxStyleId;
  static String get mapboxAccessToken => _mapboxAccessToken;
  static bool get hasMapboxAccessToken => _mapboxAccessToken.isNotEmpty;

  static void configureMapbox({
    required String username,
    required String styleId,
    required String accessToken,
  }) {
    _mapboxUsername = _mapboxNamePart(username, _mapboxDefaultUsername);
    _mapboxStyleId = _mapboxNamePart(styleId, _mapboxDefaultStyleId);
    _mapboxAccessToken = accessToken.trim();
  }

  static void configureMapboxFromPrefs(Map<String, Object?> prefs) {
    configureMapbox(
      username: prefs[mapboxUsernameKey]?.toString() ?? _mapboxDefaultUsername,
      styleId: prefs[mapboxStyleIdKey]?.toString() ?? _mapboxDefaultStyleId,
      accessToken: prefs[mapboxAccessTokenKey]?.toString() ?? '',
    );
  }

  static String _mapboxNamePart(String value, String fallback) {
    final cleaned = value
        .trim()
        .replaceFirst('mapbox://styles/', '')
        .replaceFirst('https://api.mapbox.com/styles/v1/', '')
        .split('?')
        .first;
    final parts = cleaned.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return fallback;
    return parts.last;
  }

  static String get mapboxEewceDark {
    if (!hasMapboxAccessToken) return petalDark;
    final token = Uri.encodeQueryComponent(_mapboxAccessToken);
    return 'https://api.mapbox.com/styles/v1/'
        '$_mapboxUsername/$_mapboxStyleId/tiles/512/{z}/{x}/{y}'
        '?access_token=$token';
  }

  /// FanStudio瓦片服务基础URL
  static const String _fanBase = 'https://tilemap.fanstudio.tech';
  static const String _fanCacheRevision = '20260822-zxy';

  /// Petal深色主题瓦片
  /// 适合夜间模式和地震数据可视化
  static const String petalDark =
      '$_fanBase/petaldark/{z}/{x}/{y}?v=$_fanCacheRevision';

  /// Petal浅色主题瓦片
  /// 适合日间模式，提供清晰的地图底图
  static const String petalLight =
      '$_fanBase/petallight/{z}/{x}/{y}?v=$_fanCacheRevision';

  /// ArcGIS卫星影像瓦片
  /// 提供高分辨率卫星图像
  static const String arcgisSatellite =
      '$_fanBase/arcwi/{z}/{x}/{y}?v=$_fanCacheRevision';

  /// ArcGIS地形图瓦片
  /// 提供详细的地形和地貌信息
  static const String arcgisTopo =
      '$_fanBase/arcwob/{z}/{x}/{y}?v=$_fanCacheRevision';

  /// ArcGIS山体阴影瓦片
  /// 增强地形立体感
  static const String arcgisHillshade =
      '$_fanBase/arcwh/{z}/{x}/{y}?v=$_fanCacheRevision';

  /// DEM高程数据
  /// 提供数字高程模型地形数据
  static const String demElevation =
      '$_fanBase/dem/{z}/{x}/{y}?v=$_fanCacheRevision';

  /// 实况云图层
  /// 实时卫星云图叠加层
  static const String cloudLayer =
      '$_fanBase/cloud/{z}/{x}/{y}?v=$_fanCacheRevision';

  /// 实况降水图层
  /// 实时降水雷达叠加层
  static const String rainLayer =
      '$_fanBase/rain/{z}/{x}/{y}?v=$_fanCacheRevision';

  /// 实况风图层
  /// 实时风场图叠加层
  static const String windLayer =
      '$_fanBase/wind/{z}/{x}/{y}?v=$_fanCacheRevision';

  /// 中国境内等高线
  /// 中国区域等高线地形图
  static const String cnContour =
      '$_fanBase/cncl/{z}/{x}/{y}?v=$_fanCacheRevision';

  /// 当前使用的瓦片URL
  /// 默认使用Petal浅色主题
  static String currentTileUrl = petalLight;

  /// CartoDB深色主题瓦片
  /// 开源地图服务，适合数据可视化
  static const String cartoDark =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  /// OpenStreetMap标准瓦片
  /// 开源地图服务，全球覆盖
  static const String osmTileUrl =
      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// 所有可用瓦片选项 (显示名 → URL键名)
  static Map<String, String> get baseTileOptions => {
    '矢量地图': vectorBasemapKey,
    'Petal 浅色': 'petalLight',
    'Petal 深色': 'petalDark',
    'ArcGIS 卫星': 'arcgisSatellite',
    'ArcGIS 地形': 'arcgisTopo',
    'ArcGIS 山体阴影': 'arcgisHillshade',
    'DEM 高程数据': 'demElevation',
    'Mapbox Dark': mapboxEewceDarkKey,
  };

  /// 可选叠加图层 (显示名 -> 图层键名)
  static Map<String, String> get overlayOptions => {
    '实况云图': 'cloudLayer',
    '实况风场': 'windLayer',
    '实况降水': 'rainLayer',
    '中国等高线': 'cnContour',
  };

  static bool isBaseTileKey(String key) {
    return baseTileOptions.containsValue(key);
  }

  static String normalizeBaseTileKey(String key) {
    if (_removedBaseTileKeys.contains(key)) return 'petalLight';
    // Hidden-but-still-supported legacy keys (not exposed in UI).
    // Keep them working if user already persisted them locally.
    if (key == 'cartoDark' || key == 'osmTileUrl') return key;
    return isBaseTileKey(key) ? key : 'petalLight';
  }

  /// 根据键名获取瓦片URL
  static String urlByKey(String key) {
    switch (key) {
      case vectorBasemapKey:
        return '';
      case 'petalDark':
        return petalDark;
      case 'petalLight':
        return petalLight;
      case 'arcgisSatellite':
        return arcgisSatellite;
      case 'arcgisTopo':
        return arcgisTopo;
      case 'arcgisHillshade':
        return arcgisHillshade;
      case 'demElevation':
        return demElevation;
      case 'cloudLayer':
        return cloudLayer;
      case 'rainLayer':
        return rainLayer;
      case 'windLayer':
        return windLayer;
      case 'cnContour':
        return cnContour;
      case 'cartoDark':
        return cartoDark;
      case mapboxEewceDarkKey:
        return mapboxEewceDark;
      case 'osmTileUrl':
        return osmTileUrl;
      default:
        return petalLight;
    }
  }

  static bool isTmsTileKey(String key) {
    return false;
  }

  static List<String> subdomainsByKey(String key) {
    switch (key) {
      case 'cartoDark':
      case 'osmTileUrl':
        return const ['a', 'b', 'c'];
      default:
        return const [];
    }
  }

  static String overlayUrlByKey(String key) => urlByKey(key);
}
