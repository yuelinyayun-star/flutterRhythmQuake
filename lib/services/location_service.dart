import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, kIsWeb;
import 'package:geolocator/geolocator.dart';

enum LocationServiceStatus {
  idle,
  locating,
  available,
  serviceDisabled,
  permissionDenied,
  failed,
}

/// 位置服务
///
/// 该类提供设备位置获取功能。
/// 采用单例模式，管理位置权限和位置信息。
///
/// 主要功能：
/// - 请求位置权限
/// - 获取当前位置
/// - 缓存位置信息
///
/// 使用场景：
/// - 计算用户与震中的距离
/// - 提供本地化的预警服务
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// 当前位置缓存
  Position? _currentPosition;
  final ValueNotifier<Position?> _positionNotifier = ValueNotifier(null);
  final ValueNotifier<LocationServiceStatus> _statusNotifier = ValueNotifier(
    LocationServiceStatus.idle,
  );

  /// 获取当前位置
  Position? get currentPosition => _currentPosition;
  ValueListenable<Position?> get positionListenable => _positionNotifier;
  ValueListenable<LocationServiceStatus> get statusListenable =>
      _statusNotifier;

  /// 初始化位置权限并获取位置。
  ///
  /// 保留给旧调用方；实际只做一次性定位，不创建常驻监听。
  Future<void> init() async {
    await requestCurrentPosition();
  }

  /// 一次性请求当前位置。
  ///
  /// 执行流程：
  /// 1. 检查位置服务是否启用
  /// 2. 检查/请求位置权限
  /// 3. 获取当前位置
  ///
  /// 如果位置服务未启用或权限被拒绝，
  /// 则不会获取位置信息。
  Future<Position?> requestCurrentPosition() async {
    if (kIsWeb) {
      _statusNotifier.value = LocationServiceStatus.failed;
      return null;
    }

    _statusNotifier.value = LocationServiceStatus.locating;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        const Duration(seconds: 3),
      );
      if (!serviceEnabled) {
        _currentPosition = null;
        _positionNotifier.value = null;
        _statusNotifier.value = LocationServiceStatus.serviceDisabled;
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
        _currentPosition = await Geolocator.getCurrentPosition().timeout(
          const Duration(seconds: 10),
        );
        _positionNotifier.value = _currentPosition;
        _statusNotifier.value = LocationServiceStatus.available;
        return _currentPosition;
      }

      _currentPosition = null;
      _positionNotifier.value = null;
      _statusNotifier.value = LocationServiceStatus.permissionDenied;
      return null;
    } catch (_) {
      _currentPosition = null;
      _positionNotifier.value = null;
      _statusNotifier.value = LocationServiceStatus.failed;
      return null;
    }
  }

  void setCurrentPosition(Position position) {
    _currentPosition = position;
    _positionNotifier.value = position;
    _statusNotifier.value = LocationServiceStatus.available;
  }
}
