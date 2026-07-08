import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

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
  static const String mapboxEewceDarkKey = 'mapboxEewceDark';
  static const String mapboxUsernameKey = 'mapbox_username';
  static const String mapboxStyleIdKey = 'mapbox_style_id';
  static const String mapboxAccessTokenKey = 'mapbox_access_token';
  static const String tencentWmtsKey = 'tencentWmts';
  static const String tencentStaticMapKey = 'tencentStaticMap';
  static const String tencentJsMapKey = 'tencentJsMap';
  static const String tencentStaticMapTemplate =
      'tencent-static-map://tile/{z}/{x}/{y}';
  static const String tencentWmtsApiKeyKey = 'tencent_wmts_api_key';
  static const String tencentWmtsSecretKeyKey = 'tencent_wmts_secret_key';
  static const String _mapboxDefaultUsername = 'mapbox';
  static const String _mapboxDefaultStyleId = 'dark-v11';

  static String _mapboxUsername = _mapboxDefaultUsername;
  static String _mapboxStyleId = _mapboxDefaultStyleId;
  static String _mapboxAccessToken = '';
  static String _tencentWmtsApiKey = '';
  static String _tencentWmtsSecretKey = '';
  static String? _lastTencentWmtsStateLogKey;
  static bool _loggedTencentWmtsFallback = false;

  static String get mapboxUsername => _mapboxUsername;
  static String get mapboxStyleId => _mapboxStyleId;
  static String get mapboxAccessToken => _mapboxAccessToken;
  static bool get hasMapboxAccessToken => _mapboxAccessToken.isNotEmpty;
  static String get tencentWmtsApiKey => _tencentWmtsApiKey;
  static String get tencentWmtsSecretKey => _tencentWmtsSecretKey;
  static bool get hasTencentWmtsApiKey => _tencentWmtsApiKey.isNotEmpty;
  static bool get hasTencentWmtsSecretKey => _tencentWmtsSecretKey.isNotEmpty;

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

  static void configureTencentWmts({
    required String apiKey,
    String secretKey = '',
  }) {
    _tencentWmtsApiKey = apiKey.trim();
    _tencentWmtsSecretKey = secretKey.trim();
    _lastTencentWmtsStateLogKey = null;
    _loggedTencentWmtsFallback = false;
    debugPrint(
      '[TencentMap] configured: '
      'apiKey=${_maskSecret(_tencentWmtsApiKey)}, '
      'sk=${hasTencentWmtsSecretKey ? "set" : "empty"}',
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

  static String get tencentWmts {
    if (!hasTencentWmtsApiKey) {
      if (!_loggedTencentWmtsFallback) {
        _loggedTencentWmtsFallback = true;
        debugPrint('[TencentWMTS] APIKEY empty; fallback to Petal Light.');
      }
      return petalLight;
    }
    return 'https://apis.map.qq.com/maptile/base/wmts?'
        'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&'
        'LAYER=default&STYLE=default&FORMAT=image/png&'
        'TILEMATRIXSET=EPSG:3857&'
        'TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&'
        'key=${Uri.encodeQueryComponent(_tencentWmtsApiKey)}';
  }

  static String get tencentStaticMap {
    if (!hasTencentWmtsApiKey) {
      if (!_loggedTencentWmtsFallback) {
        _loggedTencentWmtsFallback = true;
        debugPrint('[TencentStaticMap] APIKEY empty; fallback to Petal Light.');
      }
      return petalLight;
    }
    return tencentStaticMapTemplate;
  }

  static bool isTencentStaticMapTemplate(String url) {
    return url.startsWith('tencent-static-map://tile/');
  }

  static bool isTencentStaticMapUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri?.scheme == 'https' &&
        uri?.host == 'apis.map.qq.com' &&
        uri?.path == '/ws/staticmap/v2/';
  }

  static String tencentStaticMapTileUrl({
    required int z,
    required int x,
    required int y,
  }) {
    if (!hasTencentWmtsApiKey) return petalLight;
    final center = _tileCenter(z: z, x: x, y: y);
    final zoom = z.clamp(4, 18);
    final params = <String, String>{
      'center':
          '${center.latitude.toStringAsFixed(6)},${center.longitude.toStringAsFixed(6)}',
      'key': _tencentWmtsApiKey,
      'maptype': 'roadmap',
      'scale': '1',
      'size': '256*256',
      'zoom': '$zoom',
    };
    return _signedTencentServiceUrl(
      path: '/ws/staticmap/v2/',
      params: params,
      logPrefix: 'TencentStaticMap',
    );
  }

  static bool isTencentWmtsUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri?.scheme == 'https' &&
        uri?.host == 'apis.map.qq.com' &&
        uri?.path == '/maptile/base/wmts';
  }

  static String signedTencentWmtsUrl(String url) {
    if (!isTencentWmtsUrl(url)) return url;
    if (!hasTencentWmtsSecretKey) {
      _logTencentWmtsRequestState(
        'unsigned:${_maskSecret(_tencentWmtsApiKey)}',
        'SN disabled or SK empty; request without sig. '
            'sample=${redactTencentWmtsUrl(url)}',
      );
      return url;
    }
    final uri = Uri.parse(url);
    return _signedTencentServiceUrl(
      path: uri.path,
      params: Map<String, String>.from(uri.queryParameters)..remove('sig'),
      logPrefix: 'TencentWMTS',
    );
  }

  static String _signedTencentServiceUrl({
    required String path,
    required Map<String, String> params,
    required String logPrefix,
  }) {
    final queryEntries = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final rawSortedQuery = queryEntries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    if (!hasTencentWmtsSecretKey) {
      return 'https://apis.map.qq.com$path?${_encodedQuery(queryEntries)}';
    }
    final signatureSource = '$path?$rawSortedQuery$_tencentWmtsSecretKey';
    final sig = md5.convert(utf8.encode(signatureSource)).toString();
    final signedUrl =
        'https://apis.map.qq.com$path?${_encodedQuery(queryEntries)}&sig=$sig';
    _logTencentWmtsRequestState(
      '$logPrefix:signed-v3-official-ordinal:${_maskSecret(_tencentWmtsApiKey)}:${_maskSecret(_tencentWmtsSecretKey)}',
      'SN enabled; sig appended from raw query. '
          'source=${_redactTencentSignatureSource(signatureSource)} '
          'sample=${redactTencentServiceUrl(signedUrl)}',
    );
    return signedUrl;
  }

  static String _encodedQuery(List<MapEntry<String, String>> queryEntries) {
    return queryEntries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  static void _logTencentWmtsRequestState(String key, String message) {
    if (_lastTencentWmtsStateLogKey == key) return;
    _lastTencentWmtsStateLogKey = key;
    debugPrint('[TencentWMTS] $message');
  }

  static String redactTencentWmtsUrl(String url) =>
      redactTencentServiceUrl(url);

  static String redactTencentServiceUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (!isTencentWmtsUrl(url) && !isTencentStaticMapUrl(url))) {
      return url;
    }
    final params = Map<String, String>.from(uri.queryParameters);
    if (params.containsKey('key')) {
      params['key'] = _maskSecret(params['key'] ?? '');
    }
    if (params.containsKey('sig')) {
      params['sig'] = _maskSecret(params['sig'] ?? '');
    }
    return uri.replace(queryParameters: params).toString();
  }

  static ({double latitude, double longitude}) _tileCenter({
    required int z,
    required int x,
    required int y,
  }) {
    final n = math.pow(2.0, z).toDouble();
    final longitude = (x + 0.5) / n * 360.0 - 180.0;
    final mercator = math.pi * (1.0 - 2.0 * (y + 0.5) / n);
    final sinh = (math.exp(mercator) - math.exp(-mercator)) / 2.0;
    final latRad = math.atan(sinh);
    final latitude = latRad * 180.0 / math.pi;
    return (latitude: latitude, longitude: longitude);
  }

  static String _redactTencentSignatureSource(String source) {
    return source
        .replaceAll(_tencentWmtsApiKey, _maskSecret(_tencentWmtsApiKey))
        .replaceAll(_tencentWmtsSecretKey, '<SK>');
  }

  static String _maskSecret(String value) {
    if (value.isEmpty) return 'empty';
    if (value.length <= 8) return '${value.substring(0, 2)}***';
    return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
  }

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
    'Mapbox Dark': mapboxEewceDarkKey,
    'OpenStreetMap': 'osmTileUrl',
    '腾讯地图': tencentJsMapKey,
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
    if (key == 'tencentVector' ||
        key == tencentWmtsKey ||
        key == tencentStaticMapKey) {
      return tencentJsMapKey;
    }
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
      case mapboxEewceDarkKey:
        return mapboxEewceDark;
      case 'osmTileUrl':
        return osmTileUrl;
      case tencentJsMapKey:
        return petalLight;
      case tencentStaticMapKey:
        return tencentStaticMap;
      case tencentWmtsKey:
      case 'tencentVector':
        return tencentWmts;
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
