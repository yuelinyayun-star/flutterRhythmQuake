import 'dart:convert';

enum TsunamiSource { jma, nmefc }

enum TsunamiGrade { none, watch, warning, majorWarning }

class TsunamiAreaInfo {
  final String name;
  final TsunamiGrade grade;
  final double? height;
  final String? description;
  final String? arrivalTime;
  final String? condition;
  final String? classNameOverride;

  const TsunamiAreaInfo({
    required this.name,
    this.grade = TsunamiGrade.none,
    this.height,
    this.description,
    this.arrivalTime,
    this.condition,
    this.classNameOverride,
  });

  String get className {
    if (classNameOverride != null && classNameOverride!.isNotEmpty) {
      return classNameOverride!;
    }
    switch (grade) {
      case TsunamiGrade.watch:
        return 'yellow';
      case TsunamiGrade.warning:
        return 'red';
      case TsunamiGrade.majorWarning:
        return 'purple';
      case TsunamiGrade.none:
        return 'gray';
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'grade': grade.name,
    'height': height,
    'description': description,
    'arrivalTime': arrivalTime,
    'condition': condition,
    'className': className,
  };

  factory TsunamiAreaInfo.fromJson(Map<String, dynamic> json) {
    return TsunamiAreaInfo(
      name: json['name']?.toString() ?? '',
      grade: _parseGrade(json['grade']?.toString()),
      height: double.tryParse(json['height']?.toString() ?? ''),
      description: json['description']?.toString(),
      arrivalTime: json['arrivalTime']?.toString(),
      condition: json['condition']?.toString(),
      classNameOverride: json['className']?.toString(),
    );
  }

  static TsunamiGrade _parseGrade(String? grade) {
    switch (grade) {
      case 'Watch':
        return TsunamiGrade.watch;
      case 'Warning':
        return TsunamiGrade.warning;
      case 'MajorWarning':
        return TsunamiGrade.majorWarning;
      case '蓝色':
        return TsunamiGrade.watch;
      case '黄色':
        return TsunamiGrade.watch;
      case '橙色':
        return TsunamiGrade.warning;
      case '红色':
        return TsunamiGrade.majorWarning;
      default:
        return TsunamiGrade.none;
    }
  }
}

class TsunamiObservationInfo {
  final String stationName;
  final String location;
  final double latitude;
  final double longitude;
  final String time;
  final String maxWaveHeight;
  final double? maxWaveHeightMeters;

  const TsunamiObservationInfo({
    required this.stationName,
    required this.location,
    required this.latitude,
    required this.longitude,
    this.time = '',
    this.maxWaveHeight = '',
    this.maxWaveHeightMeters,
  });

  bool get hasValidPosition =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  factory TsunamiObservationInfo.fromNmefcJson(Map<String, dynamic> json) {
    final coordinates = json['coordinates'] as Map<String, dynamic>?;
    final heightText = json['maxWaveHeight']?.toString().trim() ?? '';
    return TsunamiObservationInfo(
      stationName: json['stationName']?.toString().trim() ?? '',
      location: json['location']?.toString().trim() ?? '',
      latitude:
          TsunamiMessage._parseDouble(coordinates?['latitude']) ?? double.nan,
      longitude:
          TsunamiMessage._parseDouble(coordinates?['longitude']) ?? double.nan,
      time: json['time']?.toString().trim() ?? '',
      maxWaveHeight: heightText,
      maxWaveHeightMeters: TsunamiMessage._parseNmefcWaveHeightMeters(
        heightText,
      ),
    );
  }
}

class TsunamiMessage {
  final TsunamiSource source;
  final String id;
  final int timeZone;
  final String reportTime;
  final String title;
  final String titleText;
  final TsunamiGrade grade;
  final List<TsunamiAreaInfo> areas;
  final double? epicenterLat;
  final double? epicenterLng;
  final double? magnitude;
  final double? depth;
  final String epicenterName;
  final String originTime;
  final List<TsunamiObservationInfo> observations;
  final String htmlUrl;
  final String earthquakeMapUrl;
  final String amplitudeMapUrl;
  final String coastalMapUrl;
  final String className;

  const TsunamiMessage({
    required this.source,
    this.id = '',
    this.timeZone = 9,
    this.reportTime = '',
    this.title = '',
    this.titleText = '',
    this.grade = TsunamiGrade.none,
    this.areas = const [],
    this.epicenterLat,
    this.epicenterLng,
    this.magnitude,
    this.depth,
    this.epicenterName = '',
    this.originTime = '',
    this.observations = const [],
    this.htmlUrl = '',
    this.earthquakeMapUrl = '',
    this.amplitudeMapUrl = '',
    this.coastalMapUrl = '',
    this.className = 'gray',
  });

  bool get isActive => grade != TsunamiGrade.none;

  String get warnAreaJson => json.encode(areas.map((a) => a.toJson()).toList());

  int get status {
    switch (grade) {
      case TsunamiGrade.none:
        return 0;
      case TsunamiGrade.watch:
        return 1;
      case TsunamiGrade.warning:
        return 2;
      case TsunamiGrade.majorWarning:
        return 3;
    }
  }

