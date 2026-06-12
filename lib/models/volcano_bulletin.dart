class VolcanoBulletin {
  final String id;
  final String feedTitle;
  final String bulletinTitle;
  final String infoKind;
  final String summary;
  final String? volcanoName;
  final String? alertLevelText;
  final double? latitude;
  final double? longitude;
  final DateTime? reportTime;
  final DateTime? targetTime;
  final DateTime? validTime;
  final List<String> targetAreas;
  final List<String> ashAreas;
  final List<String> plumeDirections;
  final Uri? sourceUrl;
  final DateTime fetchedAt;

  const VolcanoBulletin({
    required this.id,
    required this.feedTitle,
    required this.bulletinTitle,
    required this.infoKind,
    required this.summary,
    required this.fetchedAt,
    this.volcanoName,
    this.alertLevelText,
    this.latitude,
    this.longitude,
    this.reportTime,
    this.targetTime,
    this.validTime,
    this.targetAreas = const [],
    this.ashAreas = const [],
    this.plumeDirections = const [],
    this.sourceUrl,
  });

  VolcanoBulletin copyWith({
    String? feedTitle,
    String? bulletinTitle,
    String? infoKind,
    String? summary,
    String? volcanoName,
    String? alertLevelText,
    double? latitude,
    double? longitude,
    DateTime? reportTime,
    DateTime? targetTime,
    DateTime? validTime,
    List<String>? targetAreas,
    List<String>? ashAreas,
    List<String>? plumeDirections,
    Uri? sourceUrl,
    DateTime? fetchedAt,
  }) {
    return VolcanoBulletin(
      id: id,
      feedTitle: feedTitle ?? this.feedTitle,
      bulletinTitle: bulletinTitle ?? this.bulletinTitle,
      infoKind: infoKind ?? this.infoKind,
      summary: summary ?? this.summary,
      volcanoName: volcanoName ?? this.volcanoName,
      alertLevelText: alertLevelText ?? this.alertLevelText,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      reportTime: reportTime ?? this.reportTime,
      targetTime: targetTime ?? this.targetTime,
      validTime: validTime ?? this.validTime,
      targetAreas: targetAreas ?? this.targetAreas,
      ashAreas: ashAreas ?? this.ashAreas,
      plumeDirections: plumeDirections ?? this.plumeDirections,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'feedTitle': feedTitle,
      'bulletinTitle': bulletinTitle,
      'infoKind': infoKind,
      'summary': summary,
      'volcanoName': volcanoName,
      'alertLevelText': alertLevelText,
      'latitude': latitude,
      'longitude': longitude,
      'reportTime': reportTime?.toIso8601String(),
      'targetTime': targetTime?.toIso8601String(),
      'validTime': validTime?.toIso8601String(),
      'targetAreas': targetAreas,
      'ashAreas': ashAreas,
      'plumeDirections': plumeDirections,
      'sourceUrl': sourceUrl?.toString(),
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }

  factory VolcanoBulletin.fromJson(Map<String, dynamic> json) {
    List<String> listOf(String key) {
      final raw = json[key];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return const [];
    }

    double? finiteNum(dynamic raw) {
      final value = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
      if (value == null || !value.isFinite) return null;
      return value;
    }

    return VolcanoBulletin(
      id: json['id']?.toString() ?? '',
      feedTitle: json['feedTitle']?.toString() ?? '',
      bulletinTitle: json['bulletinTitle']?.toString() ?? '',
      infoKind: json['infoKind']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      volcanoName: json['volcanoName']?.toString(),
      alertLevelText: json['alertLevelText']?.toString(),
      latitude: finiteNum(json['latitude']),
      longitude: finiteNum(json['longitude']),
      reportTime: DateTime.tryParse(json['reportTime']?.toString() ?? ''),
      targetTime: DateTime.tryParse(json['targetTime']?.toString() ?? ''),
      validTime: DateTime.tryParse(json['validTime']?.toString() ?? ''),
      targetAreas: listOf('targetAreas'),
      ashAreas: listOf('ashAreas'),
      plumeDirections: listOf('plumeDirections'),
      sourceUrl: Uri.tryParse(json['sourceUrl']?.toString() ?? ''),
      fetchedAt: DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
