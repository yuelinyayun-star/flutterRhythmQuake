class VolcanoWindProfile {
  final double? heightFt;
  final double? degree;
  final double? speedKt;

  const VolcanoWindProfile({this.heightFt, this.degree, this.speedKt});
}

/// JMA 原始降灰范围点。经纬度值不投影、不抽稀，地图直接按官方顺序绘制。
class VolcanoAshfallCoordinate {
  final double latitude;
  final double longitude;

  const VolcanoAshfallCoordinate({
    required this.latitude,
    required this.longitude,
  });

  bool sameAs(VolcanoAshfallCoordinate other) =>
      (latitude - other.latitude).abs() < 0.0000001 &&
      (longitude - other.longitude).abs() < 0.0000001;
}

/// JMA AshInfo 下的一种预报现象，例如降灰或小さな噴石の落下。
class VolcanoAshfallItem {
  final String phenomenon;
  final String phenomenonCode;
  final List<String> areaNames;
  final List<String> areaCodes;
  final String plumeDirection;
  final double? distanceKm;
  final double? sizeCm;
  final List<List<VolcanoAshfallCoordinate>> polygons;

  const VolcanoAshfallItem({
    required this.phenomenon,
    required this.phenomenonCode,
    required this.areaNames,
    required this.areaCodes,
    required this.plumeDirection,
    required this.polygons,
    this.distanceKm,
    this.sizeCm,
  });

  bool sameAs(VolcanoAshfallItem other) {
    if (phenomenon != other.phenomenon ||
        phenomenonCode != other.phenomenonCode ||
        plumeDirection != other.plumeDirection ||
        distanceKm != other.distanceKm ||
        sizeCm != other.sizeCm ||
        !_sameStrings(areaNames, other.areaNames) ||
        !_sameStrings(areaCodes, other.areaCodes) ||
        polygons.length != other.polygons.length) {
      return false;
    }
    for (var polygonIndex = 0; polygonIndex < polygons.length; polygonIndex++) {
      final current = polygons[polygonIndex];
      final candidate = other.polygons[polygonIndex];
      if (current.length != candidate.length) return false;
      for (var pointIndex = 0; pointIndex < current.length; pointIndex++) {
        if (!current[pointIndex].sameAs(candidate[pointIndex])) return false;
      }
    }
    return true;
  }
}

/// JMA AshInfo 的一个官方预报时间窗。
class VolcanoAshfallWindow {
  final String label;
  final DateTime? startTime;
  final DateTime? endTime;
  final List<VolcanoAshfallItem> items;

  const VolcanoAshfallWindow({
    required this.label,
    required this.items,
    this.startTime,
    this.endTime,
  });

  bool contains(DateTime now) {
    final current = now.toUtc();
    final start = startTime?.toUtc();
    final end = endTime?.toUtc();
    return (start == null || !current.isBefore(start)) &&
        (end == null || !current.isAfter(end));
  }

  bool isUpcoming(DateTime now) {
    final start = startTime?.toUtc();
    return start != null && start.isAfter(now.toUtc());
  }

  bool sameAs(VolcanoAshfallWindow other) {
    if (label != other.label ||
        startTime?.toUtc() != other.startTime?.toUtc() ||
        endTime?.toUtc() != other.endTime?.toUtc() ||
        items.length != other.items.length) {
      return false;
    }
    for (var index = 0; index < items.length; index++) {
      if (!items[index].sameAs(other.items[index])) return false;
    }
    return true;
  }
}

/// 原样承载 WHEWS JMA 火山电文的专属字段。
///
/// 火山电文不是地震速报，不能挪用震级、深度或烈度字段表示这些信息。
class VolcanoEventData {
  final int updates;
  final String kindCode;
  final String kindName;
  final String infoKind;
  final String infoTypeName;
  final String title;
  final String volcanoName;
  final String volcanoCode;
  final double? latitude;
  final double? longitude;
  final double? elevation;
  final String craterName;
  final String headline;
  final String activity;
  final String prevention;
  final String nextAdvisory;
  final String plumeDirection;
  final double? plumeHeight;
  final double? plumeHeightSea;
  final String observation;
  final DateTime? reportTime;
  final DateTime? targetTime;
  final DateTime? windTime;
  final List<VolcanoWindProfile> winds;
  final String publishingOffice;
  final List<VolcanoAshfallWindow> ashfallWindows;

  const VolcanoEventData({
    required this.updates,
    required this.kindCode,
    required this.kindName,
    required this.infoKind,
    required this.infoTypeName,
    required this.title,
    required this.volcanoName,
    required this.volcanoCode,
    required this.craterName,
    required this.headline,
    required this.activity,
    required this.prevention,
    required this.nextAdvisory,
    required this.plumeDirection,
    required this.observation,
    required this.winds,
    required this.publishingOffice,
    this.ashfallWindows = const [],
    this.latitude,
    this.longitude,
    this.elevation,
    this.plumeHeight,
    this.plumeHeightSea,
    this.reportTime,
    this.targetTime,
    this.windTime,
  });

  bool get hasMapLocation =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude != 0 &&
      longitude != 0;

  bool get isCanceled => infoTypeName.trim() == '取消';

  bool get isAshfallForecast =>
      kindCode == 'VFVO53' || kindCode == 'VFVO54' || kindCode == 'VFVO55';

  bool get hasAshfallForecast => ashfallWindows.isNotEmpty;

