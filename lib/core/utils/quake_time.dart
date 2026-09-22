import '../../models/quake_message.dart';
import '../../models/whews_catalog.dart';
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
    return Duration(
      hours: event.timeZone ?? wallClockOffsetHours(event.source),
    );
  }

  /// Source wall-clock offset hours used by adapters / inject rewrites.
  /// JMA/KMA (+NIED/P2P) → 9; everything else (CEA/CENC/USGS/CWA/…) → 8.
  static int wallClockOffsetHours(QuakeSourceType source) {
    return isJapanSource(source) ? 9 : 8;
  }

  /// 当前设备时区。来源字段的偏移仍由适配器明确提供，这个值只用于
  /// 绝对时间的本地显示以及没有来源墙钟、直接使用 epoch/ISO 的源。
  static Duration get systemTimeZoneOffset => DateTime.now().timeZoneOffset;

  static int get systemTimeZoneHours => systemTimeZoneOffset.inMinutes ~/ 60;

  static String formatTimeZone(Duration offset) {
    final totalMinutes = offset.inMinutes;
    final sign = totalMinutes >= 0 ? '+' : '-';
    final absolute = totalMinutes.abs();
    final hours = absolute ~/ 60;
    final minutes = absolute % 60;
    return minutes == 0
        ? 'UTC$sign$hours'
        : 'UTC$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }

  static String get systemZoneLabel => formatTimeZone(systemTimeZoneOffset);

  /// 将来源墙上时间还原成绝对 UTC 时间。不能直接调用 DateTime.toUtc，
  /// 因为这里的 DateTime 仅承载日期时间分量，不承载来源时区。
  static DateTime wallClockToUtc(DateTime value, Duration offset) {
    return DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    ).subtract(offset);
  }

  static DateTime eventInstantUtc(QuakeMessage event, {DateTime? value}) {
    return wallClockToUtc(value ?? event.originTime, targetOffset(event));
  }

  static DateTime unifiedInstantUtc(UnifiedQuakeData event, {DateTime? value}) {
    final time = value ?? event.originTime;
    if (time == null) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return wallClockToUtc(time, Duration(hours: event.timeZone));
  }

  static DateTime unifiedDisplayClock(UnifiedQuakeData event) {
    final utc = unifiedInstantUtc(event);
    final display = utc.add(Duration(hours: event.timeZone));
    return _asWallClock(display);
  }

  static String formatSourceClockInSystem(
    DateTime? value,
    int sourceTimeZone, {
    bool includeSeconds = true,
    bool includeZoneLabel = true,
  }) {
    if (value == null) return '--:--:--';
    final display = wallClockToUtc(
      value,
      Duration(hours: sourceTimeZone),
    ).toLocal();
    final clock = formatWallClock(display, includeSeconds: includeSeconds);
    return includeZoneLabel ? '$clock ($systemZoneLabel)' : clock;
  }

  /// 获取时区标签
  ///
  /// 用于在UI上显示时区信息。
  ///
  /// [event] 地震事件
  /// 返回时区标签字符串 (如 "UTC+8", "UTC+9")
  static String zoneLabel(QuakeMessage event) {
    return formatTimeZone(targetOffset(event));
  }

  /// Unified-event timezone label from adapter [UnifiedQuakeData.timeZone].
  static String unifiedZoneLabel(UnifiedQuakeData event) {
    return formatTimeZone(Duration(hours: event.timeZone));
  }

  /// Format a source wall-clock [DateTime] stored by adapters (component values).
  static String formatWallClock(
    DateTime? time, {
    int? timeZone,
    bool includeSeconds = true,
    bool includeZoneLabel = false,
  }) {
    if (time == null) return '--:--:--';
    final y = time.year.toString().padLeft(4, '0');
    final mo = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final mi = time.minute.toString().padLeft(2, '0');
    final clock = includeSeconds
        ? '$y-$mo-$d $h:$mi:${time.second.toString().padLeft(2, '0')}'
        : '$y-$mo-$d $h:$mi';
    if (!includeZoneLabel || timeZone == null) return clock;
    return '$clock (${formatTimeZone(Duration(hours: timeZone))})';
  }

  /// Display text for unified event origin time.
  static String formatUnifiedOriginClock(
    UnifiedQuakeData event, {
    bool includeSeconds = true,
    bool includeZoneLabel = true,
  }) {
    if (event.originTime == null) return '--:--:--';
    final display = unifiedDisplayClock(event);
    final clock = formatWallClock(display, includeSeconds: includeSeconds);
    final zone = formatTimeZone(Duration(hours: event.timeZone));
    return includeZoneLabel ? '$clock ($zone)' : clock;
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
    return eventInstantUtc(event).toLocal();
  }

  /// 获取显示用时钟时间
  ///
  /// 将标准化后的时间转换为数据源本地时区的时间，
  /// 用于在UI上显示。
  ///
  /// [event] 地震事件
  /// 返回数据源本地时区的显示时间
  static DateTime displayClock(QuakeMessage event) {
    final utc = eventInstantUtc(event);
    final display = utc.add(targetOffset(event));
    return _asWallClock(display);
  }

  static DateTime _asWallClock(DateTime value) {
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
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
    if (refTime == null) return event.useSourceTimeForExpiry ? 999999 : 0;
    // 使用适配器中写入的 timeZone 字段，比字符串匹配更准确
    final offset = Duration(hours: event.timeZone);
    if (event.isReplay) {
      final instant = wallClockToUtc(refTime, offset);
      return NtpService().now.toUtc().subtract(event.replayClockOffset)
          .difference(instant).inSeconds.clamp(0, 999999);
    }
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
  /// background notifications. Catalog snapshots use the earthquake time;
  /// live catalog admission/display is handled by the separate helper below.
  static DateTime? informationDisplayReference(UnifiedQuakeData event) {
    // Catalog maintenance must not turn an old earthquake into a new alert.
    if (unifiedCatalogSources.containsKey(event.source)) return event.originTime;
    final isWhewsEmsc =
        event.apiTypeLabel == 'WHEWS' &&
        (event.source == 'emsc' || event.source == 'emscEqlist');
    if (isWhewsEmsc && event.originTime != null) return event.originTime;
    return event.reportTime ?? event.originTime;
  }

  /// Product policy for delayed live catalogs, not a provider timestamp rule.
  static const catalogLiveAdmissionWindow = Duration(minutes: 30);

  /// Returns null for feeds whose existing lifetime rules must stay unchanged.
  /// Source age controls admission; local first arrival controls card lifetime.
  static int? catalogInformationRemainingSeconds(
    UnifiedQuakeData event,
    int displaySeconds, {
    DateTime? firstArrivedAt,
    DateTime? now,
    DateTime? sourceNow,
  }) {
    if (event.isEew || !unifiedCatalogSources.containsKey(event.source)) {
      return null;
    }
    if (event.isHistory ||
        event.originTime == null ||
        event.eventId.trim().isEmpty) {
      return 0;
    }
    final sourceAge = (sourceNow ?? NtpService().now)
        .toUtc()
        .difference(
          wallClockToUtc(event.originTime!, Duration(hours: event.timeZone)),
        )
        .inSeconds
        .clamp(0, 999999);
    // Initial/reconnect snapshots retain the original, source-time window.
    if (event.isSnapshot) return displaySeconds - sourceAge;
    final arrival = firstArrivedAt ?? event.arrivedAt;
    final elapsed = arrival == null
        ? 0
        : (now ?? DateTime.now())
              .toUtc()
              .difference(arrival.toUtc())
              .inSeconds
              .clamp(0, 999999);
    if (sourceAge - elapsed >= catalogLiveAdmissionWindow.inSeconds) return 0;
    return displaySeconds - elapsed;
  }

  /// 内部：从 DateTime 计算已过去秒数
  static int _calcPassedSecondsFromDateTime(
    DateTime refTime,
    Duration tzOffset,
  ) {
    // 将 DateTime 视为数据源本地时间，转为 UTC
    final utcInstant = wallClockToUtc(refTime, tzOffset);
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
