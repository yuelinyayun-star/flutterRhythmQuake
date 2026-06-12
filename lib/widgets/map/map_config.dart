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
  /// FanStudio瓦片服务基础URL
  static const String _fanBase = 'https://tilemap.fanstudio.tech';

  /// Petal深色主题瓦片
  /// 适合夜间模式和地震数据可视化
  static const String petalDark = '$_fanBase/petaldark/{z}/{y}/{x}';

  /// Petal浅色主题瓦片
  /// 适合日间模式，提供清晰的地图底图
  static const String petalLight = '$_fanBase/petallight/{z}/{y}/{x}';

  /// ArcGIS卫星影像瓦片
  /// 提供高分辨率卫星图像
  static const String arcgisSatellite = '$_fanBase/arcwi/{z}/{y}/{x}';

  /// ArcGIS地形图瓦片
  /// 提供详细的地形和地貌信息
  static const String arcgisTopo = '$_fanBase/arcwob/{z}/{y}/{x}';

  /// ArcGIS山体阴影瓦片
  /// 增强地形立体感
  static const String arcgisHillshade = '$_fanBase/arcwh/{z}/{y}/{x}';

  /// DEM高程数据
  /// 提供数字高程模型地形数据
  static const String demElevation = '$_fanBase/dem/{z}/{y}/{x}';

  /// 实况云图层
  /// 实时卫星云图叠加层
  static const String cloudLayer = '$_fanBase/cloud/{z}/{y}/{x}';

  /// 实况降水图层
  /// 实时降水雷达叠加层
  static const String rainLayer = '$_fanBase/rain/{z}/{y}/{x}';

  /// 实况风图层
  /// 实时风场图叠加层
  static const String windLayer = '$_fanBase/wind/{z}/{y}/{x}';

  /// 中国境内等高线
  /// 中国区域等高线地形图
  static const String cnContour = '$_fanBase/cncl/{z}/{y}/{x}';

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
    'Petal 浅色': 'petalLight',
    'Petal 深色': 'petalDark',
    'ArcGIS 卫星': 'arcgisSatellite',
    'ArcGIS 地形': 'arcgisTopo',
    'ArcGIS 山体阴影': 'arcgisHillshade',
    'DEM 高程数据': 'demElevation',
    'CartoDB 深色': 'cartoDark',
    'OpenStreetMap': 'osmTileUrl',
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
    return isBaseTileKey(key) ? key : 'petalLight';
  }

  /// 根据键名获取瓦片URL
  static String urlByKey(String key) {
    switch (key) {
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
      case 'osmTileUrl':
        return osmTileUrl;
      default:
        return petalLight;
    }
  }

  static String overlayUrlByKey(String key) => urlByKey(key);
}
