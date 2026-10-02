import 'unified_quake_data.dart';
import 'station_history_frame.dart';

class EewEventGroup {
  final String eventId;
  final List<UnifiedQuakeData> reports;
  final DateTime firstArrivedAt;
  final List<StationHistoryFrame> stationFrames;
  final DateTime? captureEndedAt;

  EewEventGroup({
    required this.eventId,
    required this.reports,
    required this.firstArrivedAt,
    this.stationFrames = const [],
    this.captureEndedAt,
  });

  UnifiedQuakeData get latest => reports.first;

  int get reportCount => reports.length;

  /// 当前事件已推进到的最高报号；与实际保存的去重后列表长度区分。
  int get latestReportNumber {
    final match = RegExp(r'(?:第\s*)?(\d+)').firstMatch(latest.reportNumText);
    return int.tryParse(match?.group(1) ?? '') ?? reportCount;
  }

  bool get isCanceled => latest.isCanceled;

  Map<String, dynamic> toMap({bool includeStationFrames = true}) => {
    'eventId': eventId,
    'firstArrivedAt': firstArrivedAt.toIso8601String(),
    'reports': reports.map((report) => report.toMap()).toList(),
    if (includeStationFrames && stationFrames.isNotEmpty)
      'stationFrames': stationFrames.map((frame) => frame.toMap()).toList(),
    if (captureEndedAt != null)
      'captureEndedAt': captureEndedAt!.toUtc().toIso8601String(),
  };

  factory EewEventGroup.fromMap(Map<dynamic, dynamic> map) {
    DateTime? parseTime(Object? value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : DateTime.tryParse(text);
    }

    final reports = (map['reports'] is List ? map['reports'] as List : const [])
        .whereType<Map>()
        .map(
          (report) =>
              UnifiedQuakeData.fromMap(Map<String, dynamic>.from(report)),
        )
        .toList();
    if (reports.isEmpty) {
      throw const FormatException('EEW history group has no reports');
    }

    final firstArrivedAt =
        parseTime(map['firstArrivedAt']) ??
        reports.last.arrivedAt ??
        reports.last.reportTime ??
        DateTime.now();
    return EewEventGroup(
      eventId: map['eventId']?.toString() ?? reports.last.eventId,
      reports: reports,
      firstArrivedAt: firstArrivedAt,
      stationFrames: (map['stationFrames'] as List? ?? const [])
          .map((frame) => StationHistoryFrame.fromMap(frame as Map))
          .toList(),
      captureEndedAt: parseTime(map['captureEndedAt']),
    );
  }

  EewEventGroup addReport(UnifiedQuakeData newReport) {
    final existingIndex = reports.indexWhere(
      (r) => r.source == 'iclEew' && newReport.source == 'iclEew'
          ? _reportSortKey(r) == _reportSortKey(newReport)
          : r.reportNumText == newReport.reportNumText,
    );
    final updated = List<UnifiedQuakeData>.from(reports);
    if (existingIndex >= 0) {
      if (newReport.source == 'iclEew' &&
          updated[existingIndex].source == 'iclEew') {
        return this;
      }
      updated[existingIndex] = newReport;
    } else {
      updated.insert(0, newReport);
    }
    updated.sort((a, b) {
      return _reportSortKey(b).compareTo(_reportSortKey(a));
    });
    return EewEventGroup(
      eventId: eventId,
      reports: updated,
      firstArrivedAt: firstArrivedAt,
      stationFrames: stationFrames,
      captureEndedAt: captureEndedAt,
    );
  }

  int _reportSortKey(UnifiedQuakeData r) {
    final text = r.reportNumText;
    final match = RegExp(r'第(\d+)').firstMatch(text);
    if (match != null) return int.tryParse(match.group(1) ?? '0') ?? 0;
    return 0;
  }

  EewEventGroup copyWith({
    String? eventId,
    List<UnifiedQuakeData>? reports,
    DateTime? firstArrivedAt,
    List<StationHistoryFrame>? stationFrames,
    DateTime? captureEndedAt,
  }) {
    return EewEventGroup(
      eventId: eventId ?? this.eventId,
      reports: reports ?? this.reports,
      firstArrivedAt: firstArrivedAt ?? this.firstArrivedAt,
      stationFrames: stationFrames ?? this.stationFrames,
      captureEndedAt: captureEndedAt ?? this.captureEndedAt,
    );
  }
}