  TsunamiMessage copyWith({
    TsunamiSource? source,
    String? id,
    int? timeZone,
    String? reportTime,
    String? title,
    String? titleText,
    TsunamiGrade? grade,
    List<TsunamiAreaInfo>? areas,
    double? epicenterLat,
    double? epicenterLng,
    double? magnitude,
    double? depth,
    String? epicenterName,
    String? originTime,
    List<TsunamiObservationInfo>? observations,
    String? htmlUrl,
    String? earthquakeMapUrl,
    String? amplitudeMapUrl,
    String? coastalMapUrl,
    String? className,
  }) {
    return TsunamiMessage(
      source: source ?? this.source,
      id: id ?? this.id,
      timeZone: timeZone ?? this.timeZone,
      reportTime: reportTime ?? this.reportTime,
      title: title ?? this.title,
      titleText: titleText ?? this.titleText,
      grade: grade ?? this.grade,
      areas: areas ?? this.areas,
      epicenterLat: epicenterLat ?? this.epicenterLat,
      epicenterLng: epicenterLng ?? this.epicenterLng,
      magnitude: magnitude ?? this.magnitude,
      depth: depth ?? this.depth,
      epicenterName: epicenterName ?? this.epicenterName,
      originTime: originTime ?? this.originTime,
      observations: observations ?? this.observations,
      htmlUrl: htmlUrl ?? this.htmlUrl,
      earthquakeMapUrl: earthquakeMapUrl ?? this.earthquakeMapUrl,
      amplitudeMapUrl: amplitudeMapUrl ?? this.amplitudeMapUrl,
      coastalMapUrl: coastalMapUrl ?? this.coastalMapUrl,
      className: className ?? this.className,
    );
  }

  static TsunamiMessage parseJmaTsunami(Map<String, dynamic> json) {
    final issue = json['issue'] as Map<String, dynamic>?;
    final reportTime = issue?['time']?.toString().replaceAll('/', '-') ?? '';
    final id =
        json['id']?.toString() ??
        issue?['time']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ??
        '';
    final bool cancelled = json['cancelled'] == true;

    if (cancelled) {
      return TsunamiMessage(
        source: TsunamiSource.jma,
        id: id,
        timeZone: 9,
        reportTime: reportTime,
        title: '津波警報・注意報なし',
        titleText: '津波警報・注意報なし',
        grade: TsunamiGrade.none,
        className: 'gray',
      );
    }

    final areasRaw = json['areas'] as List? ?? [];
    TsunamiGrade topGrade = TsunamiGrade.none;
    final areas = <TsunamiAreaInfo>[];

    for (final area in areasRaw) {
      if (area is! Map<String, dynamic>) continue;
      final info = TsunamiAreaInfo(
        name: area['name']?.toString() ?? '',
        grade: TsunamiAreaInfo._parseGrade(area['grade']?.toString()),
        height: double.tryParse(area['maxHeight']?['value']?.toString() ?? ''),
        description: area['maxHeight']?['description']?.toString(),
        arrivalTime: area['firstHeight']?['arrivalTime']?.toString(),
        condition: area['firstHeight']?['condition']?.toString(),
      );
      areas.add(info);
      if (info.grade.index > topGrade.index) {
        topGrade = info.grade;
      }
    }

    String title;
    String titleText;
    String className;
    switch (topGrade) {
      case TsunamiGrade.majorWarning:
        title = '大津波警報';
        titleText = '大津波警報発表中';
        className = 'purple';
        break;
      case TsunamiGrade.warning:
        title = '津波警報';
        titleText = '津波警報発表中';
        className = 'red';
        break;
      case TsunamiGrade.watch:
        title = '津波注意報';
        titleText = '津波注意報発表中';
        className = 'yellow';
        break;
      case TsunamiGrade.none:
        title = '津波警報・注意報なし';
        titleText = '津波警報・注意報なし';
        className = 'gray';
        break;
    }

    return TsunamiMessage(
      source: TsunamiSource.jma,
      id: id,
      timeZone: 9,
      reportTime: reportTime,
      title: title,
      titleText: titleText,
      grade: topGrade,
      areas: areas,
      className: className,
    );
  }

