class ReplayPackageManifest {
  final int schemaVersion;
  final String packageId;
  final String caseType;
  final String timeZone;
  final DateTime startTime;
  final DateTime endTime;
  final int expectedFrameIntervalMs;
  final int expectedTimestampCount;
  final String decoderVersion;
  final String stationDbVersion;
  final String sensorSelectionPolicy;
  final String rawLayout;
  final String frameIndexPath;
  final String stationSnapshotPath;
  final String? truthPath;
  final List<String> layers;
  final List<ReplayMissingFrame> missingFrames;
  final Map<String, String> sourceUrlTemplates;
  final Map<String, Object?> provenance;

  const ReplayPackageManifest({
    required this.schemaVersion,
    required this.packageId,
    required this.caseType,
    required this.timeZone,
    required this.startTime,
    required this.endTime,
    required this.expectedFrameIntervalMs,
    required this.expectedTimestampCount,
    required this.decoderVersion,
    required this.stationDbVersion,
    required this.sensorSelectionPolicy,
    required this.rawLayout,
    required this.frameIndexPath,
    required this.stationSnapshotPath,
    required this.truthPath,
    required this.layers,
    required this.missingFrames,
    required this.sourceUrlTemplates,
    required this.provenance,
  });

  factory ReplayPackageManifest.fromJson(Map<String, Object?> json) {
    return ReplayPackageManifest(
      schemaVersion: json['schemaVersion']! as int,
      packageId: json['packageId']! as String,
      caseType: json['caseType']! as String,
      timeZone: json['timeZone']! as String,
      startTime: DateTime.parse(json['startTime']! as String),
      endTime: DateTime.parse(json['endTime']! as String),
      expectedFrameIntervalMs: json['expectedFrameIntervalMs']! as int,
      expectedTimestampCount: json['expectedTimestampCount']! as int,
      decoderVersion: json['decoderVersion']! as String,
      stationDbVersion: json['stationDbVersion']! as String,
      sensorSelectionPolicy: json['sensorSelectionPolicy']! as String,
      rawLayout: json['rawLayout']! as String,
      frameIndexPath: json['frameIndexPath']! as String,
      stationSnapshotPath: json['stationSnapshotPath']! as String,
      truthPath: json['truthPath'] as String?,
      layers: (json['layers']! as List<Object?>).cast<String>(),
      missingFrames: (json['missingFrames']! as List<Object?>)
          .map(
            (entry) =>
                ReplayMissingFrame.fromJson(entry! as Map<String, Object?>),
          )
          .toList(growable: false),
      sourceUrlTemplates: (json['sourceUrlTemplates']! as Map<String, Object?>)
          .map((key, value) => MapEntry(key, value! as String)),
      provenance: json['provenance']! as Map<String, Object?>,
    );
  }

  List<String> validate() {
    final issues = <String>[];
    if (schemaVersion != 1) issues.add('unsupported_schema_version');
    if (packageId.isEmpty) issues.add('missing_package_id');
    if (caseType != 'event' && caseType != 'noise') {
      issues.add('invalid_case_type');
    }
    if (timeZone != 'Asia/Tokyo') issues.add('unsupported_time_zone');
    if (!startTime.isBefore(endTime)) issues.add('invalid_time_range');
    if (expectedFrameIntervalMs <= 0) {
      issues.add('invalid_frame_interval');
    } else {
      final durationMs = endTime.difference(startTime).inMilliseconds;
      if (durationMs % expectedFrameIntervalMs != 0) {
        issues.add('time_range_not_aligned_to_frame_interval');
      } else if (expectedTimestampCount !=
          durationMs ~/ expectedFrameIntervalMs + 1) {
        issues.add('expected_timestamp_count_mismatch');
      }
    }
    if (decoderVersion.isEmpty) issues.add('missing_decoder_version');
    if (stationDbVersion.isEmpty) issues.add('missing_station_db_version');
    if (sensorSelectionPolicy.isEmpty) {
      issues.add('missing_sensor_selection_policy');
    }
    if (layers.isEmpty || layers.toSet().length != layers.length) {
      issues.add('invalid_layers');
    }
    if (caseType == 'event' && truthPath == null) {
      issues.add('missing_event_truth_path');
    }
    for (final path in [frameIndexPath, stationSnapshotPath, ?truthPath]) {
      if (!_isSafeRelativePath(path)) issues.add('unsafe_path:$path');
    }
    final missingKeys = <String>{};
    for (final missing in missingFrames) {
      if (!layers.contains(missing.layer)) {
        issues.add('unknown_missing_frame_layer:${missing.layer}');
      }
      final key = '${missing.observedAt.toIso8601String()}:${missing.layer}';
      if (!missingKeys.add(key)) issues.add('duplicate_missing_frame:$key');
    }
    return issues;
  }

  bool _isSafeRelativePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.isNotEmpty &&
        !normalized.startsWith('/') &&
        !normalized.contains('../') &&
        !RegExp(r'^[A-Za-z]:').hasMatch(normalized);
  }
}

class ReplayMissingFrame {
  final DateTime observedAt;
  final String layer;
  final String reason;

  const ReplayMissingFrame({
    required this.observedAt,
    required this.layer,
    required this.reason,
  });

  factory ReplayMissingFrame.fromJson(Map<String, Object?> json) {
    return ReplayMissingFrame(
      observedAt: DateTime.parse(json['observedAt']! as String),
      layer: json['layer']! as String,
      reason: json['reason']! as String,
    );
  }
}

