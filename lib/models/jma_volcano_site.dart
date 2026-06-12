class JmaVolcanoSite {
  final String code;
  final String nameJp;
  final String nameEn;
  final double latitude;
  final double longitude;
  final bool levelOperation;
  final int alertLevel;
  final bool hasWarning;
  final bool hasRecentInfo;
  final bool hasRecentEruption;
  final String? warningKindCode;
  final String? warningKindName;
  final String? warningAlarm;
  final DateTime? warningReportTime;
  final String? infoHeadTitle;
  final DateTime? infoReportTime;
  final DateTime? eruptionReportTime;

  const JmaVolcanoSite({
    required this.code,
    required this.nameJp,
    required this.nameEn,
    required this.latitude,
    required this.longitude,
    required this.levelOperation,
    required this.alertLevel,
    required this.hasWarning,
    required this.hasRecentInfo,
    required this.hasRecentEruption,
    this.warningKindCode,
    this.warningKindName,
    this.warningAlarm,
    this.warningReportTime,
    this.infoHeadTitle,
    this.infoReportTime,
    this.eruptionReportTime,
  });

  String get displayName {
    final jp = nameJp.trim();
    if (jp.isNotEmpty && !jp.contains('\uFFFD')) return jp;
    final en = nameEn.trim();
    if (en.isNotEmpty) return en;
    return jp.isNotEmpty ? jp : code;
  }

  bool get hasFreshInfoOverlay {
    if (!hasRecentInfo) return false;
    if (warningReportTime == null) return true;
    if (infoReportTime == null) return false;
    return infoReportTime!.isAfter(warningReportTime!);
  }

  DateTime? get latestReportTime {
    DateTime? latest = warningReportTime;
    if (infoReportTime != null &&
        (latest == null || infoReportTime!.isAfter(latest))) {
      latest = infoReportTime;
    }
    if (eruptionReportTime != null &&
        (latest == null || eruptionReportTime!.isAfter(latest))) {
      latest = eruptionReportTime;
    }
    return latest;
  }

  String get statusLabel {
    if (hasRecentEruption) return '噴火速報';
    if (alertLevel >= 4) return '噴火警報';
    if (alertLevel >= 2) return '火口周辺火山警報';
    if (alertLevel == 1) return '火山予報';
    if (warningKindName != null && warningKindName!.trim().isNotEmpty) {
      return warningKindName!.trim();
    }
    if (hasRecentInfo) return '火山の状況に関する解説情報';
    return '火山予報';
  }

  String? get detailText {
    if (warningAlarm != null && warningAlarm!.trim().isNotEmpty) {
      return warningAlarm!.trim();
    }
    if (infoHeadTitle != null && infoHeadTitle!.trim().isNotEmpty) {
      return infoHeadTitle!.trim();
    }
    return null;
  }
}
