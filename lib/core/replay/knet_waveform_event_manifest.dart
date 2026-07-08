const knetWaveformDownloadManifestVersion =
    'knet_waveform_download_manifest_v1';

enum KnetDownloadCollection { all, knet, kik, kik0 }

class KnetWaveformEventCandidate {
  const KnetWaveformEventCandidate({
    required this.eventId,
    required this.originTimeUtc,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
    required this.eventLabels,
    required this.niedDirectoryId,
    required this.source,
    required this.notes,
  });

  final String eventId;
  final DateTime originTimeUtc;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double magnitude;
  final List<String> eventLabels;
  final String niedDirectoryId;
  final String source;
  final String? notes;

  DateTime get originTimeJst => originTimeUtc.add(const Duration(hours: 9));

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'originTimeUtc': originTimeUtc.toIso8601String(),
    'originTimeJst': _formatJst(originTimeJst),
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
    'eventLabels': eventLabels,
    'niedDirectoryId': niedDirectoryId,
    'source': source,
    'notes': notes,
  };
}

class KnetWaveformDownloadTarget {
  const KnetWaveformDownloadTarget({
    required this.collection,
    required this.format,
    required this.url,
    required this.requiresRegistration,
    required this.qualityFlags,
  });

  final KnetDownloadCollection collection;
  final String format;
  final String url;
  final bool requiresRegistration;
  final List<String> qualityFlags;

  Map<String, Object?> toJson() => {
    'collection': collection.name,
    'format': format,
    'url': url,
    'requiresRegistration': requiresRegistration,
    'qualityFlags': qualityFlags,
  };
}

class KnetWaveformDownloadPlan {
  const KnetWaveformDownloadPlan({
    required this.schemaVersion,
    required this.generatedAtUtc,
    required this.events,
    required this.targetsByEventId,
    required this.provenance,
  });

  final String schemaVersion;
  final DateTime generatedAtUtc;
  final List<KnetWaveformEventCandidate> events;
  final Map<String, List<KnetWaveformDownloadTarget>> targetsByEventId;
  final Map<String, Object?> provenance;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'generatedAtUtc': generatedAtUtc.toIso8601String(),
    'provenance': provenance,
    'events': events.map((event) => event.toJson()).toList(),
    'targetsByEventId': {
      for (final entry in targetsByEventId.entries)
        entry.key: entry.value.map((target) => target.toJson()).toList(),
    },
  };
}

class KnetWaveformDownloadPlanner {
  const KnetWaveformDownloadPlanner({
    this.baseUrl = 'https://www.kyoshin.bosai.go.jp/kyoshin/download',
  });

  final String baseUrl;

  KnetWaveformDownloadPlan buildPlan(
    List<KnetWaveformEventCandidate> events, {
    List<KnetDownloadCollection> collections = const [
      KnetDownloadCollection.all,
      KnetDownloadCollection.knet,
      KnetDownloadCollection.kik,
    ],
    List<String> formats = const ['ascii', 'csv'],
  }) {
    final sortedEvents = events.toList()
      ..sort((a, b) => a.originTimeUtc.compareTo(b.originTimeUtc));
    return KnetWaveformDownloadPlan(
      schemaVersion: knetWaveformDownloadManifestVersion,
      generatedAtUtc: DateTime.now().toUtc(),
      events: sortedEvents,
      targetsByEventId: {
        for (final event in sortedEvents)
          event.eventId: [
            for (final collection in collections)
              for (final format in formats)
                _target(event, collection: collection, format: format),
          ],
      },
      provenance: const {
        'source': 'NIED K-NET/KiK-net HTTPS directory semantics',
        'requiresRegistration': true,
        'downloadPolicy':
            'manifest_only_no_credentials_or_waveform_redistribution',
        'directoryIdPolicy':
            'explicit_niedDirectoryId_required_to_avoid_origin_second_guessing',
      },
    );
  }

  KnetWaveformDownloadTarget _target(
    KnetWaveformEventCandidate event, {
    required KnetDownloadCollection collection,
    required String format,
  }) {
    final id = event.niedDirectoryId;
    if (!RegExp(r'^\d{14}$').hasMatch(id)) {
      throw FormatException('Invalid NIED directory id: $id');
    }
    final year = id.substring(0, 4);
    final month = id.substring(4, 6);
    final url =
        '$baseUrl/${collection.name}/zip/$year/$month/$id/${id}_$format.zip';
    final qualityFlags = <String>[
      'requires_nied_registration',
      'explicit_directory_id',
      if (collection == KnetDownloadCollection.kik0)
        'kik0_includes_not_officially_released_records',
    ];
    return KnetWaveformDownloadTarget(
      collection: collection,
      format: format,
      url: url,
      requiresRegistration: true,
      qualityFlags: qualityFlags,
    );
  }
}

KnetWaveformEventCandidate parseKnetWaveformEventCandidate(
  Map<String, Object?> json,
) {
  return KnetWaveformEventCandidate(
    eventId: json['eventId']! as String,
    originTimeUtc: DateTime.parse(json['originTimeUtc']! as String).toUtc(),
    latitude: _number(json['latitude']),
    longitude: _number(json['longitude']),
    depthKm: _number(json['depthKm']),
    magnitude: _number(json['magnitude']),
    eventLabels: (json['eventLabels'] as List<Object?>? ?? const [])
        .cast<String>()
        .toList(growable: false),
    niedDirectoryId: json['niedDirectoryId']! as String,
    source: json['source'] as String? ?? 'manual',
    notes: json['notes'] as String?,
  );
}

String suggestedKnetNiedDirectoryId(DateTime originTimeUtc) {
  final jst = originTimeUtc.toUtc().add(const Duration(hours: 9));
  final second = jst.second < 30 ? '00' : '30';
  return '${jst.year.toString().padLeft(4, '0')}'
      '${jst.month.toString().padLeft(2, '0')}'
      '${jst.day.toString().padLeft(2, '0')}'
      '${jst.hour.toString().padLeft(2, '0')}'
      '${jst.minute.toString().padLeft(2, '0')}'
      '$second';
}

String _formatJst(DateTime utcPlusNine) =>
    '${utcPlusNine.year.toString().padLeft(4, '0')}-'
    '${utcPlusNine.month.toString().padLeft(2, '0')}-'
    '${utcPlusNine.day.toString().padLeft(2, '0')}T'
    '${utcPlusNine.hour.toString().padLeft(2, '0')}:'
    '${utcPlusNine.minute.toString().padLeft(2, '0')}:'
    '${utcPlusNine.second.toString().padLeft(2, '0')}+09:00';

double _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.parse(value);
  return double.nan;
}