class ReplayFrameIndex {
  final int schemaVersion;
  final String packageId;
  final List<ReplayFrameRecord> frames;

  const ReplayFrameIndex({
    required this.schemaVersion,
    required this.packageId,
    required this.frames,
  });

  factory ReplayFrameIndex.fromJson(Map<String, Object?> json) {
    return ReplayFrameIndex(
      schemaVersion: json['schemaVersion']! as int,
      packageId: json['packageId']! as String,
      frames: (json['frames']! as List<Object?>)
          .map(
            (entry) =>
                ReplayFrameRecord.fromJson(entry! as Map<String, Object?>),
          )
          .toList(growable: false),
    );
  }

  List<String> validateAgainst(ReplayPackageManifest manifest) {
    final issues = <String>[];
    if (schemaVersion != manifest.schemaVersion) {
      issues.add('frame_index_schema_mismatch');
    }
    if (packageId != manifest.packageId) {
      issues.add('frame_index_package_id_mismatch');
    }
    if (frames.length != manifest.expectedTimestampCount) {
      issues.add('frame_index_count_mismatch');
    }
    DateTime? previous;
    for (final frame in frames) {
      if (previous != null &&
          frame.observedAt.difference(previous).inMilliseconds !=
              manifest.expectedFrameIntervalMs) {
        issues.add('non_contiguous_frame_index:${frame.observedAt}');
      }
      previous = frame.observedAt;
      if (frame.layers.keys
          .toSet()
          .difference(manifest.layers.toSet())
          .isNotEmpty) {
        issues.add('frame_index_unknown_layer:${frame.observedAt}');
      }
      if (frame.layers.keys
              .toSet()
              .difference(manifest.layers.toSet())
              .isEmpty &&
          frame.layers.length != manifest.layers.length) {
        issues.add('frame_index_missing_layer:${frame.observedAt}');
      }
      for (final entry in frame.layers.entries) {
        final layer = entry.value;
        if (layer.available) {
          if (layer.path == null || layer.bytes == null || layer.bytes! <= 0) {
            issues.add(
              'incomplete_available_layer:${frame.observedAt}:${entry.key}',
            );
          }
          if (layer.path != null && !_isSafeRelativePath(layer.path!)) {
            issues.add(
              'unsafe_layer_path:${frame.observedAt}:${entry.key}:${layer.path}',
            );
          }
        } else if (layer.path != null || layer.bytes != null) {
          issues.add(
            'unexpected_missing_layer_file:${frame.observedAt}:${entry.key}',
          );
        }
      }
    }
    if (frames.isNotEmpty) {
      if (frames.first.observedAt != manifest.startTime) {
        issues.add('frame_index_start_mismatch');
      }
      if (frames.last.observedAt != manifest.endTime) {
        issues.add('frame_index_end_mismatch');
      }
    }
    return issues;
  }

  bool _isSafeRelativePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.isNotEmpty &&
        !normalized.startsWith('/') &&
        !normalized.contains('../') &&
        !RegExp(r'^[A-Za-z]:').hasMatch(normalized);
  }
}

class ReplayFrameRecord {
  final DateTime observedAt;
  final DateTime? receivedAt;
  final Map<String, ReplayLayerRecord> layers;

  const ReplayFrameRecord({
    required this.observedAt,
    required this.receivedAt,
    required this.layers,
  });

  factory ReplayFrameRecord.fromJson(Map<String, Object?> json) {
    return ReplayFrameRecord(
      observedAt: DateTime.parse(json['observedAt']! as String),
      receivedAt: json['receivedAt'] == null
          ? null
          : DateTime.parse(json['receivedAt']! as String),
      layers: (json['layers']! as Map<String, Object?>).map(
        (key, value) => MapEntry(
          key,
          ReplayLayerRecord.fromJson(value! as Map<String, Object?>),
        ),
      ),
    );
  }
}

class ReplayLayerRecord {
  final bool available;
  final String? path;
  final int? bytes;
  final String? sha256;
  final String? sourceUrl;
  final DateTime? requestStartedAt;
  final DateTime? receivedAt;
  final DateTime? retrievedAt;
  final double? retrievalDurationMs;
  final double? receiveDelayMs;
  final int? attempts;
  final Set<String> qualityFlags;

  const ReplayLayerRecord({
    required this.available,
    required this.path,
    required this.bytes,
    required this.sha256,
    required this.sourceUrl,
    required this.requestStartedAt,
    required this.receivedAt,
    required this.retrievedAt,
    required this.retrievalDurationMs,
    required this.receiveDelayMs,
    required this.attempts,
    required this.qualityFlags,
  });

  factory ReplayLayerRecord.fromJson(Map<String, Object?> json) {
    return ReplayLayerRecord(
      available: json['available']! as bool,
      path: json['path'] as String?,
      bytes: json['bytes'] as int?,
      sha256: json['sha256'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      requestStartedAt: json['requestStartedAt'] == null
          ? null
          : DateTime.parse(json['requestStartedAt']! as String),
      receivedAt: json['receivedAt'] == null
          ? null
          : DateTime.parse(json['receivedAt']! as String),
      retrievedAt: json['retrievedAt'] == null
          ? null
          : DateTime.parse(json['retrievedAt']! as String),
      retrievalDurationMs: (json['retrievalDurationMs'] as num?)?.toDouble(),
      receiveDelayMs: (json['receiveDelayMs'] as num?)?.toDouble(),
      attempts: json['attempts'] as int?,
      qualityFlags: (json['qualityFlags']! as List<Object?>)
          .cast<String>()
          .toSet(),
    );
  }
}