  static TsunamiMessage parseNmefcTsunami(Map<String, dynamic> json) {
    final timeInfo = json['timeInfo'] as Map<String, dynamic>?;
    final warningInfo = json['warningInfo'] as Map<String, dynamic>?;
    final shockInfo = json['shockInfo'] as Map<String, dynamic>?;
    final details = json['details'] as Map<String, dynamic>?;
    final maps = details?['maps'] as Map<String, dynamic>?;
    final reportTime = timeInfo?['updateDate']?.toString() ?? '';
    final id = json['id']?.toString().trim().isNotEmpty == true
        ? json['id'].toString()
        : json['code']?.toString().trim().isNotEmpty == true
        ? '${json['code']}_${timeInfo?['updateDate']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? ''}'
        : timeInfo?['updateDate']?.toString().replaceAll(
                RegExp(r'[^0-9]'),
                '',
              ) ??
              '';
    final level = warningInfo?['level']?.toString() ?? '';
    final rawTitle = warningInfo?['title']?.toString().trim() ?? '';

    TsunamiGrade grade;
    String title;
    String titleText;
    String className;

    switch (level) {
      case '蓝色':
        grade = TsunamiGrade.watch;
        title = rawTitle.isNotEmpty ? rawTitle : '海啸蓝色警报';
        titleText = '现正发布$title';
        className = 'blue';
        break;
      case '黄色':
        grade = TsunamiGrade.watch;
        title = rawTitle.isNotEmpty ? rawTitle : '海啸黄色警报';
        titleText = '现正发布$title';
        className = 'yellow';
        break;
      case '橙色':
        grade = TsunamiGrade.warning;
        title = rawTitle.isNotEmpty ? rawTitle : '海啸橙色警报';
        titleText = '现正发布$title';
        className = 'red';
        break;
      case '红色':
        grade = TsunamiGrade.majorWarning;
        title = rawTitle.isNotEmpty ? rawTitle : '海啸红色警报';
        titleText = '现正发布$title';
        className = 'purple';
        break;
      case '信息':
        grade = TsunamiGrade.none;
        title = rawTitle.isNotEmpty ? rawTitle : '海啸信息';
        titleText = title;
        className = 'gray';
        break;
      default:
        grade = TsunamiGrade.none;
        title = rawTitle.isNotEmpty ? rawTitle : '海啸预警已解除';
        titleText = title;
        className = 'gray';
        break;
    }

    final forecasts = json['forecasts'] as List? ?? [];
    final areas = <TsunamiAreaInfo>[];
    for (final item in forecasts) {
      if (item is! Map<String, dynamic>) continue;
      final warningLevel = item['warningLevel']?.toString() ?? '';
      final maxWaveHeight = item['maxWaveHeight']?.toString().trim() ?? '';
      final height = _parseNmefcWaveHeightMeters(maxWaveHeight);
      String? desc = maxWaveHeight.isNotEmpty ? '${maxWaveHeight}cm' : null;
      switch (warningLevel) {
        case '蓝色':
          desc ??= '30cm以下';
          break;
        case '黄色':
          desc ??= '30-100cm';
          break;
        case '橙色':
          desc ??= '100-300cm';
          break;
        case '红色':
          desc ??= '300cm以上';
          break;
      }
      areas.add(
        TsunamiAreaInfo(
          name: item['forecastArea']?.toString() ?? '',
          grade: TsunamiAreaInfo._parseGrade(warningLevel),
          height: height,
          description: desc,
          arrivalTime: item['estimatedArrivalTime']?.toString(),
          condition: item['province']?.toString(),
          classNameOverride: _parseNmefcClassName(warningLevel),
        ),
      );
    }

    final observations = <TsunamiObservationInfo>[];
    final waterLevelMonitoring = json['waterLevelMonitoring'] as List? ?? [];
    for (final item in waterLevelMonitoring) {
      if (item is! Map<String, dynamic>) continue;
      final observation = TsunamiObservationInfo.fromNmefcJson(item);
      if (observation.hasValidPosition) {
        observations.add(observation);
      }
    }

    return TsunamiMessage(
      source: TsunamiSource.nmefc,
      id: id,
      timeZone: 8,
      reportTime: reportTime,
      title: title,
      titleText: titleText,
      grade: grade,
      areas: areas,
      epicenterLat: _parseDouble(shockInfo?['latitude']),
      epicenterLng: _parseDouble(shockInfo?['longitude']),
      magnitude: _parseDouble(shockInfo?['magnitude']),
      depth: _parseDouble(shockInfo?['depth']),
      epicenterName: shockInfo?['placeName']?.toString().trim() ?? '',
      originTime: shockInfo?['shockTime']?.toString().trim() ?? '',
      observations: observations,
      htmlUrl: details?['htmlUrl']?.toString().trim() ?? '',
      earthquakeMapUrl: maps?['earthquakeMapUrl']?.toString().trim() ?? '',
      amplitudeMapUrl: maps?['amplitudeMapUrl']?.toString().trim() ?? '',
      coastalMapUrl: maps?['coastalMapUrl']?.toString().trim() ?? '',
      className: className,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static String? _parseNmefcClassName(String level) {
    switch (level) {
      case '蓝色':
      case '钃濊壊':
        return 'blue';
      case '黄色':
      case '榛勮壊':
        return 'yellow';
      case '橙色':
      case '姗欒壊':
        return 'red';
      case '红色':
      case '绾㈣壊':
        return 'purple';
      default:
        return null;
    }
  }

  static double? _parseNmefcWaveHeightMeters(String value) {
    if (value.isEmpty) return null;
    final matches = RegExp(r'\d+(?:\.\d+)?').allMatches(value).toList();
    if (matches.isEmpty) return null;
    final centimeters = matches
        .map((m) => double.tryParse(m.group(0) ?? '') ?? 0)
        .fold<double>(0, (max, v) => v > max ? v : max);
    return centimeters > 0 ? centimeters / 100.0 : null;
  }
}
