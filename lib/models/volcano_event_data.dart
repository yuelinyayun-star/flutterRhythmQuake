double? _parseDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _parseInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _parseTime(Object? value) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) return null;
  return DateTime.tryParse(text);
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.map((item) => item.toString()).toList();
}

List<Map<dynamic, dynamic>> _mapList(Object? value) {
  if (value is! List) return const <Map<dynamic, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<dynamic, dynamic>.from(item))
      .toList();
}

List<VolcanoAshfallCoordinate> _coordinateList(Object? value) {
  if (value is! List) return const <VolcanoAshfallCoordinate>[];
  return value
      .whereType<Map>()
      .map(
        (item) =>
            VolcanoAshfallCoordinate.fromMap(Map<dynamic, dynamic>.from(item)),
      )
      .toList();
}

List<Object?> _listValue(Object? value) =>
    value is List ? List<Object?>.from(value) : const <Object?>[];

class VolcanoWindProfile {
  final double? heightFt;
  final double? degree;
  final double? speedKt;

  const VolcanoWindProfile({this.heightFt, this.degree, this.speedKt});

  Map<String, dynamic> toMap() => {
    'heightFt': heightFt,
    'degree': degree,
    'speedKt': speedKt,
  };

  factory VolcanoWindProfile.fromMap(Map<dynamic, dynamic> map) =>
      VolcanoWindProfile(
        heightFt: _parseDouble(map['heightFt']),
        degree: _parseDouble(map['degree']),
        speedKt: _parseDouble(map['speedKt']),
      );
}

/// JMA 原始降灰范围点。经纬度值不投影、不抽稀，地图直接按官方顺序绘制。
class VolcanoAshfallCoordinate {
  final double latitude;
  final double longitude;

