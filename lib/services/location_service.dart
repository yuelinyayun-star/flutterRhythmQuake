import 'package:geolocator/geolocator.dart';

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
  
  /// 获取当前位置
  Position? get currentPosition => _currentPosition;

  /// 初始化位置权限并获取位置
  /// 
  /// 执行流程：
  /// 1. 检查位置服务是否启用
  /// 2. 检查/请求位置权限
  /// 3. 获取当前位置
  /// 
  /// 如果位置服务未启用或权限被拒绝，
  /// 则不会获取位置信息。
  Future<void> init() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      _currentPosition = await Geolocator.getCurrentPosition();
    }
  }
}
