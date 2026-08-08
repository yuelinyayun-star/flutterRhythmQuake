import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

enum LocationServiceStatus {
  idle,
  locating,
  available,
  serviceDisabled,
  permissionDenied,
  failed,
}

/// 位置来源，用于在 UI 上区分 GPS / IP 兜底 / 手动输入。
enum LocationSource {
  /// 还没拿到任何位置。
  unknown,

  /// 设备原生定位（GPS / Wi-Fi / 蜂窝网络定位）。
  native,

  /// 无 GPS 或权限被拒时，通过 IP 地理定位拿到的城市级粗略位置。
  ipFallback,

  /// 设置页手动输入的经纬度。
  manual,
}

/// 位置服务
///
/// 优先使用设备原生定位（geolocator）；
/// 当设备无 GPS（例如部分平板）或定位服务关闭/权限被拒时，
/// 回退到 IP 地理定位（fanstudio/wolfx/ip-api）拿一个城市级粗略位置。
/// 主要功能：
/// - 请求位置权限
/// - 获取当前位置（原生优先，IP 兜底）
/// - 缓存位置信息与来源
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// 当前位置缓存
  Position? _currentPosition;

  /// 当前位置来源
  LocationSource _currentSource = LocationSource.unknown;

  /// IP 兜底返回的省/市描述，便于 UI 提示与排查
  String? _ipRegion;

  final ValueNotifier<Position?> _positionNotifier = ValueNotifier(null);
  final ValueNotifier<LocationServiceStatus> _statusNotifier = ValueNotifier(
    LocationServiceStatus.idle,
  );
  final ValueNotifier<LocationSource> _sourceNotifier = ValueNotifier(
    LocationSource.unknown,
  );

  /// 获取当前位置
  Position? get currentPosition => _currentPosition;
  LocationSource get currentSource => _currentSource;
  String? get ipRegion => _ipRegion;

  ValueListenable<Position?> get positionListenable => _positionNotifier;
  ValueListenable<LocationServiceStatus> get statusListenable =>
      _statusNotifier;
  ValueListenable<LocationSource> get sourceListenable => _sourceNotifier;
  String? get bestRegionLabel => _ipRegion;

  /// 初始化位置权限并获取位置。
  ///
  /// 保留给旧调用方；实际只做一次性定位，不创建常驻监听。
  Future<void> init() async {
    await requestCurrentPosition();
  }

  /// 一次性请求当前位置。
  ///
  /// 执行流程：
  /// 1. 非 web 平台先尝试设备原生定位（GPS/网络）
  /// 2. 原生拿不到（无 GPS / 服务关闭 / 权限被拒）时，回退到 IP 定位
  /// 平板等无 GPS 设备会走 IP 兜底，仍能拿到城市级粗略位置。
  Future<Position?> requestCurrentPosition() async {
    _statusNotifier.value = LocationServiceStatus.locating;

    // 非 web 平台先试原生定位。
    if (!kIsWeb) {
      final native = await _requestNativePosition();
      if (native != null) {
        return native;
      }
      // 原生失败（无 GPS / 服务关闭 / 权限被拒），继续走 IP 兜底。
    }

    return _requestIpFallbackPosition();
  }

  /// 设备原生定位（geolocator）。
  Future<Position?> _requestNativePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        const Duration(seconds: 3),
      );
      if (!serviceEnabled) {
        _setStatus(LocationServiceStatus.serviceDisabled);
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 3));
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(
          const Duration(seconds: 10),
        );
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final lastKnown = await Geolocator.getLastKnownPosition().timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
        Position? position;
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 15),
          );
        } catch (_) {
          position = lastKnown;
        }
        if (position == null) {
          _setStatus(LocationServiceStatus.failed);
          return null;
        }
        _applyPosition(position, LocationSource.native, ipRegion: null);
        return position;
      }

      _setStatus(LocationServiceStatus.permissionDenied);
      return null;
    } catch (_) {
      _setStatus(LocationServiceStatus.failed);
      return null;
    }
  }

  /// 通过 IP 地理定位拿一个城市级粗略位置，作为无 GPS 设备的兜底。
  ///
  /// 三段回退链，按可用性与平台兼容性排序：
  /// 1. fanstudio geo_ip.php（https，返回中文省市 + 经纬度，iOS/Web/Android 通吃）
  /// 2. wolfx ip.php 取公网 IP 后，带 ?ip= 显式查 fanstudio（应对 CDN 误判访客 IP）
  /// 3. ip-api.com（http，Android cleartext 已开，最后兜底）
  ///
  /// 任一步成功即返回；全部失败才置 failed。
  /// IP 坐标精度仅城市级，省市名直接使用 IP 服务返回值。
  Future<Position?> _requestIpFallbackPosition() async {
    // 1. fanstudio 直查（访客 IP 自动判定）
    final pos = await _requestFanstudioGeoIp(ip: null);
    if (pos != null) return pos;

    // 2. wolfx 取公网 IP → 带 ?ip= 显式查 fanstudio（应对 CDN 误判访客 IP）
    final ip = await _requestWolfxPublicIp();
    if (ip != null) {
      final pos2 = await _requestFanstudioGeoIp(ip: ip);
      if (pos2 != null) return pos2;
    }

    // 3. ip-api.com 兜底（http，Android cleartext 已开）
    final pos3 = await _requestIpApiGeo();
    if (pos3 != null) return pos3;

    _setStatus(LocationServiceStatus.failed);
    return null;
  }

  /// fanstudio geo_ip.php：返回中文 country/province/city + latitude/longitude。
  /// 传 [ip] 时走 ?ip= 显式查询，不传时由服务端自动判定访客 IP。
  Future<Position?> _requestFanstudioGeoIp({String? ip}) async {
    final url = ip == null
        ? 'https://api.fanstudio.tech/tool/geo_ip.php'
        : 'https://api.fanstudio.tech/tool/geo_ip.php?ip=${Uri.encodeComponent(ip)}';
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body);
      if (data is! Map) return null;
      // 错误响应：{"error": "..."}
      if (data['error'] != null) return null;
      final lat = _toDouble(data['latitude']);
      final lon = _toDouble(data['longitude']);
      if (lat == null || lat.isNaN || lon == null || lon.isNaN) return null;

      final regionParts = <String>[];
      final province = data['province'];
      if (province is String && province.isNotEmpty) {
        regionParts.add(province);
      }
      final city = data['city'];
      if (city is String && city.isNotEmpty) {
        regionParts.add(city);
      }

      return _buildIpPosition(lat, lon, regionParts.join(' '));
    } catch (_) {
      return null;
    }
  }

  /// wolfx ip.php：纯文本返回访客公网 IP（如 "114.114.114.114"）。
  Future<String?> _requestWolfxPublicIp() async {
    try {
      final resp = await http
          .get(Uri.parse('https://api.wolfx.jp/ip.php'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final ip = resp.body.trim();
      // 简单校验：非空、无空白/HTML、形似 IPv4 或 IPv6。
      if (ip.isEmpty || ip.contains(' ') || ip.contains('<')) return null;
      final ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
      final ipv6 = RegExp(r'^[0-9a-fA-F:]+$');
      if (!ipv4.hasMatch(ip) && !ipv6.hasMatch(ip)) return null;
      return ip;
    } catch (_) {
      return null;
    }
  }

  /// ip-api.com：免 key，对中国友好，lang=zh-CN 返回中文省市名 + 经纬度。
  /// http 端点，依赖 Android cleartext 配置；iOS/Web 上会被 ATS/mixed-content 拦截。
  Future<Position?> _requestIpApiGeo() async {
    const url =
        'http://ip-api.com/json/?lang=zh-CN&fields=status,message,countryCode,regionName,city,lat,lon,timezone';
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body);
      if (data is! Map || data['status'] != 'success') return null;
      final lat = _toDouble(data['lat']);
      final lon = _toDouble(data['lon']);
      if (lat == null || lat.isNaN || lon == null || lon.isNaN) return null;

      final regionParts = <String>[];
      final regionName = data['regionName'];
      if (regionName is String && regionName.isNotEmpty) {
        regionParts.add(regionName);
      }
      final city = data['city'];
      if (city is String && city.isNotEmpty) {
        regionParts.add(city);
      }

      return _buildIpPosition(lat, lon, regionParts.join(' '));
    } catch (_) {
      return null;
    }
  }

  /// 构造一个城市级粗略 Position 并登记为 IP 兜底来源。
  /// accuracy 标为 50000 米，提示下游这是粗略定位。
  Position _buildIpPosition(double lat, double lon, String region) {
    final pos = Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 50000,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    _applyPosition(pos, LocationSource.ipFallback, ipRegion: region);
    return pos;
  }

  void _applyPosition(
    Position position,
    LocationSource source, {
    String? ipRegion,
  }) {
    _currentPosition = position;
    _currentSource = source;
    _ipRegion = ipRegion;
    _positionNotifier.value = position;
    _sourceNotifier.value = source;
    _statusNotifier.value = LocationServiceStatus.available;
  }

  void _setStatus(LocationServiceStatus status) {
    // A transient GPS, permission or network failure must not erase the last
    // usable manual/native/IP position. New installs still remain null because
    // they have no successful position to preserve.
    _statusNotifier.value = status;
  }

  void setCurrentPosition(Position position) {
    _applyPosition(position, LocationSource.native, ipRegion: null);
  }

  void setCurrentLatLng(double latitude, double longitude) {
    _applyPosition(
      Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
      LocationSource.manual,
      ipRegion: null,
    );
  }

  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
