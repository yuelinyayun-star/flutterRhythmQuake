import 'unified_quake_data.dart';

class EewEventGroup {
  final String eventId;
  final List<UnifiedQuakeData> reports;
  final DateTime firstArrivedAt;

  EewEventGroup({
    required this.eventId,
    required this.reports,
    required this.firstArrivedAt,
  });

  UnifiedQuakeData get latest => reports.first;

  int get reportCount => reports.length;

  /// 当前事件已推进到的最高报号；与实际保存的去重后列表长度区分。
  int get latestReportNumber {
    final match = RegExp(r'(?:第\s*)?(\d+)').firstMatch(latest.reportNumText);
    return int.tryParse(match?.group(1) ?? '') ?? reportCount;
  }

  bool get isCanceled => latest.isCanceled;

  Map<String, dynamic> toMap() => {
    'eventId': eventId,
    'firstArrivedAt': firstArrivedAt.toIso8601String(),
    'reports': reports.map((report) => report.toMap()).toList(),
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
    );
  }

  EewEventGroup addReport(UnifiedQuakeData newReport) {
    final existingIndex = reports.indexWhere(
      (r) => r.reportNumText == newReport.reportNumText,
    );
    final updated = List<UnifiedQuakeData>.from(reports);
    if (existingIndex >= 0) {
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
  }) {
    return EewEventGroup(
      eventId: eventId ?? this.eventId,
      reports: reports ?? this.reports,
      firstArrivedAt: firstArrivedAt ?? this.firstArrivedAt,
    );
  }
}
