import '../../models/quake_message.dart';
import '../../models/unified_quake_data.dart';
import '../../services/ntp_service.dart';

/// 地震时间处理工具类
///
/// 该类提供地震事件时间相关的处理功能。
/// 主要处理不同数据源的时间偏移和显示问题。
///
/// 主要功能：
/// - 判断数据源是否为日本数据源
/// - 获取目标时区偏移
/// - 标准化发震时刻
/// - 格式化显示时间
///
/// 时区说明：
/// - UTC+8: 中国标准时间 (北京时间)
/// - UTC+9: 日本标准时间 (东京时间)
class QuakeTime {
  /// UTC+8 时区偏移 (中国标准时间)
  static const Duration _utc8 = Duration(hours: 8);

  /// UTC+9 时区偏移 (日本标准时间)
  static const Duration _utc9 = Duration(hours: 9);

  /// 判断数据源是否为日本数据源
  ///
  /// 日本数据源包括:
  /// - wolfx: Wolfx JMA数据
  /// - nied: NIED强震数据
  /// - p2p: P2PQuake数据
  /// - jma_fan: FanStudio JMA数据
  ///
  /// 韩国数据源也使用UTC+9时区:
  /// - kma_eq: 韩国气象厅地震信息
  /// - kma_eew_fan: 韩国气象厅地震预警
  ///
  /// [source] 数据源类型
  /// 返回是否为日本/韩国数据源（UTC+9时区）
  static bool isJapanSource(QuakeSourceType source) {
    switch (source) {
      case QuakeSourceType.wolfx:
      case QuakeSourceType.nied:
      case QuakeSourceType.p2p:
      case QuakeSourceType.jma_fan:
      case QuakeSourceType.jmaCmt:
      case QuakeSourceType.fnetCmt:
      case QuakeSourceType.hinetAquaCmt:
      case QuakeSourceType.kma_eq:
      case QuakeSourceType.kma_eew_fan:
        return true;
      default:
        return false;
    }
  }

  /// 获取目标时区偏移
  ///
  /// 根据数据源返回对应的时区偏移。
  /// - 日本数据源: UTC+9
  /// - 其他数据源: UTC+8
  ///
  /// [event] 地震事件
  /// 返回时区偏移
  static Duration targetOffset(QuakeMessage event) {
    return isJapanSource(event.source) ? _utc9 : _utc8;
  }

  /// 获取时区标签
  ///
  /// 用于在UI上显示时区信息。
  ///
  /// [event] 地震事件
  /// 返回时区标签字符串 (如 "UTC+8", "UTC+9")
  static String zoneLabel(QuakeMessage event) {
    return isJapanSource(event.source) ? 'UTC+9' : 'UTC+8';
  }

  /// 标准化发震时刻
  ///
  /// 将原始数据中的发震时刻转换为标准化的本地时间。
  ///
  /// 处理逻辑:
  /// 1. 原始数据中的时间被视为数据源本地时间
  /// 2. 将其转换为UTC时间
  /// 3. 再转换为系统本地时间
  ///
  /// 这样可以正确处理不同时区的地震数据。
  ///
  /// [event] 地震事件
  /// 返回标准化后的本地发震时刻
  static DateTime normalizedOriginLocal(QuakeMessage event) {
    final t = event.originTime;
    final utcInstant = DateTime.utc(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute,
      t.second,
      t.millisecond,
      t.microsecond,
    ).subtract(targetOffset(event));
    return utcInstant.toLocal();
  }

  /// 获取显示用时钟时间
  ///
  /// 将标准化后的时间转换为数据源本地时区的时间，
  /// 用于在UI上显示。
  ///
  /// [event] 地震事件
  /// 返回数据源本地时区的显示时间
  static DateTime displayClock(QuakeMessage event) {
    return normalizedOriginLocal(event).toUtc().add(targetOffset(event));
  }

  /// 计算从报告发布时间到当前已过去的时间（秒）
  ///
  /// 对齐 kanameishi-dev 的 calcPassedTime 逻辑：
  /// 1. reportTime/originTime 是数据源本地时间字符串解析而来
  /// 2. 需要减去时区偏移转为 UTC 时间戳
  /// 3. 再与当前 UTC 时间比较
  static int calcPassedSeconds(QuakeMessage event) {
    final refTime = event.reportTime ?? event.originTime;
    return _calcPassedSecondsFromDateTime(refTime, targetOffset(event));
  }

  /// 计算统一事件的已过去时间（秒）
  static int calcPassedSecondsUnified(UnifiedQuakeData event) {
    final refTime = event.originTime;
    if (refTime == null) return 0;
    // 使用适配器中写入的 timeZone 字段，比字符串匹配更准确
    final offset = Duration(hours: event.timeZone);
    return _calcPassedSecondsFromDateTime(refTime, offset);
  }

  /// 计算统一事件从指定时间起已过去的秒数
  /// 参照 kanameishi 的 calcPassedTime(reportTime, timeZone) 逻辑
  static int calcPassedSecondsFromDateTime(
    DateTime refTime,
    Duration tzOffset,
  ) {
    return _calcPassedSecondsFromDateTime(refTime, tzOffset);
  }

  /// Current-card lifetime reference for a non-EEW unified event.
  ///
  /// WHEWS EMSC can publish a recent directory revision for an earthquake that
  /// occurred much earlier. Its updateTime remains useful for ordering
  /// revisions, but must not revive that old earthquake in the current UI or
  /// background notifications. Other sources retain the existing report-time
  /// display-window behavior.
  static DateTime? informationDisplayReference(UnifiedQuakeData event) {
    final isWhewsEmsc =
        event.apiTypeLabel == 'WHEWS' &&
        (event.source == 'emsc' || event.source == 'emscEqlist');
    if (isWhewsEmsc && event.originTime != null) return event.originTime;
    return event.reportTime ?? event.originTime;
  }

  /// 内部：从 DateTime 计算已过去秒数
  static int _calcPassedSecondsFromDateTime(
    DateTime refTime,
    Duration tzOffset,
  ) {
    // 将 DateTime 视为数据源本地时间，转为 UTC
    final utcInstant = DateTime.utc(
      refTime.year,
      refTime.month,
      refTime.day,
      refTime.hour,
      refTime.minute,
      refTime.second,
      refTime.millisecond,
      refTime.microsecond,
    ).subtract(tzOffset);
    final elapsed = NtpService().now.toUtc().difference(utcInstant);
    return elapsed.inSeconds.clamp(0, 999999);
  }

  /// 计算 EEW 预警总超时时间（秒）
  ///
  /// 对齐 kanameishi-dev 的过期策略：
  /// - 取消报：20秒
  /// - 警报级 (isWarn)：max(震级, 6) * 60 秒
  /// - 普通：max(震级, 3) * 60 秒
  static int eewTimeoutSeconds(QuakeMessage event) {
    if (event.isCanceled) return 20;
    final mag = event.magnitude;
    if (event.isWarn) return ((mag > 6 ? mag : 6) * 60).ceil();
    return ((mag > 3 ? mag : 3) * 60).ceil();
  }

  /// 计算统一事件的 EEW 超时时间（秒）
  static int eewTimeoutSecondsUnified(UnifiedQuakeData event) {
    if (event.isCanceled) return 20;
    final mag = event.magnitude;
    if (event.isWarn) return ((mag > 6 ? mag : 6) * 60).ceil();
    return ((mag > 3 ? mag : 3) * 60).ceil();
  }
}