  const VolcanoAshfallCoordinate({
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
  };

  factory VolcanoAshfallCoordinate.fromMap(Map<dynamic, dynamic> map) =>
      VolcanoAshfallCoordinate(
        latitude: _parseDouble(map['latitude']) ?? 0,
        longitude: _parseDouble(map['longitude']) ?? 0,
      );

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

  Map<String, dynamic> toMap() => {
    'phenomenon': phenomenon,
    'phenomenonCode': phenomenonCode,
    'areaNames': areaNames,
    'areaCodes': areaCodes,
    'plumeDirection': plumeDirection,
    'distanceKm': distanceKm,
    'sizeCm': sizeCm,
    'polygons': polygons
        .map((polygon) => polygon.map((point) => point.toMap()).toList())
        .toList(),
  };

  factory VolcanoAshfallItem.fromMap(Map<dynamic, dynamic> map) =>
      VolcanoAshfallItem(
        phenomenon: map['phenomenon']?.toString() ?? '',
        phenomenonCode: map['phenomenonCode']?.toString() ?? '',
        areaNames: _stringList(map['areaNames']),
        areaCodes: _stringList(map['areaCodes']),
        plumeDirection: map['plumeDirection']?.toString() ?? '',
        distanceKm: _parseDouble(map['distanceKm']),
        sizeCm: _parseDouble(map['sizeCm']),
        polygons: _listValue(map['polygons']).map(_coordinateList).toList(),
      );

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

  Map<String, dynamic> toMap() => {
    'label': label,
    'startTime': startTime?.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'items': items.map((item) => item.toMap()).toList(),
  };

  factory VolcanoAshfallWindow.fromMap(Map<dynamic, dynamic> map) =>
      VolcanoAshfallWindow(
        label: map['label']?.toString() ?? '',
        startTime: _parseTime(map['startTime']),
        endTime: _parseTime(map['endTime']),
        items: _mapList(map['items']).map(VolcanoAshfallItem.fromMap).toList(),
      );

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

  Map<String, dynamic> toMap() => {
    'updates': updates,
    'kindCode': kindCode,
    'kindName': kindName,
    'infoKind': infoKind,
    'infoTypeName': infoTypeName,
    'title': title,
    'volcanoName': volcanoName,
    'volcanoCode': volcanoCode,
    'latitude': latitude,
    'longitude': longitude,
    'elevation': elevation,
    'craterName': craterName,
    'headline': headline,
    'activity': activity,
    'prevention': prevention,
    'nextAdvisory': nextAdvisory,
    'plumeDirection': plumeDirection,
    'plumeHeight': plumeHeight,
    'plumeHeightSea': plumeHeightSea,
    'observation': observation,
    'reportTime': reportTime?.toIso8601String(),
    'targetTime': targetTime?.toIso8601String(),
    'windTime': windTime?.toIso8601String(),
    'winds': winds.map((wind) => wind.toMap()).toList(),
    'publishingOffice': publishingOffice,
    'ashfallWindows': ashfallWindows.map((window) => window.toMap()).toList(),
  };

  factory VolcanoEventData.fromMap(Map<dynamic, dynamic> map) =>
      VolcanoEventData(
        updates: _parseInt(map['updates']) ?? 0,
        kindCode: map['kindCode']?.toString() ?? '',
        kindName: map['kindName']?.toString() ?? '',
        infoKind: map['infoKind']?.toString() ?? '',
        infoTypeName: map['infoTypeName']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        volcanoName: map['volcanoName']?.toString() ?? '',
        volcanoCode: map['volcanoCode']?.toString() ?? '',
        latitude: _parseDouble(map['latitude']),
        longitude: _parseDouble(map['longitude']),
        elevation: _parseDouble(map['elevation']),
        craterName: map['craterName']?.toString() ?? '',
        headline: map['headline']?.toString() ?? '',
        activity: map['activity']?.toString() ?? '',
        prevention: map['prevention']?.toString() ?? '',
        nextAdvisory: map['nextAdvisory']?.toString() ?? '',
        plumeDirection: map['plumeDirection']?.toString() ?? '',
        plumeHeight: _parseDouble(map['plumeHeight']),
        plumeHeightSea: _parseDouble(map['plumeHeightSea']),
        observation: map['observation']?.toString() ?? '',
        reportTime: _parseTime(map['reportTime']),
        targetTime: _parseTime(map['targetTime']),
        windTime: _parseTime(map['windTime']),
        winds: _mapList(map['winds']).map(VolcanoWindProfile.fromMap).toList(),
        publishingOffice: map['publishingOffice']?.toString() ?? '',
        ashfallWindows: _mapList(
          map['ashfallWindows'],
        ).map(VolcanoAshfallWindow.fromMap).toList(),
      );

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

  /// 火山の状況に関する解説情報（臨時）才使用 Temp.png。
  /// VFVO51 也可能是常规解説；是否临时只看报文里的「臨時/临时」。
  bool get isProvisionalCommentary {
    return _provisionalCommentaryPattern.hasMatch(
      '$kindName $infoKind $title $headline',
    );
  }

  /// WHEWS/JMA 火山状况解説情报（含 VFVO51）。
  bool get isCommentaryInfo =>
      kindCode.trim().toUpperCase() == 'VFVO51' ||
      _commentaryInfoPattern.hasMatch('$kindName $infoKind $title');

  /// Alert level mentioned in the telegram, if any (1-5).
  int? get parsedAlertLevel {
    final match = _alertLevelPattern.firstMatch(
      '$kindName $headline $activity $prevention $title $observation',
    );
    if (match == null) return null;
    const fullWidth = '１２３４５';
    final raw = match.group(1) ?? '';
    final fullIndex = fullWidth.indexOf(raw);
    if (fullIndex >= 0) return fullIndex + 1;
    return int.tryParse(raw);
  }

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

  /// Short summary for the compact unified card. The full forecast window is
  /// still available in [displayDetail] and the volcano sidebar.
  String get compactDisplayDetail {
    final ashfall = displayAshfallWindow();
    if (ashfall == null) return displayDetail;
    final label = ashfall.label.replaceAll(RegExp(r'\s+'), ' ').trim();
    final items = _formatAshfallItems(ashfall);
    if (items.isEmpty) return label.isEmpty ? kindName.trim() : label;
    return label.isEmpty ? items : '$label：$items';
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
    final items = _formatAshfallItems(window);
    final prefix = [
      window.label.trim(),
      time,
    ].where((part) => part.isNotEmpty).join(' ');
    if (items.isEmpty) return prefix.isEmpty ? kindName.trim() : prefix;
    return prefix.isEmpty ? items : '$prefix：$items';
  }

  String _formatAshfallItems(VolcanoAshfallWindow window) {
    return window.items
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

final _provisionalCommentaryPattern = RegExp(r'臨時|临时');
final _commentaryInfoPattern = RegExp(r'解説情報|解说信息|解説信息');
final _alertLevelPattern = RegExp(r'(?:レベル|Level)\s*([1-5１-５])');

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
