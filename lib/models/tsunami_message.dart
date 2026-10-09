import 'dart:convert';
import '../core/utils/information_report_order.dart';
import '../core/utils/quake_time.dart';

enum TsunamiSource { jma, nmefc, ptwc, ntwc, incois, cat, cwa }

extension TsunamiSourceLabels on TsunamiSource {
  String get displayLabel => switch (this) {
    TsunamiSource.jma => 'P2P/JMA',
    TsunamiSource.nmefc => 'NMEFC',
    TsunamiSource.ptwc => 'PTWC',
    TsunamiSource.ntwc => 'NTWC',
    TsunamiSource.incois => 'INCOIS',
    TsunamiSource.cat => 'CAT',
    TsunamiSource.cwa => 'CWA',
  };

  String get voiceLabel => switch (this) {
    TsunamiSource.jma => '日本气象厅',
    TsunamiSource.nmefc => '国家海洋预报台',
    TsunamiSource.ptwc => '太平洋海啸预警中心',
    TsunamiSource.ntwc => '美国国家海啸预警中心',
    TsunamiSource.incois => '印度海啸早期预警中心',
    TsunamiSource.cat => '墨西哥海啸预警中心',
    TsunamiSource.cwa => '台湾中央气象署',
  };

  bool get isBulletinSource => const {
    TsunamiSource.ptwc, TsunamiSource.ntwc, TsunamiSource.incois,
    TsunamiSource.cat, TsunamiSource.cwa,
  }.contains(this);
}

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
  final String stationId;
  final String condition;
  final String stationName;
  final String location;
  final double latitude;
  final double longitude;
  final String time;
  final String maxWaveHeight;
  final double? maxWaveHeightMeters;

  const TsunamiObservationInfo({
    this.stationId = '',
    this.condition = '',
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
  final String eventId;
  final int? reportNumber;
  final Map<String, dynamic> sourcePayload;
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
  final String bulletinLevel;
  final String expires;
  final bool isInitialSnapshot;

  const TsunamiMessage({
    required this.source,
    this.id = '',
    this.eventId = '',
    this.reportNumber,
    this.sourcePayload = const {},
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
    this.bulletinLevel = '',
    this.expires = '',
    this.isInitialSnapshot = false,
  });

  bool get isActive => grade != TsunamiGrade.none;

  bool get isInformation =>
      source.isBulletinSource &&
      bulletinLevel.toLowerCase() == 'information';

  DateTime? get informationDisplayUntilUtc {
    if (!isInformation) return null;
    final issued = reportInstantUtc;
    if (issued == null) return null;
    final sourceExpiry = _parseSourceTimeUtc(expires, timeZone);
    if (sourceExpiry != null && sourceExpiry.isAfter(issued)) {
      return sourceExpiry;
    }
    // Presentation freshness only; this does not assert a warning expiry.
    return issued.add(const Duration(hours: 3));
  }

  DateTime? get displayUntilUtc => informationDisplayUntilUtc ??
      ((source == TsunamiSource.cat || source == TsunamiSource.cwa)
          ? _parseSourceTimeUtc(expires, timeZone) : null);

  bool isDisplayableAt(DateTime now) {
    final deadline = displayUntilUtc;
    if (deadline != null && !deadline.isAfter(now.toUtc())) return false;
    return isActive || (informationDisplayUntilUtc?.isAfter(now.toUtc()) ?? false);
  }

  bool get isCancellation {
    // A CWA Information report can quote removal of a Pacific threat in its
    // description. Its explicit source level, not that quoted text, decides.
    if ((source == TsunamiSource.cat || source == TsunamiSource.cwa) &&
        bulletinLevel.trim().isNotEmpty) {
      return !isActive && bulletinLevel.toLowerCase() == 'cancellation';
    }
    return !isActive &&
      (bulletinLevel.toLowerCase() == 'cancellation' ||
          title.contains('解除') ||
          titleText.contains('解除') ||
          title.contains('なし') ||
          titleText.contains('なし'));
  }

  DateTime? get reportInstantUtc {
    return _parseSourceTimeUtc(reportTime, timeZone);
  }

  String formatLocalTime(String raw) {
    final time = _parseSourceTimeUtc(raw, timeZone)?.toLocal();
    if (time == null) return '未知';
    return '${QuakeTime.formatWallClock(time)} (${QuakeTime.formatTimeZone(time.timeZoneOffset)})';
  }

  /// Compare only reports whose upstream event identity proves they match.
  int? reportOrderComparedTo(TsunamiMessage previous) {
    if (source != previous.source || eventId.isEmpty ||
        eventId != previous.eventId) {
      return null;
    }
    return compareInformationReportOrder(
      currentNumber: previous.reportNumber, incomingNumber: reportNumber,
      currentTime: previous.reportInstantUtc, incomingTime: reportInstantUtc,
    );
  }

  static DateTime? _parseSourceTimeUtc(String raw, int timeZone) {
    final value = raw.trim().replaceAll('/', '-');
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    if (RegExp(
      r'(?:Z|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).hasMatch(value)) {
      return parsed.toUtc();
    }
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).subtract(Duration(hours: timeZone));
  }

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

  Map<String, dynamic> toMap() => {
    'source': source.name,
    'id': id,
    'eventId': eventId,
    'reportNumber': reportNumber,
    'sourcePayload': sourcePayload,
    'timeZone': timeZone,
    'reportTime': reportTime,
    'title': title,
    'titleText': titleText,
    'grade': grade.name,
    'areas': areas.map((area) => area.toJson()).toList(),
    'epicenterLat': epicenterLat,
    'epicenterLng': epicenterLng,
    'magnitude': magnitude,
    'depth': depth,
    'epicenterName': epicenterName,
    'originTime': originTime,
    'observations': observations
        .map(
          (item) => {
            'stationId': item.stationId,
            'condition': item.condition,
            'stationName': item.stationName,
            'location': item.location,
            'latitude': item.latitude.isFinite ? item.latitude : null,
            'longitude': item.longitude.isFinite ? item.longitude : null,
            'time': item.time,
            'maxWaveHeight': item.maxWaveHeight,
            'maxWaveHeightMeters': item.maxWaveHeightMeters,
          },
        )
        .toList(),
    'htmlUrl': htmlUrl,
    'earthquakeMapUrl': earthquakeMapUrl,
    'amplitudeMapUrl': amplitudeMapUrl,
    'coastalMapUrl': coastalMapUrl,
    'className': className,
    'bulletinLevel': bulletinLevel,
    'expires': expires,
    'isInitialSnapshot': isInitialSnapshot,
  };

  factory TsunamiMessage.fromMap(Map<dynamic, dynamic> map) {
    TsunamiGrade parseGrade(Object? value) {
      return TsunamiGrade.values.firstWhere(
        (item) => item.name == value?.toString(),
        orElse: () => TsunamiGrade.none,
      );
    }

    TsunamiSource parseSource(Object? value) {
      return TsunamiSource.values.firstWhere(
        (item) => item.name == value?.toString(),
        orElse: () => TsunamiSource.jma,
      );
    }

    double? parseDouble(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    final rawAreas = map['areas'];
    final rawObservations = map['observations'];
    return TsunamiMessage(
      source: parseSource(map['source']),
      id: map['id']?.toString() ?? '',
      eventId: map['eventId']?.toString() ?? '',
      reportNumber: (map['reportNumber'] as num?)?.toInt(),
      sourcePayload: map['sourcePayload'] is Map
          ? Map<String, dynamic>.from(map['sourcePayload'] as Map) : const {},
      timeZone: (map['timeZone'] as num?)?.toInt() ?? 9,
      reportTime: map['reportTime']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      titleText: map['titleText']?.toString() ?? '',
      grade: parseGrade(map['grade']),
      areas: rawAreas is List
          ? rawAreas
                .whereType<Map>()
                .map(
                  (item) =>
                      TsunamiAreaInfo.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
      epicenterLat: parseDouble(map['epicenterLat']),
      epicenterLng: parseDouble(map['epicenterLng']),
      magnitude: parseDouble(map['magnitude']),
      depth: parseDouble(map['depth']),
      epicenterName: map['epicenterName']?.toString() ?? '',
      originTime: map['originTime']?.toString() ?? '',
      observations: rawObservations is List
          ? rawObservations.whereType<Map>().map((item) {
              final row = Map<dynamic, dynamic>.from(item);
              return TsunamiObservationInfo(
                stationId: row['stationId']?.toString() ?? '',
                condition: row['condition']?.toString() ?? '',
                stationName: row['stationName']?.toString() ?? '',
                location: row['location']?.toString() ?? '',
                latitude: parseDouble(row['latitude']) ?? double.nan,
                longitude: parseDouble(row['longitude']) ?? double.nan,
                time: row['time']?.toString() ?? '',
                maxWaveHeight: row['maxWaveHeight']?.toString() ?? '',
                maxWaveHeightMeters: parseDouble(row['maxWaveHeightMeters']),
              );
            }).toList()
          : const [],
      htmlUrl: map['htmlUrl']?.toString() ?? '',
      earthquakeMapUrl: map['earthquakeMapUrl']?.toString() ?? '',
      amplitudeMapUrl: map['amplitudeMapUrl']?.toString() ?? '',
      coastalMapUrl: map['coastalMapUrl']?.toString() ?? '',
      className: map['className']?.toString() ?? 'gray',
      bulletinLevel: map['bulletinLevel']?.toString() ?? '',
      expires: map['expires']?.toString() ?? '',
      isInitialSnapshot: map['isInitialSnapshot'] == true,
    );
  }

  TsunamiMessage copyWith({
    TsunamiSource? source,
    String? id,
    String? eventId,
    int? reportNumber,
    Map<String, dynamic>? sourcePayload,
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
    String? bulletinLevel,
    String? expires,
    bool? isInitialSnapshot,
  }) {
    return TsunamiMessage(
      source: source ?? this.source,
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      reportNumber: reportNumber ?? this.reportNumber,
      sourcePayload: sourcePayload ?? this.sourcePayload,
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
      bulletinLevel: bulletinLevel ?? this.bulletinLevel,
      expires: expires ?? this.expires,
      isInitialSnapshot: isInitialSnapshot ?? this.isInitialSnapshot,
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

  static TsunamiMessage parseWhewsJmaTsunami(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final reportTime = json['createTime']?.toString().trim() ?? '';
    final headline = json['headline']?.toString().trim() ?? '';
    final cancelled = json['cancel'] == true;

    if (cancelled) {
      return TsunamiMessage(
        source: TsunamiSource.jma,
        id: id,
        timeZone: 9,
        reportTime: reportTime,
        title: '津波警報・注意報解除',
        titleText: headline.isNotEmpty ? headline : '津波警報・注意報は解除されました',
        grade: TsunamiGrade.none,
        className: 'gray',
      );
    }

    final areas = <TsunamiAreaInfo>[];
    var topGrade = TsunamiGrade.none;
    final areasRaw = json['areas'];
    if (areasRaw is List) {
      for (final rawArea in areasRaw) {
        if (rawArea is! Map) continue;
        final area = Map<String, dynamic>.from(rawArea);
        final kind = area['kind']?.toString().trim() ?? '';
        final grade = _parseWhewsJmaGrade(kind);
        final rawHeight = area['maxHeight']?.toString().trim() ?? '';
        final heightDescription =
            area['maxHeightDesc']?.toString().trim() ?? '';
        areas.add(
          TsunamiAreaInfo(
            name: area['name']?.toString().trim() ?? '',
            grade: grade,
            height: _parseDouble(rawHeight),
            description: heightDescription.isNotEmpty
                ? heightDescription
                : rawHeight.isNotEmpty
                ? rawHeight
                : null,
            arrivalTime: area['arrivalTime']?.toString().trim(),
            condition: area['condition']?.toString().trim(),
          ),
        );
        if (grade.index > topGrade.index) {
          topGrade = grade;
        }
      }
    }

    final rawTitle = json['title']?.toString().trim() ?? '';
    final fallbackText = _whewsJmaStatusText(topGrade);
    return TsunamiMessage(
      source: TsunamiSource.jma,
      id: id,
      timeZone: 9,
      reportTime: reportTime,
      title: rawTitle.isNotEmpty ? rawTitle : fallbackText,
      titleText: headline.isNotEmpty ? headline : fallbackText,
      grade: topGrade,
      areas: areas,
      className: _whewsJmaClassName(topGrade),
    );
  }

  static TsunamiMessage parseNmefcTsunami(Map<String, dynamic> json) {
    final timeInfo = json['timeInfo'] as Map<String, dynamic>?;
    final warningInfo = json['warningInfo'] as Map<String, dynamic>?;
    final shockInfo = json['shockInfo'] as Map<String, dynamic>?;
    final details = json['details'] as Map<String, dynamic>?;
    final maps = details?['maps'] as Map<String, dynamic>?;
    final alarmDate = timeInfo?['alarmDate']?.toString().trim() ?? '';
    final updateDate = timeInfo?['updateDate']?.toString().trim() ?? '';
    final reportTime = alarmDate.isNotEmpty ? alarmDate : updateDate;
    final code = json['code']?.toString().trim() ?? '';
    final id = code.isNotEmpty
        ? code
        : json['id']?.toString().trim().isNotEmpty == true
        ? json['id'].toString()
        : updateDate.replaceAll(RegExp(r'[^0-9]'), '');
    final level = warningInfo?['level']?.toString() ?? '';
    final rawTitle = warningInfo?['title']?.toString().trim() ?? '';
    final subtitle = warningInfo?['subtitle']?.toString().trim() ?? '';
    final batch = details?['batch']?.toString().trim() ?? '';

    TsunamiGrade grade;
    String title;
    String titleText;
    String className;

    switch (level) {
      case '蓝色':
      case '黄色':
        grade = TsunamiGrade.watch;
        title = '海啸注意报';
        titleText = subtitle.isNotEmpty ? subtitle : '现正发布$title';
        className = 'yellow';
        break;
      case '橙色':
        grade = TsunamiGrade.warning;
        title = '海啸警报';
        titleText = subtitle.isNotEmpty ? subtitle : '现正发布$title';
        className = 'red';
        break;
      case '红色':
        grade = TsunamiGrade.majorWarning;
        title = '大海啸警报';
        titleText = subtitle.isNotEmpty ? subtitle : '现正发布$title';
        className = 'purple';
        break;
      case '信息':
        grade = TsunamiGrade.none;
        title = rawTitle.isNotEmpty ? rawTitle : '海啸信息';
        titleText = subtitle.isNotEmpty ? subtitle : title;
        className = 'gray';
        break;
      case '解除':
        grade = TsunamiGrade.none;
        title = rawTitle.isNotEmpty ? rawTitle : '海啸预警已解除';
        titleText = subtitle.isNotEmpty ? subtitle : title;
        className = 'gray';
        break;
      default:
        grade = TsunamiGrade.none;
        title = rawTitle.isNotEmpty ? rawTitle : '海啸预警已解除';
        titleText = subtitle.isNotEmpty ? subtitle : title;
        className = 'gray';
        break;
    }
    if (batch.isNotEmpty && grade != TsunamiGrade.none) {
      title = '$title 第$batch报';
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

  static TsunamiGrade _parseWhewsJmaGrade(String kind) {
    if (kind.contains('大津波警報')) {
      return TsunamiGrade.majorWarning;
    }
    if (kind.contains('津波警報')) {
      return TsunamiGrade.warning;
    }
    if (kind.contains('津波注意報')) {
      return TsunamiGrade.watch;
    }
    return TsunamiGrade.none;
  }

  static String _whewsJmaStatusText(TsunamiGrade grade) {
    switch (grade) {
      case TsunamiGrade.majorWarning:
        return '大津波警報発表中';
      case TsunamiGrade.warning:
        return '津波警報発表中';
      case TsunamiGrade.watch:
        return '津波注意報発表中';
      case TsunamiGrade.none:
        return '津波警報・注意報なし';
    }
  }

  static String _whewsJmaClassName(TsunamiGrade grade) {
    switch (grade) {
      case TsunamiGrade.majorWarning:
        return 'purple';
      case TsunamiGrade.warning:
        return 'red';
      case TsunamiGrade.watch:
        return 'yellow';
      case TsunamiGrade.none:
        return 'gray';
    }
  }

  static String? _parseNmefcClassName(String level) {
    switch (level) {
      case '蓝色':
        return 'yellow';
      case '黄色':
        return 'yellow';
      case '橙色':
        return 'red';
      case '红色':
        return 'purple';
      default:
        return null;
    }
  }

  static TsunamiMessage parseInternationalTsunami(
    TsunamiSource source,
    Map<String, dynamic> json,
  ) {
    assert(source.isBulletinSource);
    final level = json['level']?.toString().trim() ?? '';
    final grade = _parseInternationalLevel(level);
    final headline = json['headline']?.toString().trim() ?? '';
    final description = json['description']?.toString().trim() ?? '';
    final instruction = json['instruction']?.toString().trim() ?? '';
    final reportTime = json['issueTime']?.toString().trim() ?? '';
    final originTime = json['shockTime']?.toString().trim() ?? '';
    final id =
        json['id']?.toString().trim() ??
        json['eventId']?.toString().trim() ??
        '';
    final maps = json['maps'] as Map<String, dynamic>?;
    final bulletinUrl = json['bulletinUrl']?.toString().trim() ?? '';
    final detailUrl = json['detailUrl']?.toString().trim() ?? '';
    final capUrl = json['capUrl']?.toString().trim() ?? '';
    final htmlUrl = bulletinUrl.isNotEmpty
        ? bulletinUrl
        : detailUrl.isNotEmpty
        ? detailUrl
        : capUrl;
    final title = headline.isNotEmpty
        ? headline
        : _internationalLevelTitle(grade, level);
    final titleText = description.isNotEmpty
        ? description
        : instruction.isNotEmpty
        ? instruction
        : title;
    final updates = int.tryParse(json['updates']?.toString() ?? '');
    final rawAreas = json['warningAreas'];
    final rawStations = json['stations'];

    return TsunamiMessage(
      source: source,
      id: id,
      eventId: json['eventId']?.toString().trim() ?? '',
      reportNumber: updates != null && updates > 0 ? updates : null,
      sourcePayload: Map<String, dynamic>.from(json),
      timeZone: 8,
      reportTime: reportTime,
      originTime: originTime,
      title: title,
      titleText: titleText,
      grade: grade,
      className: _internationalClassName(grade),
      bulletinLevel: level,
      expires: json['expires']?.toString().trim() ?? '',
      epicenterLat: _parseDouble(json['latitude']),
      epicenterLng: _parseDouble(json['longitude']),
      magnitude: _parseDouble(json['magnitude']),
      depth: _parseDouble(json['depth']),
      epicenterName: json['placeName']?.toString().trim() ?? '',
      areas: rawAreas is List ? rawAreas.whereType<Map>().map((area) {
        final areaColor = area['areaColor']?.toString().trim() ?? '';
        final areaGrade = switch (areaColor) {
          '紅色' || '红色' => TsunamiGrade.warning,
          '橙色' => TsunamiGrade.warning,
          '黃色' || '黄色' => TsunamiGrade.watch,
          '綠色' || '绿色' => TsunamiGrade.none,
          _ => grade,
        };
        final wave = area['waveHeight']?.toString().trim() ?? '';
        final detail = area['areaDesc']?.toString().trim() ?? '';
        return TsunamiAreaInfo(
          name: area['areaName']?.toString().trim() ?? '',
          grade: areaGrade,
          height: _waveHeightMeters(wave),
          description: [if (detail.isNotEmpty) detail, if (wave.isNotEmpty) '波高：$wave'].join('；'),
          arrivalTime: area['arrivalTime']?.toString().trim(),
          condition: area['infoStatus']?.toString().trim(),
        );
      }).toList() : const [],
      observations: rawStations is List ? rawStations.whereType<Map>().map((station) {
        final wave = station['waveHeight']?.toString().trim() ?? '';
        return TsunamiObservationInfo(
          stationId: station['stationId']?.toString().trim() ?? '',
          stationName: station['stationName']?.toString().trim() ?? '',
          condition: station['infoStatus']?.toString().trim() ?? '',
          location: '',
          latitude: _parseDouble(station['latitude']) ?? double.nan,
          longitude: _parseDouble(station['longitude']) ?? double.nan,
          time: station['arrivalTime']?.toString().trim() ?? '',
          maxWaveHeight: wave, maxWaveHeightMeters: _waveHeightMeters(wave),
        );
      }).toList() : const [],
      htmlUrl: htmlUrl,
      earthquakeMapUrl: maps?['energyMapUrl']?.toString().trim() ?? '',
      amplitudeMapUrl: maps?['travelTimeMapUrl']?.toString().trim() ?? '',
    );
  }

  static double? _waveHeightMeters(String value) {
    // CWA's string contract does not specify a unit for bare numbers.
    final match = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(cm|m|公分|厘米|米)\s*$', caseSensitive: false).firstMatch(value);
    if (match == null) return null;
    final number = double.parse(match.group(1)!);
    return const {'cm', '公分', '厘米'}.contains(match.group(2)!.toLowerCase())
        ? number / 100 : number;
  }

  static TsunamiGrade _parseInternationalLevel(String level) {
    final normalized = level.trim().toLowerCase();
    if (normalized.contains('warning')) return TsunamiGrade.warning;
    if (normalized.contains('alert')) return TsunamiGrade.warning;
    if (normalized.contains('advisory')) return TsunamiGrade.watch;
    if (normalized.contains('watch')) return TsunamiGrade.watch;
    return TsunamiGrade.none;
  }

  static String _internationalLevelTitle(TsunamiGrade grade, String rawLevel) {
    if (rawLevel.trim().isNotEmpty) return rawLevel.trim();
    return switch (grade) {
      TsunamiGrade.majorWarning => 'Tsunami Warning',
      TsunamiGrade.warning => 'Tsunami Warning',
      TsunamiGrade.watch => 'Tsunami Watch',
      TsunamiGrade.none => 'Tsunami Information',
    };
  }

  static String _internationalClassName(TsunamiGrade grade) {
    return switch (grade) {
      TsunamiGrade.majorWarning => 'purple',
      TsunamiGrade.warning => 'red',
      TsunamiGrade.watch => 'yellow',
      TsunamiGrade.none => 'gray',
    };
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