  VolcanoAshfallWindow? displayAshfallWindow({DateTime? now}) {
    if (ashfallWindows.isEmpty) return null;
    final current = now ?? DateTime.now();
    for (final window in ashfallWindows) {
      if (window.contains(current)) return window;
    }
    for (final window in ashfallWindows) {
      if (window.isUpcoming(current)) return window;
    }
    return ashfallWindows.last;
  }

  VolcanoAshfallWindow? mapAshfallWindow({DateTime? now}) {
    if (ashfallWindows.isEmpty) return null;
    final current = now ?? DateTime.now();
    for (final window in ashfallWindows) {
      if (window.contains(current)) return window;
    }
    for (final window in ashfallWindows) {
      if (window.isUpcoming(current)) return window;
    }
    return null;
  }

  String get displayLocation {
    final volcano = volcanoName.trim();
    final crater = craterName.trim();
    if (volcano.isEmpty) return crater;
    if (crater.isEmpty) return volcano;
    return '$volcano $crater';
  }

  String get displayDetail {
    final ashfall = displayAshfallWindow();
    if (ashfall != null) return _formatAshfallSummary(ashfall);
    for (final value in [headline, activity, observation, prevention]) {
      final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (compact.isNotEmpty) return compact;
    }
    final direction = plumeDirection.trim();
    final height = plumeHeight;
    if (direction.isNotEmpty && height != null && height > 0) {
      return '噴煙 $direction ${height.round()}m';
    }
    if (direction.isNotEmpty) return '噴煙 $direction';
    if (height != null && height > 0) return '噴煙 ${height.round()}m';
    return kindName.trim();
  }

  VolcanoEventData copyWith({List<VolcanoAshfallWindow>? ashfallWindows}) {
    return VolcanoEventData(
      updates: updates,
      kindCode: kindCode,
      kindName: kindName,
      infoKind: infoKind,
      infoTypeName: infoTypeName,
      title: title,
      volcanoName: volcanoName,
      volcanoCode: volcanoCode,
      latitude: latitude,
      longitude: longitude,
      elevation: elevation,
      craterName: craterName,
      headline: headline,
      activity: activity,
      prevention: prevention,
      nextAdvisory: nextAdvisory,
      plumeDirection: plumeDirection,
      plumeHeight: plumeHeight,
      plumeHeightSea: plumeHeightSea,
      observation: observation,
      reportTime: reportTime,
      targetTime: targetTime,
      windTime: windTime,
      winds: winds,
      publishingOffice: publishingOffice,
      ashfallWindows: ashfallWindows ?? this.ashfallWindows,
    );
  }

  bool sameAs(VolcanoEventData other) {
    if (updates != other.updates ||
        kindCode != other.kindCode ||
        kindName != other.kindName ||
        infoKind != other.infoKind ||
        infoTypeName != other.infoTypeName ||
        title != other.title ||
        volcanoName != other.volcanoName ||
        volcanoCode != other.volcanoCode ||
        latitude != other.latitude ||
        longitude != other.longitude ||
        elevation != other.elevation ||
        craterName != other.craterName ||
        headline != other.headline ||
        activity != other.activity ||
        prevention != other.prevention ||
        nextAdvisory != other.nextAdvisory ||
        plumeDirection != other.plumeDirection ||
        plumeHeight != other.plumeHeight ||
        plumeHeightSea != other.plumeHeightSea ||
        observation != other.observation ||
        reportTime?.toUtc() != other.reportTime?.toUtc() ||
        targetTime?.toUtc() != other.targetTime?.toUtc() ||
        windTime?.toUtc() != other.windTime?.toUtc() ||
        publishingOffice != other.publishingOffice ||
        winds.length != other.winds.length ||
        ashfallWindows.length != other.ashfallWindows.length) {
      return false;
    }
    for (var index = 0; index < winds.length; index++) {
      final current = winds[index];
      final candidate = other.winds[index];
      if (current.heightFt != candidate.heightFt ||
          current.degree != candidate.degree ||
          current.speedKt != candidate.speedKt) {
        return false;
      }
    }
    for (var index = 0; index < ashfallWindows.length; index++) {
      if (!ashfallWindows[index].sameAs(other.ashfallWindows[index])) {
        return false;
      }
    }
    return true;
  }

  String _formatAshfallSummary(VolcanoAshfallWindow window) {
    final time = _formatWindowTime(window);
    final items = window.items
        .where((item) => item.phenomenon.trim().isNotEmpty)
        .take(2)
        .map((item) {
          final areas = item.areaNames.take(2).join('、');
          final distance = item.distanceKm == null
              ? ''
              : ' ${item.distanceKm!.round()}km';
          final direction = item.plumeDirection.trim().isEmpty
              ? ''
              : ' ${item.plumeDirection.trim()}';
          final areaText = areas.isEmpty ? '' : ' $areas';
          return '${item.phenomenon.trim()}$areaText$direction$distance';
        })
        .join('；');
    final prefix = [
      window.label.trim(),
      time,
    ].where((part) => part.isNotEmpty).join(' ');
    if (items.isEmpty) return prefix.isEmpty ? kindName.trim() : prefix;
    return prefix.isEmpty ? items : '$prefix：$items';
  }

  String _formatWindowTime(VolcanoAshfallWindow window) {
    String format(DateTime? value) {
      if (value == null) return '';
      final jst = value.toUtc().add(const Duration(hours: 9));
      String two(int number) => number.toString().padLeft(2, '0');
      return '${two(jst.month)}/${two(jst.day)} ${two(jst.hour)}:${two(jst.minute)}';
    }

    final start = format(window.startTime);
    final end = format(window.endTime);
    if (start.isEmpty) return end;
    if (end.isEmpty) return start;
    return '$start-$end';
  }
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
