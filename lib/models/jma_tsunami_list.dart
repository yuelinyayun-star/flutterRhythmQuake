/// Prepared Rust view. No grade inference, sorting or height conversion here.
class JmaTsunamiListGroup {
  final String source;
  final bool pinned;
  final String informationText;
  final String eventText;
  final int timeZone;
  final String key, grade, label, caption, className, reportTime, headline;
  final int? reportNumber;
  final int regionCount;
  final List<JmaTsunamiListRow> rows;
  final String nameLabel, timeLabel, heightLabel, countLabel;
  JmaTsunamiListGroup.fromMap(Map map)
    : source = map['source'] as String? ?? 'jma',
      pinned = map['pinned'] as bool? ?? true,
      informationText = map['informationText'] as String? ?? '',
      eventText = map['eventText'] as String? ?? '',
      timeZone = map['timeZone'] as int? ?? 9,
      key = map['key'] as String,
      grade = map['grade'] as String,
      label = map['label'] as String,
      caption = map['caption'] as String,
      className = map['className'] as String,
      reportTime = map['reportTime'] as String,
      headline = map['headline'] as String,
      reportNumber = map['reportNumber'] as int?,
      regionCount = map['regionCount'] as int,
      nameLabel = map['nameLabel'] as String? ?? '区域',
      timeLabel = map['timeLabel'] as String? ?? '到达',
      heightLabel = map['heightLabel'] as String? ?? '波高',
      countLabel = map['countLabel'] as String? ?? '区域',
      rows = List.unmodifiable(
        (map['rows'] as List).map((v) => JmaTsunamiListRow.fromMap(v as Map)),
      );

  Map<String, dynamic> toMap() => {
    'source': source,
    'pinned': pinned,
    'informationText': informationText,
    'eventText': eventText,
    'timeZone': timeZone,
    'nameLabel': nameLabel,
    'timeLabel': timeLabel,
    'heightLabel': heightLabel,
    'countLabel': countLabel,
    'key': key,
    'grade': grade,
    'label': label,
    'caption': caption,
    'className': className,
    'reportTime': reportTime,
    'headline': headline,
    'reportNumber': reportNumber,
    'regionCount': regionCount,
    'rows': [for (final row in rows) row.toMap()],
  };
}

class JmaTsunamiListRow {
  final String name, height, arrivalTime, condition, arrivalLabel;
  final String heightTime;
  final String regionName, stationCode;
  final List<JmaTsunamiListField> secondary, details;
  JmaTsunamiListRow.fromMap(Map map)
    : name = map['name'] as String,
      height = map['height'] as String,
      arrivalTime = map['arrivalTime'] as String,
      condition = map['condition'] as String,
      heightTime = map['heightTime'] as String? ?? '',
      regionName = map['regionName'] as String? ?? '',
      stationCode = map['stationCode'] as String? ?? '',
      secondary = [
        for (final v in map['secondary'] as List? ?? const [])
          JmaTsunamiListField.fromMap(v as Map),
      ],
      details = [
        for (final v in map['details'] as List? ?? const [])
          JmaTsunamiListField.fromMap(v as Map),
      ],
      arrivalLabel = map['arrivalLabel'] as String;

  Map<String, dynamic> toMap() => {
    'name': name,
    'height': height,
    'arrivalTime': arrivalTime,
    'condition': condition,
    'arrivalLabel': arrivalLabel,
    'heightTime': heightTime,
    'regionName': regionName,
    'stationCode': stationCode,
    'secondary': [for (final field in secondary) field.toMap()],
    'details': [for (final field in details) field.toMap()],
  };
}

class JmaTsunamiListField {
  final String label, text, time;
  JmaTsunamiListField.fromMap(Map map)
    : label = map['label'] as String? ?? '',
      text = map['text'] as String? ?? '',
      time = map['time'] as String? ?? '';
  Map<String, dynamic> toMap() => {'label': label, 'text': text, 'time': time};
}
