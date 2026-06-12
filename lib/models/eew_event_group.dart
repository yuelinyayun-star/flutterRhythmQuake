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

  bool get isCanceled => latest.isCanceled;

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
