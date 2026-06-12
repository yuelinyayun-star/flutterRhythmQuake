import 'package:ntp/ntp.dart';
import 'dart:async';

/// NTP时间同步服务
/// 
/// 该类提供网络时间协议(NTP)同步功能。
/// 用于校正设备本地时间与标准时间的偏差。
/// 
/// 主要功能：
/// - 同步NTP服务器时间
/// - 计算设备时间偏移量
/// - 提供修正后的当前时间
/// - 定时同步防止时钟漂移
/// 
/// 使用场景：
/// - 地震预警需要精确的时间同步
/// - 确保S波到达倒计时准确
/// - 多设备协同需要统一时间基准
class NtpService {
  static final NtpService _instance = NtpService._internal();
  factory NtpService() => _instance;
  NtpService._internal();

  /// 设备时间与NTP时间的偏移量（毫秒）
  /// 
  /// 正值表示设备时间快于标准时间
  /// 负值表示设备时间慢于标准时间
  int _deviceOffset = 0;
  
  /// 是否已同步
  bool _isSynced = false;

  int get deviceOffset => _deviceOffset;
  bool get isSynced => _isSynced;

  /// 获取经过修正后的当前时间
  /// 
  /// 返回NTP校准后的时间
  DateTime get now {
    return DateTime.now().add(Duration(milliseconds: _deviceOffset));
  }

  /// 同步NTP时间
  /// 
  /// 从指定NTP服务器获取时间并计算偏移量。
  /// 
  /// [lookUpAddress] NTP服务器地址
  /// 常用服务器：
  /// - pool.ntp.org: NTP池，全球分布
  /// - time.apple.com: 苹果时间服务器
  /// - ntp.aliyun.com: 阿里云NTP服务器
  Future<void> syncTime({String lookUpAddress = 'pool.ntp.org'}) async {
    try {
      print('--- 正在同步 NTP 时间自: $lookUpAddress ---');

      int offset = await NTP.getNtpOffset(
        lookUpAddress: lookUpAddress,
        timeout: const Duration(seconds: 5),
      );

      _deviceOffset = offset;
      _isSynced = true;

      print('--- NTP 同步成功! 当前偏移量: $_deviceOffset ms ---');
      print('--- 修正后时间: ${now.toIso8601String()} ---');
    } catch (e) {
      print('--- NTP 同步失败: $e ---');
      _isSynced = false;
      Future.delayed(const Duration(seconds: 30), () => syncTime());
    }
  }

  /// 启动定时同步任务
  /// 
  /// 建议每小时执行一次，防止系统时钟漂移。
  /// 立即执行一次同步，然后每小时重复。
  void startPeriodicSync() {
    syncTime();
    Timer.periodic(const Duration(hours: 1), (timer) {
      syncTime();
    });
  }
}
