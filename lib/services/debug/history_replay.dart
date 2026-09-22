import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/utils/quake_time.dart';
import '../../models/eew_event_group.dart';
import '../../models/unified_quake_data.dart';
import '../ntp_service.dart';
import '../quake_event_adapter.dart';

class HistoryReplayPackage {
  static const format = 'rhythmquake-replay';
  static const version = 1;
  static const maxBytes = 16 * 1024 * 1024;
  static const maxReports = 1000;
  static const maxDuration = Duration(days: 1);

  final String name;
  final List<UnifiedQuakeData> reports;
  final List<DateTime> times;
  final int omittedReports;
  final bool manualTiming;

  HistoryReplayPackage._(
    this.name,
    this.reports,
    this.times,
    this.omittedReports,
    this.manualTiming,
  );

  static bool hasPayload(UnifiedQuakeData event) =>
      event.sourcePayload?.isNotEmpty == true;

  factory HistoryReplayPackage.fromGroup(EewEventGroup group) {
    final saved = group.reports.where(hasPayload).toList();
    return HistoryReplayPackage._validated(
      group.latest.hypocenter,
      saved,
      group.reports.length - saved.length,
    );
  }

  static DateTime? reportInstant(UnifiedQuakeData event) {
    if (event.reportTime != null) {
      return QuakeTime.unifiedInstantUtc(event, value: event.reportTime);
    }
    final rawTime = QuakeEventAdapter.savedReportTime(
      event.sourcePayload!,
      event.timeZone,
    );
    if (rawTime != null) {
      return QuakeTime.unifiedInstantUtc(event, value: rawTime);
    }
    if (event.arrivedAt != null) return event.arrivedAt!.toUtc();
    return null;
  }

  factory HistoryReplayPackage._validated(
    String name,
    List<UnifiedQuakeData> reports,
    int omitted,
  ) {
    if (reports.isEmpty || reports.length > maxReports || omitted < 0) {
      throw const FormatException('回放报文数量无效');
    }
    for (final event in reports) {
      if (!hasPayload(event) ||
          event.isEmpty ||
          event.source.isEmpty ||
          event.eventId.isEmpty ||
          event.timeZone < -12 ||
          event.timeZone > 14 ||
          !event.magnitude.isFinite ||
          !event.depth.isFinite ||
          (event.lat != null &&
              (!event.lat!.isFinite || event.lat!.abs() > 90)) ||
          (event.lng != null &&
              (!event.lng!.isFinite || event.lng!.abs() > 180))) {
        throw const FormatException('回放报文缺少原始数据或事件字段无效');
      }
    }
    final manual = reports.any((e) => reportInstant(e) == null);
    int reportNumber(UnifiedQuakeData event) =>
        int.tryParse(
          RegExp(r'\d+').firstMatch(event.reportNumText)?.group(0) ?? '',
        ) ??
        0;
    final indexed = reports.indexed.toList()
      ..sort((a, b) {
        final time = manual
            ? 0
            : reportInstant(a.$2)!.compareTo(reportInstant(b.$2)!);
        if (time != 0) return time;
        final number = reportNumber(a.$2).compareTo(reportNumber(b.$2));
        return number == 0 ? a.$1.compareTo(b.$1) : number;
      });
    final ordered = indexed.map((item) => item.$2).toList();
    final times = manual
        ? List.filled(
            ordered.length,
            QuakeTime.unifiedInstantUtc(ordered.first),
          )
        : ordered.map((e) => reportInstant(e)!).toList();
    if (times.last.difference(times.first) > maxDuration) {
      throw const FormatException('单个回放包跨度不能超过 24 小时');
    }
    return HistoryReplayPackage._(
      name,
      List.unmodifiable(ordered),
      List.unmodifiable(times),
      omitted,
      manual,
    );
  }

  Duration get duration => times.last.difference(times.first);

  String encode() {
    final text = jsonEncode({
      'format': format,
      'version': version,
      'name': name,
      'omittedReports': omittedReports,
      'reports': reports.map((e) => e.toMap()).toList(),
    });
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('回放包超过 16 MiB');
    }
    return text;
  }

  factory HistoryReplayPackage.decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('回放包超过 16 MiB');
    }
    try {
      final value = jsonDecode(text);
      if (value is! Map<String, dynamic> ||
          value['format'] != format ||
          value['version'] != version ||
          value['reports'] is! List ||
          value['name'] is! String ||
          value['omittedReports'] is! int) {
        throw const FormatException('不是受支持的 RhythmQuake 回放包');
      }
      final reports = value['reports'] as List;
      if (reports.length > maxReports) {
        throw const FormatException('回放报文过多');
      }
      return HistoryReplayPackage._validated(
        value['name'],
        reports
            .map(
              (e) =>
                  UnifiedQuakeData.fromMap(Map<String, dynamic>.from(e as Map)),
            )
            .toList(),
        value['omittedReports'],
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('回放包结构或事件字段无效');
    }
  }
}

/// Plays accepted historical snapshots, not new upstream deliveries. The raw
/// bodies and displayed source times remain unchanged; only the map clock shifts.
class HistoryReplayController extends ChangeNotifier {
  final void Function(UnifiedQuakeData) onReport;
  final void Function(String) onClear;
  final DateTime Function() now;
  HistoryReplayController({
    required this.onReport,
    required this.onClear,
    DateTime Function()? now,
  }) : now = now ?? (() => NtpService().now.toUtc());

  HistoryReplayPackage? _package;
  HistoryReplayPackage? get package => _package;
  String? _session;
  Timer? _timer;
  VoidCallback? _advance;
  int _sequence = 0;
  int played = 0;
  bool get active => _session != null;
  bool get holding => active && played == package?.reports.length;

  void load(HistoryReplayPackage value) {
    stop();
    _package = value;
    played = 0;
    notifyListeners();
  }

  void play() {
    final value = package;
    if (value == null) return;
    stop();
    final started = now();
    final session = 'replay-${started.microsecondsSinceEpoch}-${++_sequence}';
    _session = session;
    played = 0;
    final clockOffset = started.difference(value.times.first);
    void deliver() {
      if (_session != session) return;
      final report = value.reports[played];
      onReport(
        report.copyWith(
          eventId: '$session:${report.eventId}',
          replaySessionId: session,
          replayClockOffset: clockOffset,
          arrivedAt: now(),
          isHistory: false,
          isSnapshot: false,
          apiTypeLabel: '本地注入 · 回放',
        ),
      );
      if (_session != session) return;
      played++;
      notifyListeners();
      if (_session != session) return;
      if (played == value.reports.length) {
        _timer = Timer(const Duration(seconds: 30), stop);
      } else if (!value.manualTiming) {
        final due = started.add(
          value.times[played].difference(value.times.first),
        );
        final delay = due.difference(now());
        _timer = Timer(delay.isNegative ? Duration.zero : delay, deliver);
      }
    }

    _advance = deliver;
    deliver();
  }

  void next() {
    if (active && package!.manualTiming && !holding) _advance?.call();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _advance = null;
    final session = _session;
    _session = null;
    if (session != null) {
      onClear(session);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _advance = null;
    _session = null;
    super.dispose();
  }
}
