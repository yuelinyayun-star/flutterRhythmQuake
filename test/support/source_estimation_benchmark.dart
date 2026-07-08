import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/core/event_detection/robust_station_trigger_detector.dart';
import 'package:flutterrhythmquake/core/event_detection/spatiotemporal_event_detector.dart';
import 'package:flutterrhythmquake/core/hypocenter_estimator.dart';
import 'package:flutterrhythmquake/core/replay/replay_metrics.dart';
import 'package:flutterrhythmquake/core/source_estimation/jma2001_travel_time_approximation.dart';
import 'package:flutterrhythmquake/core/source_estimation/seismic_source_tracker.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_trigger.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_trigger_continuity_gate.dart';
import 'package:flutterrhythmquake/core/source_estimation/station_event_tracker.dart';
import 'package:flutterrhythmquake/services/sources/lmoni_image_service.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';
import 'package:flutterrhythmquake/services/sources/nied_source_estimation_driver.dart';
import 'package:flutterrhythmquake/services/sources/nied_station_observation_adapter.dart';
import 'package:flutterrhythmquake/services/sources/shake_detection_service.dart';

import 'nied_replay_fixture.dart';

enum SourceEstimationReplayCaseType { event, noise }

enum SourceEstimationBenchmarkInputMode { dualLayer, surfaceImageOnly }

extension SourceEstimationBenchmarkInputModeInfo
    on SourceEstimationBenchmarkInputMode {
  String get id => switch (this) {
    SourceEstimationBenchmarkInputMode.dualLayer => 'jma_s_plus_jma_b',
    SourceEstimationBenchmarkInputMode.surfaceImageOnly => 'jma_s_only',
  };

  List<String> get layers => switch (this) {
    SourceEstimationBenchmarkInputMode.dualLayer => const ['jma_s', 'jma_b'],
    SourceEstimationBenchmarkInputMode.surfaceImageOnly => const ['jma_s'],
  };

  bool get usesBoreholeImage =>
      this == SourceEstimationBenchmarkInputMode.dualLayer;
}

class ReplayEventLabels {
  final bool catalogEvent;
  final bool catalogTruthVerified;
  final bool? observableEvent;
  final bool? detectableEvent;
  final bool includeInDetectionMetrics;

  const ReplayEventLabels({
    required this.catalogEvent,
    required this.catalogTruthVerified,
    required this.observableEvent,
    required this.detectableEvent,
    required this.includeInDetectionMetrics,
  });

  factory ReplayEventLabels.fromJson(
    Map<String, Object?>? json,
    SourceEstimationReplayCaseType caseType,
  ) {
    if (json == null) {
      final isEvent = caseType == SourceEstimationReplayCaseType.event;
      return ReplayEventLabels(
        catalogEvent: isEvent,
        catalogTruthVerified: false,
        observableEvent: isEvent ? true : false,
        detectableEvent: isEvent ? true : false,
        includeInDetectionMetrics: isEvent,
      );
    }
    final labels = ReplayEventLabels(
      catalogEvent: json['catalogEvent']! as bool,
      catalogTruthVerified: json['catalogTruthVerified']! as bool,
      observableEvent: json['observableEvent'] as bool?,
      detectableEvent: json['detectableEvent'] as bool?,
      includeInDetectionMetrics: json['includeInDetectionMetrics']! as bool,
    );
    if (labels.includeInDetectionMetrics &&
        (!labels.catalogEvent ||
            labels.observableEvent != true ||
            labels.detectableEvent != true)) {
      throw FormatException(
        'Detection metric targets must be catalog, observable, and detectable.',
      );
    }
    return labels;
  }

  Map<String, Object?> toJson() => {
    'catalogEvent': catalogEvent,
    'catalogTruthVerified': catalogTruthVerified,
    'observableEvent': observableEvent,
    'detectableEvent': detectableEvent,
    'includeInDetectionMetrics': includeInDetectionMetrics,
  };
}

class SourceEstimationReplayTruth {
  final DateTime originTimeJst;
  final LatLng epicenter;
  final double? depthKm;
  final double? magnitude;
  final String source;

  const SourceEstimationReplayTruth({
    required this.originTimeJst,
    required this.epicenter,
    required this.depthKm,
    required this.magnitude,
    required this.source,
  });

  factory SourceEstimationReplayTruth.fromJson(Map<String, Object?> json) {
    return SourceEstimationReplayTruth(
      originTimeJst: _parseJstWallClock(json['originTimeJst']! as String),
      epicenter: LatLng(
        (json['latitude']! as num).toDouble(),
        (json['longitude']! as num).toDouble(),
      ),
      depthKm: (json['depthKm'] as num?)?.toDouble(),
      magnitude: (json['magnitude'] as num?)?.toDouble(),
      source: json['source']! as String,
    );
  }

  Map<String, Object?> toJson() => {
    'originTimeJst': originTimeJst.toIso8601String(),
    'latitude': epicenter.latitude,
    'longitude': epicenter.longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
    'source': source,
  };
}

class SourceEstimationReplayCase {
  final int schemaVersion;
  final String caseId;
  final SourceEstimationReplayCaseType caseType;
  final Directory captureDirectory;
  final String captureDirectoryReference;
  final String gifNamePattern;
  final DateTime startTimeJst;
  final DateTime endTimeJst;
  final int sensitivity;
  final SourceEstimationReplayTruth? truth;
  final ReplayEventLabels eventLabels;
  final Map<String, Object?> classification;

  const SourceEstimationReplayCase({
    required this.schemaVersion,
    required this.caseId,
    required this.caseType,
    required this.captureDirectory,
    required this.captureDirectoryReference,
    required this.gifNamePattern,
    required this.startTimeJst,
    required this.endTimeJst,
    required this.sensitivity,
    required this.truth,
    required this.eventLabels,
    required this.classification,
  });

  factory SourceEstimationReplayCase.fromManifest(
    File manifest, {
    Directory? workspaceRoot,
    Directory? captureDirectoryOverride,
  }) {
    final json =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    final root = workspaceRoot ?? Directory.current;
    final caseType = SourceEstimationReplayCaseType.values.byName(
      json['caseType']! as String,
    );
    final captureDirectory =
        captureDirectoryOverride ??
        _resolveReplayCaptureDirectory(
          root,
          json['captureDirectory']! as String,
        );
    return SourceEstimationReplayCase(
      schemaVersion: json['schemaVersion']! as int,
      caseId: json['caseId']! as String,
      caseType: caseType,
      captureDirectory: captureDirectory,
      captureDirectoryReference: json['captureDirectory']! as String,
      gifNamePattern: json['gifNamePattern']! as String,
      startTimeJst: _parseJstWallClock(json['startTimeJst']! as String),
      endTimeJst: _parseJstWallClock(json['endTimeJst']! as String),
      sensitivity: json['sensitivity']! as int,
      truth: json['truth'] == null
          ? null
          : SourceEstimationReplayTruth.fromJson(
              json['truth']! as Map<String, Object?>,
            ),
      eventLabels: ReplayEventLabels.fromJson(
        json['eventLabels'] as Map<String, Object?>?,
        caseType,
      ),
      classification:
          (json['classification'] as Map<String, Object?>?) ?? const {},
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'caseId': caseId,
    'caseType': caseType.name,
    'captureDirectory': captureDirectoryReference,
    'timeZone': 'Asia/Tokyo',
    'gifNamePattern': gifNamePattern,
    'startTimeJst': startTimeJst.toIso8601String(),
    'endTimeJst': endTimeJst.toIso8601String(),
    'sensitivity': sensitivity,
    'truth': truth?.toJson(),
    'eventLabels': eventLabels.toJson(),
    'classification': classification,
  };

  String gifFileName(DateTime observedAt, String layer) {
    return gifNamePattern
        .replaceAll('{stamp}', formatNiedTimeKey(observedAt))
        .replaceAll('{layer}', layer);
  }
}

Directory _resolveReplayCaptureDirectory(Directory root, String reference) {
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(reference) ||
      reference.startsWith(r'\\')) {
    return Directory(reference);
  }
  return Directory.fromUri(root.uri.resolve(reference.replaceAll('\\', '/')));
}

class SourceEstimationBenchmarkReport {
  final SourceEstimationReplayCase replayCase;
  final int requestedFrameCount;
  final int decodedFrameCount;
  final List<SourceEstimationFrameReport> frames;
  final SourceEstimationDetectionCaseSummary detectionSummary;
  final Map<String, SourceEstimationMethodSummary> summaries;

  const SourceEstimationBenchmarkReport({
    required this.replayCase,
    required this.requestedFrameCount,
    required this.decodedFrameCount,
    required this.frames,
    required this.detectionSummary,
    required this.summaries,
  });

  Map<String, Object?> toJson() => {
    'reportSchemaVersion': 1,
    'case': replayCase.toJson(),
    'requestedFrameCount': requestedFrameCount,
    'decodedFrameCount': decodedFrameCount,
    'detectionSummary': detectionSummary.toJson(),
    'summaries': summaries.map((key, value) => MapEntry(key, value.toJson())),
    'frames': frames.map((frame) => frame.toJson()).toList(growable: false),
  };

  void writeJson(File output) {
    output.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    output.writeAsStringSync('${encoder.convert(_jsonEncodable(toJson()))}\n');
  }
}

Object? _jsonEncodable(Object? value) {
  if (value is double) {
    return value.isFinite ? value : null;
  }
  if (value is num) return value;
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _jsonEncodable(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_jsonEncodable).toList(growable: false);
  }
  return value;
}

class SourceEstimationFrameReport {
  final DateTime observedAtJst;
  final bool decoded;
  final String detectionStage;
  final EventDetection? eventDetection;
  final int activeStationCount;
  final int maxShindo;
  final int maxStationDetectLevel;
  final double maxStationActivity;
  final Map<String, Object?> sourceTriggerMetadata;
  final Map<String, SourceEstimationMethodFrame> methods;

  const SourceEstimationFrameReport({
    required this.observedAtJst,
    required this.decoded,
    required this.detectionStage,
    required this.eventDetection,
    required this.activeStationCount,
    required this.maxShindo,
    required this.maxStationDetectLevel,
    required this.maxStationActivity,
    this.sourceTriggerMetadata = const {},
    required this.methods,
  });

  Map<String, Object?> toJson() => {
    'observedAtJst': observedAtJst.toIso8601String(),
    'decoded': decoded,
    'detectionStage': detectionStage,
    'eventDetection': _eventDetectionToJson(eventDetection),
    'activeStationCount': activeStationCount,
    'maxShindo': maxShindo,
    'maxStationDetectLevel': maxStationDetectLevel,
    'maxStationActivity': maxStationActivity,
    'sourceTriggerMetadata': sourceTriggerMetadata,
    'methods': methods.map((key, value) => MapEntry(key, value.toJson())),
  };
}

class SourceEstimationDetectionCaseSummary {
  final String detectorId;
  final SourceEstimationReplayCaseType caseType;
  final int decodedFrameCount;
  final int candidateFrameCount;
  final int confirmedFrameCount;
  final int maxActiveStationCount;
  final int maxShindo;
  final int maxStationDetectLevel;
  final double maxStationActivity;
  final DateTime? firstCandidateAtJst;
  final DateTime? firstConfirmedAtJst;
  final double? firstCandidateDelaySeconds;
  final double? firstConfirmedDelaySeconds;

  const SourceEstimationDetectionCaseSummary({
    required this.detectorId,
    required this.caseType,
    required this.decodedFrameCount,
    required this.candidateFrameCount,
    required this.confirmedFrameCount,
    required this.maxActiveStationCount,
    required this.maxShindo,
    required this.maxStationDetectLevel,
    required this.maxStationActivity,
    required this.firstCandidateAtJst,
    required this.firstConfirmedAtJst,
    required this.firstCandidateDelaySeconds,
    required this.firstConfirmedDelaySeconds,
  });

  bool get hasCandidate => candidateFrameCount > 0;

  bool get hasConfirmed => confirmedFrameCount > 0;

  int get falseCandidateFrameCount =>
      caseType == SourceEstimationReplayCaseType.noise
      ? candidateFrameCount
      : 0;

  int get falseConfirmedFrameCount =>
      caseType == SourceEstimationReplayCaseType.noise
      ? confirmedFrameCount
      : 0;

  bool get missedCandidate =>
      caseType == SourceEstimationReplayCaseType.event && !hasCandidate;

  bool get missedConfirmed =>
      caseType == SourceEstimationReplayCaseType.event && !hasConfirmed;

  Map<String, Object?> toJson() => {
    'detectorId': detectorId,
    'caseType': caseType.name,
    'decodedFrameCount': decodedFrameCount,
    'candidateFrameCount': candidateFrameCount,
    'confirmedFrameCount': confirmedFrameCount,
    'maxActiveStationCount': maxActiveStationCount,
    'maxShindo': maxShindo,
    'maxStationDetectLevel': maxStationDetectLevel,
    'maxStationActivity': maxStationActivity,
    'firstCandidateAtJst': firstCandidateAtJst?.toIso8601String(),
    'firstConfirmedAtJst': firstConfirmedAtJst?.toIso8601String(),
    'firstCandidateDelaySeconds': firstCandidateDelaySeconds,
    'firstConfirmedDelaySeconds': firstConfirmedDelaySeconds,
    'missedCandidate': missedCandidate,
    'missedConfirmed': missedConfirmed,
    'falseCandidateFrameCount': falseCandidateFrameCount,
    'falseConfirmedFrameCount': falseConfirmedFrameCount,
  };
}

Map<String, Object?>? _eventDetectionToJson(EventDetection? detection) {
  if (detection == null) return null;
  return {
    'detectorId': detection.detectorId,
    'sourceId': detection.sourceId,
    'eventId': detection.eventId,
    'state': detection.state.name,
    'observedAt': detection.observedAt.toIso8601String(),
    'startedAt': detection.startedAt?.toIso8601String(),
    'updatedAt': detection.updatedAt?.toIso8601String(),
    'endedAt': detection.endedAt?.toIso8601String(),
    'memberStationIds': detection.memberStationIds,
    'detectionScore': detection.detectionScore,
    'maxIntensity': detection.maxIntensity,
    'reasonCodes': detection.reasonCodes.toList(growable: false),
    'metadata': detection.metadata,
  };
}

EventDetection _continuityAwareEventDetection(
  EventDetection detection,
  SourceTriggerContinuityDecision continuity,
) {
  return EventDetection(
    detectorId: detection.detectorId,
    sourceId: detection.sourceId,
    eventId: continuity.effectiveEventId ?? detection.eventId,
    state: detection.state,
    observedAt: detection.observedAt,
    startedAt: detection.startedAt,
    updatedAt: detection.updatedAt,
    endedAt: detection.endedAt,
    memberStationIds: continuity.heldReplacement
        ? continuity.effectiveMemberStationIds
        : detection.memberStationIds,
    detectionScore: detection.detectionScore,
    maxIntensity: detection.maxIntensity,
    reasonCodes: {
      ...detection.reasonCodes,
      if (continuity.heldReplacement) 'source_trigger_replacement_held',
    },
    metadata: {...detection.metadata, ...continuity.metadata},
  );
}

class SourceEstimationMethodFrame {
  final SourceEstimate? estimate;
  final double? errorKm;
  final double? jumpKm;
  final int runtimeMicros;
  final Map<String, Object?> eventMetadata;

  const SourceEstimationMethodFrame({
    required this.estimate,
    required this.errorKm,
    required this.jumpKm,
    required this.runtimeMicros,
    this.eventMetadata = const {},
  });

  Map<String, Object?> toJson() => {
    'estimate': estimate == null
        ? null
        : {
            'latitude': estimate!.latitude,
            'longitude': estimate!.longitude,
            'depthKm': estimate!.depthKm,
            'originTime': estimate!.originTime?.toIso8601String(),
            'confidence': estimate!.confidence,
            'method': estimate!.method,
            'supportingStationCount': estimate!.supportingStationCount,
            'diagnostics': estimate!.diagnostics,
          },
    'errorKm': errorKm,
    'jumpKm': jumpKm,
    'runtimeMicros': runtimeMicros,
    'eventMetadata': eventMetadata,
  };
}

class SourceEstimationMethodSummary {
  final String methodId;
  final int estimateCount;
  final DateTime? firstEstimateAtJst;
  final double? firstEstimateDelaySeconds;
  final double? medianErrorKm;
  final double? p90ErrorKm;
  final Map<String, double?> errorAtSeconds;
  final double? medianJumpKm;
  final double? p90JumpKm;
  final double p95RuntimeMicros;
  final int falseEstimateFrameCount;

  const SourceEstimationMethodSummary({
    required this.methodId,
    required this.estimateCount,
    required this.firstEstimateAtJst,
    required this.firstEstimateDelaySeconds,
    required this.medianErrorKm,
    required this.p90ErrorKm,
    required this.errorAtSeconds,
    required this.medianJumpKm,
    required this.p90JumpKm,
    required this.p95RuntimeMicros,
    required this.falseEstimateFrameCount,
  });

  Map<String, Object?> toJson() => {
    'methodId': methodId,
    'estimateCount': estimateCount,
    'firstEstimateAtJst': firstEstimateAtJst?.toIso8601String(),
    'firstEstimateDelaySeconds': firstEstimateDelaySeconds,
    'medianErrorKm': medianErrorKm,
    'p90ErrorKm': p90ErrorKm,
    'errorAtSeconds': errorAtSeconds,
    'medianJumpKm': medianJumpKm,
    'p90JumpKm': p90JumpKm,
    'p95RuntimeMicros': p95RuntimeMicros,
    'falseEstimateFrameCount': falseEstimateFrameCount,
  };
}

class SourceEstimationBenchmarkSuite {
  final int schemaVersion;
  final String suiteId;
  final List<File> caseManifests;

  const SourceEstimationBenchmarkSuite({
    required this.schemaVersion,
    required this.suiteId,
    required this.caseManifests,
  });

  factory SourceEstimationBenchmarkSuite.fromManifest(File manifest) {
    final json =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    final caseNames = (json['cases']! as List<Object?>).cast<String>();
    return SourceEstimationBenchmarkSuite(
      schemaVersion: json['schemaVersion']! as int,
      suiteId: json['suiteId']! as String,
      caseManifests: caseNames
          .map((name) => File.fromUri(manifest.parent.uri.resolve(name)))
          .toList(growable: false),
    );
  }
}

class SourceEstimationBatchReport {
  final String suiteId;
  final List<SourceEstimationBenchmarkReport> cases;
  final SourceEstimationBatchDetectionSummary detectionSummary;
  final Map<String, SourceEstimationBatchMethodSummary> summaries;

  const SourceEstimationBatchReport({
    required this.suiteId,
    required this.cases,
    required this.detectionSummary,
    required this.summaries,
  });

  Map<String, Object?> toJson() => {
    'reportSchemaVersion': 1,
    'suiteId': suiteId,
    'caseCount': cases.length,
    'eventCaseCount': cases
        .where(
          (report) =>
              report.replayCase.caseType ==
              SourceEstimationReplayCaseType.event,
        )
        .length,
    'noiseCaseCount': cases
        .where(
          (report) =>
              report.replayCase.caseType ==
              SourceEstimationReplayCaseType.noise,
        )
        .length,
    'detectionSummary': detectionSummary.toJson(),
    'summaries': summaries.map((key, value) => MapEntry(key, value.toJson())),
    'cases': cases
        .map(
          (report) => {
            'caseId': report.replayCase.caseId,
            'caseType': report.replayCase.caseType.name,
            'requestedFrameCount': report.requestedFrameCount,
            'decodedFrameCount': report.decodedFrameCount,
            'detectionSummary': report.detectionSummary.toJson(),
            'summaries': report.summaries.map(
              (key, value) => MapEntry(key, value.toJson()),
            ),
          },
        )
        .toList(growable: false),
  };

  void writeJson(File output) {
    output.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    output.writeAsStringSync('${encoder.convert(toJson())}\n');
  }

  String toMarkdown() {
    final eventCaseCount = cases
        .where(
          (report) =>
              report.replayCase.caseType ==
              SourceEstimationReplayCaseType.event,
        )
        .length;
    final noiseCaseCount = cases.length - eventCaseCount;
    final buffer = StringBuffer()
      ..writeln('# 震源估算自动基线：`$suiteId`')
      ..writeln()
      ..writeln('> 此文件由基线测试自动生成，请勿手工修改。')
      ..writeln()
      ..writeln('案例总数：${cases.length}（事件 $eventCaseCount，静稳 $noiseCaseCount）')
      ..writeln()
      ..writeln('## 数据集')
      ..writeln()
      ..writeln('| 案例 | 类型 | 请求帧 | 解码帧 |')
      ..writeln('|---|---|---:|---:|');
    for (final report in cases) {
      buffer.writeln(
        '| `${_markdownCell(report.replayCase.caseId)}` '
        '| ${report.replayCase.caseType.name} '
        '| ${report.requestedFrameCount} '
        '| ${report.decodedFrameCount} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Event Detection Summary')
      ..writeln()
      ..writeln(
        '> Detection denominator: ${detectionSummary.eventCaseCount} eligible observable events; '
        '${detectionSummary.excludedEventCaseCount} of '
        '${detectionSummary.catalogEventCaseCount} catalog/reference events excluded.',
      )
      ..writeln()
      ..writeln(
        '| Detector | Candidate coverage | Confirmed coverage | Missed confirmed events | Noise candidate frames | Noise confirmed frames | Median candidate delay | Median confirmation delay |',
      )
      ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|')
      ..writeln(
        '| `${_markdownCell(detectionSummary.detectorId)}` '
        '| ${detectionSummary.eventCasesWithCandidate}/${detectionSummary.eventCaseCount} '
        '| ${detectionSummary.eventCasesConfirmed}/${detectionSummary.eventCaseCount} '
        '| ${detectionSummary.detectionMissedEventCount} '
        '| ${detectionSummary.noiseCandidateFrameCount}/${detectionSummary.noiseFrameCount} '
        '| ${detectionSummary.noiseConfirmedFrameCount}/${detectionSummary.noiseFrameCount} '
        '| ${_formatSeconds(detectionSummary.medianCandidateDelaySeconds)} '
        '| ${_formatSeconds(detectionSummary.medianConfirmationDelaySeconds)} |',
      );

    buffer
      ..writeln()
      ..writeln('## 方法汇总')
      ..writeln()
      ..writeln('| 方法 | 事件覆盖 | 漏估事件 | 静稳误报帧 | 中位误差 | P90误差 |')
      ..writeln('|---|---:|---:|---:|---:|---:|');
    for (final summary in summaries.values) {
      buffer.writeln(
        '| `${_markdownCell(summary.methodId)}` '
        '| ${summary.eventCasesWithEstimates}/${summary.eventCaseCount} '
        '| ${summary.missedEventCaseCount} '
        '| ${summary.noiseEstimateFrameCount}/${summary.noiseFrameCount} '
        '| ${_formatKilometers(summary.medianEventErrorKm)} '
        '| ${_formatKilometers(summary.p90EventErrorKm)} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## 分案例结果')
      ..writeln()
      ..writeln('| 案例 | 方法 | 输出帧 | 中位误差 | P90误差 | 误报帧 |')
      ..writeln('|---|---|---:|---:|---:|---:|');
    for (final report in cases) {
      for (final summary in report.summaries.values) {
        buffer.writeln(
          '| `${_markdownCell(report.replayCase.caseId)}` '
          '| `${_markdownCell(summary.methodId)}` '
          '| ${summary.estimateCount} '
          '| ${_formatKilometers(summary.medianErrorKm)} '
          '| ${_formatKilometers(summary.p90ErrorKm)} '
          '| ${summary.falseEstimateFrameCount} |',
        );
      }
    }
    return buffer.toString();
  }

  void writeMarkdown(File output) {
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(toMarkdown());
  }
}

class SourceEstimationBatchDetectionSummary {
  final String detectorId;
  final int catalogEventCaseCount;
  final int excludedEventCaseCount;
  final int eventCaseCount;
  final int eventCasesWithCandidate;
  final int eventCasesConfirmed;
  final int detectionMissedCandidateCount;
  final int detectionMissedEventCount;
  final int noiseCaseCount;
  final int noiseFrameCount;
  final int noiseCandidateFrameCount;
  final int noiseConfirmedFrameCount;
  final double falseCandidateFrameRate;
  final double falseConfirmedFrameRate;
  final double? medianCandidateDelaySeconds;
  final double? medianConfirmationDelaySeconds;

  const SourceEstimationBatchDetectionSummary({
    required this.detectorId,
    required this.catalogEventCaseCount,
    required this.excludedEventCaseCount,
    required this.eventCaseCount,
    required this.eventCasesWithCandidate,
    required this.eventCasesConfirmed,
    required this.detectionMissedCandidateCount,
    required this.detectionMissedEventCount,
    required this.noiseCaseCount,
    required this.noiseFrameCount,
    required this.noiseCandidateFrameCount,
    required this.noiseConfirmedFrameCount,
    required this.falseCandidateFrameRate,
    required this.falseConfirmedFrameRate,
    required this.medianCandidateDelaySeconds,
    required this.medianConfirmationDelaySeconds,
  });

  Map<String, Object?> toJson() => {
    'detectorId': detectorId,
    'catalogEventCaseCount': catalogEventCaseCount,
    'excludedEventCaseCount': excludedEventCaseCount,
    'eventCaseCount': eventCaseCount,
    'eventCasesWithCandidate': eventCasesWithCandidate,
    'eventCasesConfirmed': eventCasesConfirmed,
    'detectionMissedCandidateCount': detectionMissedCandidateCount,
    'detectionMissedEventCount': detectionMissedEventCount,
    'eventCandidateRate': eventCaseCount == 0
        ? null
        : eventCasesWithCandidate / eventCaseCount,
    'eventConfirmationRate': eventCaseCount == 0
        ? null
        : eventCasesConfirmed / eventCaseCount,
    'noiseCaseCount': noiseCaseCount,
    'noiseFrameCount': noiseFrameCount,
    'noiseCandidateFrameCount': noiseCandidateFrameCount,
    'noiseConfirmedFrameCount': noiseConfirmedFrameCount,
    'falseCandidateFrameRate': falseCandidateFrameRate,
    'falseConfirmedFrameRate': falseConfirmedFrameRate,
    'medianCandidateDelaySeconds': medianCandidateDelaySeconds,
    'medianConfirmationDelaySeconds': medianConfirmationDelaySeconds,
  };
}

class SourceEstimationBatchMethodSummary {
  final String methodId;
  final int eventCaseCount;
  final int eventCasesWithEstimates;
  final int missedEventCaseCount;
  final int confirmedEventCaseCount;
  final int confirmedEventCasesWithEstimates;
  final int sourceMissedConfirmedEventCount;
  final int noiseCaseCount;
  final int eventEstimateFrameCount;
  final int noiseEstimateFrameCount;
  final int noiseFrameCount;
  final int noiseCasesWithEstimates;
  final double? medianEventErrorKm;
  final double? p90EventErrorKm;
  final double falseEstimateFrameRate;

  const SourceEstimationBatchMethodSummary({
    required this.methodId,
    required this.eventCaseCount,
    required this.eventCasesWithEstimates,
    required this.missedEventCaseCount,
    required this.confirmedEventCaseCount,
    required this.confirmedEventCasesWithEstimates,
    required this.sourceMissedConfirmedEventCount,
    required this.noiseCaseCount,
    required this.eventEstimateFrameCount,
    required this.noiseEstimateFrameCount,
    required this.noiseFrameCount,
    required this.noiseCasesWithEstimates,
    required this.medianEventErrorKm,
    required this.p90EventErrorKm,
    required this.falseEstimateFrameRate,
  });

  Map<String, Object?> toJson() => {
    'methodId': methodId,
    'eventCaseCount': eventCaseCount,
    'eventCasesWithEstimates': eventCasesWithEstimates,
    'missedEventCaseCount': missedEventCaseCount,
    'eventCaseDetectionRate': eventCaseCount == 0
        ? null
        : eventCasesWithEstimates / eventCaseCount,
    'confirmedEventCaseCount': confirmedEventCaseCount,
    'confirmedEventCasesWithEstimates': confirmedEventCasesWithEstimates,
    'sourceMissedConfirmedEventCount': sourceMissedConfirmedEventCount,
    'confirmedEventSourceEstimateRate': confirmedEventCaseCount == 0
        ? null
        : confirmedEventCasesWithEstimates / confirmedEventCaseCount,
    'noiseCaseCount': noiseCaseCount,
    'eventEstimateFrameCount': eventEstimateFrameCount,
    'noiseEstimateFrameCount': noiseEstimateFrameCount,
    'noiseFrameCount': noiseFrameCount,
    'noiseCasesWithEstimates': noiseCasesWithEstimates,
    'medianEventErrorKm': medianEventErrorKm,
    'p90EventErrorKm': p90EventErrorKm,
    'falseEstimateFrameRate': falseEstimateFrameRate,
  };
}

class SourceEstimationBatchRunner {
  final SourceEstimationBenchmarkSuite suite;
  final Directory workspaceRoot;
  final SourceEstimationBenchmarkInputMode inputMode;

  const SourceEstimationBatchRunner({
    required this.suite,
    required this.workspaceRoot,
    this.inputMode = SourceEstimationBenchmarkInputMode.dualLayer,
  });

  Future<SourceEstimationBatchReport> run({
    Directory? perCaseOutputDirectory,
  }) async {
    final reports = <SourceEstimationBenchmarkReport>[];
    for (final manifest in suite.caseManifests) {
      final replayCase = SourceEstimationReplayCase.fromManifest(
        manifest,
        workspaceRoot: workspaceRoot,
      );
      if (!replayCase.captureDirectory.existsSync()) {
        throw StateError(
          'Missing replay capture for ${replayCase.caseId}: '
          '${replayCase.captureDirectory.path}',
        );
      }
      final report = await SourceEstimationBenchmarkRunner(
        replayCase,
        inputMode: inputMode,
      ).run();
      reports.add(report);
      if (perCaseOutputDirectory != null) {
        report.writeJson(
          File.fromUri(
            perCaseOutputDirectory.uri.resolve('${replayCase.caseId}.json'),
          ),
        );
      }
    }

    final summaries = {
      for (final method in [
        SourceEstimationBenchmarkRunner.weightedMethod,
        SourceEstimationBenchmarkRunner.hybridMethod,
        SourceEstimationBenchmarkRunner.jqScoringHypMethod,
        SourceEstimationBenchmarkRunner.jqReferenceStateMachineMethod,
        SourceEstimationBenchmarkRunner.scratchMethod,
      ])
        method: _summarizeBatch(method, reports),
    };
    return SourceEstimationBatchReport(
      suiteId: suite.suiteId,
      cases: List.unmodifiable(reports),
      detectionSummary: _summarizeBatchDetection(reports),
      summaries: Map.unmodifiable(summaries),
    );
  }
}

class EventDetectionFrameReport {
  final DateTime observedAtJst;
  final bool decoded;
  final String detectionStage;
  final EventDetection? eventDetection;
  final EventDetection? shadowEventDetection;
  final EventDetection? temporalBridgeEventDetection;
  final int activeStationCount;
  final int maxShindo;
  final int maxStationDetectLevel;
  final double maxStationActivity;
  final Map<StationTriggerState, int> stationTriggerCounts;
  final NetworkAssociationDiagnostics? networkDiagnostics;
  final Map<int, NetworkAssociationDiagnostics> networkDiagnosticsByRadius;
  final Map<String, EventDetection> temporalBridgeSweepDetections;
  final Map<String, NetworkAssociationDiagnostics>
  temporalBridgeSweepDiagnostics;
  final Map<int, LocalObservabilityFrameDiagnostics> localObservabilityByRadius;

  const EventDetectionFrameReport({
    required this.observedAtJst,
    required this.decoded,
    required this.detectionStage,
    required this.eventDetection,
    required this.shadowEventDetection,
    required this.temporalBridgeEventDetection,
    required this.activeStationCount,
    required this.maxShindo,
    required this.maxStationDetectLevel,
    required this.maxStationActivity,
    required this.stationTriggerCounts,
    required this.networkDiagnostics,
    required this.networkDiagnosticsByRadius,
    required this.temporalBridgeSweepDetections,
    required this.temporalBridgeSweepDiagnostics,
    required this.localObservabilityByRadius,
  });

  Map<String, Object?> toJson() => {
    'observedAtJst': observedAtJst.toIso8601String(),
    'decoded': decoded,
    'detectionStage': detectionStage,
    'eventDetection': _eventDetectionToJson(eventDetection),
    'shadowEventDetection': _eventDetectionToJson(shadowEventDetection),
    'temporalBridgeEventDetection': _eventDetectionToJson(
      temporalBridgeEventDetection,
    ),
    'activeStationCount': activeStationCount,
    'maxShindo': maxShindo,
    'maxStationDetectLevel': maxStationDetectLevel,
    'maxStationActivity': maxStationActivity,
    'stationTriggerCounts': {
      for (final entry in stationTriggerCounts.entries)
        entry.key.name: entry.value,
    },
    'networkDiagnostics': networkDiagnostics?.toJson(),
    'networkDiagnosticsByRadius': {
      for (final entry in networkDiagnosticsByRadius.entries)
        '${entry.key}km': entry.value.toJson(),
    },
    'temporalBridgeSweepDetections': {
      for (final entry in temporalBridgeSweepDetections.entries)
        entry.key: _eventDetectionToJson(entry.value),
    },
    'temporalBridgeSweepDiagnostics': {
      for (final entry in temporalBridgeSweepDiagnostics.entries)
        entry.key: entry.value.toJson(),
    },
    'localObservabilityByRadius': {
      for (final entry in localObservabilityByRadius.entries)
        '${entry.key}km': entry.value.toJson(),
    },
  };
}

class LocalObservabilityFrameDiagnostics {
  final int risingStationCount;
  final int triggeredStationCount;
  final int largestConnectedComponentSize;

  const LocalObservabilityFrameDiagnostics({
    required this.risingStationCount,
    required this.triggeredStationCount,
    required this.largestConnectedComponentSize,
  });

  Map<String, Object?> toJson() => {
    'risingStationCount': risingStationCount,
    'triggeredStationCount': triggeredStationCount,
    'largestConnectedComponentSize': largestConnectedComponentSize,
  };
}

class StationTriggerCaseSummary {
  final String detectorId;
  final int framesWithRisingStations;
  final int framesWithTriggeredStations;
  final int framesWithStrongStations;
  final int maxRisingStationCount;
  final int maxTriggeredStationCount;
  final int maxStrongStationCount;
  final int uniqueActivityAtLeast1StationCount;
  final int uniqueActivityAtLeast2StationCount;
  final int uniqueActivityAtLeast3StationCount;
  final int uniqueRisingStationCount;
  final int uniqueTriggeredStationCount;
  final int uniqueStrongStationCount;
  final Map<int, int> uniqueTriggeredStationCountByRadiusKm;
  final List<StationTriggerStationSummary> stations;

  const StationTriggerCaseSummary({
    required this.detectorId,
    required this.framesWithRisingStations,
    required this.framesWithTriggeredStations,
    required this.framesWithStrongStations,
    required this.maxRisingStationCount,
    required this.maxTriggeredStationCount,
    required this.maxStrongStationCount,
    required this.uniqueActivityAtLeast1StationCount,
    required this.uniqueActivityAtLeast2StationCount,
    required this.uniqueActivityAtLeast3StationCount,
    required this.uniqueRisingStationCount,
    required this.uniqueTriggeredStationCount,
    required this.uniqueStrongStationCount,
    required this.uniqueTriggeredStationCountByRadiusKm,
    required this.stations,
  });

  Map<String, Object?> toJson() => {
    'detectorId': detectorId,
    'framesWithRisingStations': framesWithRisingStations,
    'framesWithTriggeredStations': framesWithTriggeredStations,
    'framesWithStrongStations': framesWithStrongStations,
    'maxRisingStationCount': maxRisingStationCount,
    'maxTriggeredStationCount': maxTriggeredStationCount,
    'maxStrongStationCount': maxStrongStationCount,
    'uniqueActivityAtLeast1StationCount': uniqueActivityAtLeast1StationCount,
    'uniqueActivityAtLeast2StationCount': uniqueActivityAtLeast2StationCount,
    'uniqueActivityAtLeast3StationCount': uniqueActivityAtLeast3StationCount,
    'uniqueRisingStationCount': uniqueRisingStationCount,
    'uniqueTriggeredStationCount': uniqueTriggeredStationCount,
    'uniqueStrongStationCount': uniqueStrongStationCount,
    'uniqueTriggeredStationCountByRadiusKm': {
      for (final entry in uniqueTriggeredStationCountByRadiusKm.entries)
        '${entry.key}km': entry.value,
    },
    'stations': stations.map((station) => station.toJson()).toList(),
  };
}

class StationTriggerStationSummary {
  final String stationId;
  final double? latitude;
  final double? longitude;
  final double? distanceToTruthKm;
  final DateTime? firstRisingAtJst;
  final DateTime? firstTriggeredAtJst;
  final double maxActivity;
  final int maxAscend;
  final int? maxDetectLevel;
  final int risingFrameCount;
  final int triggeredFrameCount;
  final int strongFrameCount;

  const StationTriggerStationSummary({
    required this.stationId,
    required this.latitude,
    required this.longitude,
    required this.distanceToTruthKm,
    required this.firstRisingAtJst,
    required this.firstTriggeredAtJst,
    required this.maxActivity,
    required this.maxAscend,
    required this.maxDetectLevel,
    required this.risingFrameCount,
    required this.triggeredFrameCount,
    required this.strongFrameCount,
  });

  Map<String, Object?> toJson() => {
    'stationId': stationId,
    'latitude': latitude,
    'longitude': longitude,
    'distanceToTruthKm': distanceToTruthKm,
    'firstRisingAtJst': firstRisingAtJst?.toIso8601String(),
    'firstTriggeredAtJst': firstTriggeredAtJst?.toIso8601String(),
    'maxActivity': maxActivity,
    'maxAscend': maxAscend,
    'maxDetectLevel': maxDetectLevel,
    'risingFrameCount': risingFrameCount,
    'triggeredFrameCount': triggeredFrameCount,
    'strongFrameCount': strongFrameCount,
  };
}

class NetworkAssociationCaseSummary {
  final String detectorId;
  final int maxTriggeredStationCount;
  final int maxComponentCount;
  final int maxLargestComponentSize;
  final double maxLargestComponentDiameterKm;
  final double maxQualityWeightedSupport;
  final double? maxTriggerTimeSpanSeconds;
  final DateTime? peakTriggeredAtJst;
  final List<int> peakTriggeredComponentSizes;
  final List<NetworkRadiusSweepSummary> radiusSweep;
  final List<TemporalBridgeSweepCaseSummary> temporalBridgeSweep;
  final List<LocalObservabilityRadiusSummary> localObservability;

  const NetworkAssociationCaseSummary({
    required this.detectorId,
    required this.maxTriggeredStationCount,
    required this.maxComponentCount,
    required this.maxLargestComponentSize,
    required this.maxLargestComponentDiameterKm,
    required this.maxQualityWeightedSupport,
    required this.maxTriggerTimeSpanSeconds,
    required this.peakTriggeredAtJst,
    required this.peakTriggeredComponentSizes,
    required this.radiusSweep,
    required this.temporalBridgeSweep,
    required this.localObservability,
  });

  Map<String, Object?> toJson() => {
    'detectorId': detectorId,
    'maxTriggeredStationCount': maxTriggeredStationCount,
    'maxComponentCount': maxComponentCount,
    'maxLargestComponentSize': maxLargestComponentSize,
    'maxLargestComponentDiameterKm': maxLargestComponentDiameterKm,
    'maxQualityWeightedSupport': maxQualityWeightedSupport,
    'maxTriggerTimeSpanSeconds': maxTriggerTimeSpanSeconds,
    'peakTriggeredAtJst': peakTriggeredAtJst?.toIso8601String(),
    'peakTriggeredComponentSizes': peakTriggeredComponentSizes,
    'radiusSweep': radiusSweep.map((entry) => entry.toJson()).toList(),
    'temporalBridgeSweep': temporalBridgeSweep
        .map((entry) => entry.toJson())
        .toList(),
    'localObservability': localObservability
        .map((entry) => entry.toJson())
        .toList(),
  };
}

class LocalObservabilityRadiusSummary {
  final int radiusKm;
  final int maxRisingStationCount;
  final int maxTriggeredStationCount;
  final int maxConnectedStationCount;
  final int candidateEvidenceFrameCount;
  final int confirmedEvidenceFrameCount;

  const LocalObservabilityRadiusSummary({
    required this.radiusKm,
    required this.maxRisingStationCount,
    required this.maxTriggeredStationCount,
    required this.maxConnectedStationCount,
    required this.candidateEvidenceFrameCount,
    required this.confirmedEvidenceFrameCount,
  });

  Map<String, Object?> toJson() => {
    'radiusKm': radiusKm,
    'maxRisingStationCount': maxRisingStationCount,
    'maxTriggeredStationCount': maxTriggeredStationCount,
    'maxConnectedStationCount': maxConnectedStationCount,
    'candidateEvidenceFrameCount': candidateEvidenceFrameCount,
    'confirmedEvidenceFrameCount': confirmedEvidenceFrameCount,
  };
}

class NetworkRadiusSweepSummary {
  final int radiusKm;
  final int maxLargestComponentSize;
  final int candidateFrameCount;
  final int confirmedFrameCount;

  const NetworkRadiusSweepSummary({
    required this.radiusKm,
    required this.maxLargestComponentSize,
    required this.candidateFrameCount,
    required this.confirmedFrameCount,
  });

  Map<String, Object?> toJson() => {
    'radiusKm': radiusKm,
    'maxLargestComponentSize': maxLargestComponentSize,
    'candidateFrameCount': candidateFrameCount,
    'confirmedFrameCount': confirmedFrameCount,
  };
}

class TemporalBridgeSweepCaseSummary {
  final String detectorId;
  final int bridgeDistanceKm;
  final int maxGapSeconds;
  final int candidateFrameCount;
  final int confirmedFrameCount;
  final DateTime? firstCandidateAtJst;
  final DateTime? firstConfirmedAtJst;
  final double? firstCandidateDelaySeconds;
  final double? firstConfirmedDelaySeconds;
  final List<String> firstCandidateStationIds;
  final int firstCandidateStrongEdgeCount;
  final int firstCandidateWeakEdgeCount;
  final Map<String, ObservationTimeInterval> firstCandidateTriggerIntervals;
  final double? firstCandidateClusterDistanceToTruthKm;

  const TemporalBridgeSweepCaseSummary({
    required this.detectorId,
    required this.bridgeDistanceKm,
    required this.maxGapSeconds,
    required this.candidateFrameCount,
    required this.confirmedFrameCount,
    required this.firstCandidateAtJst,
    required this.firstConfirmedAtJst,
    required this.firstCandidateDelaySeconds,
    required this.firstConfirmedDelaySeconds,
    required this.firstCandidateStationIds,
    required this.firstCandidateStrongEdgeCount,
    required this.firstCandidateWeakEdgeCount,
    required this.firstCandidateTriggerIntervals,
    required this.firstCandidateClusterDistanceToTruthKm,
  });

  Map<String, Object?> toJson() => {
    'detectorId': detectorId,
    'bridgeDistanceKm': bridgeDistanceKm,
    'maxGapSeconds': maxGapSeconds,
    'candidateFrameCount': candidateFrameCount,
    'confirmedFrameCount': confirmedFrameCount,
    'firstCandidateAtJst': firstCandidateAtJst?.toIso8601String(),
    'firstConfirmedAtJst': firstConfirmedAtJst?.toIso8601String(),
    'firstCandidateDelaySeconds': firstCandidateDelaySeconds,
    'firstConfirmedDelaySeconds': firstConfirmedDelaySeconds,
    'firstCandidateStationIds': firstCandidateStationIds,
    'firstCandidateStrongEdgeCount': firstCandidateStrongEdgeCount,
    'firstCandidateWeakEdgeCount': firstCandidateWeakEdgeCount,
    'firstCandidateTriggerIntervals': {
      for (final entry in firstCandidateTriggerIntervals.entries)
        entry.key: {
          'start': entry.value.start.toIso8601String(),
          'end': entry.value.end.toIso8601String(),
        },
    },
    'firstCandidateClusterDistanceToTruthKm':
        firstCandidateClusterDistanceToTruthKm,
  };
}

class EventDetectionBenchmarkReport {
  final SourceEstimationReplayCase replayCase;
  final int requestedFrameCount;
  final int decodedFrameCount;
  final List<EventDetectionFrameReport> frames;
  final SourceEstimationDetectionCaseSummary detectionSummary;
  final SourceEstimationDetectionCaseSummary shadowDetectionSummary;
  final SourceEstimationDetectionCaseSummary temporalBridgeDetectionSummary;
  final StationTriggerCaseSummary stationTriggerSummary;
  final NetworkAssociationCaseSummary networkAssociationSummary;

  const EventDetectionBenchmarkReport({
    required this.replayCase,
    required this.requestedFrameCount,
    required this.decodedFrameCount,
    required this.frames,
    required this.detectionSummary,
    required this.shadowDetectionSummary,
    required this.temporalBridgeDetectionSummary,
    required this.stationTriggerSummary,
    required this.networkAssociationSummary,
  });

  Map<String, Object?> toJson() => {
    'reportSchemaVersion': 2,
    'case': replayCase.toJson(),
    'requestedFrameCount': requestedFrameCount,
    'decodedFrameCount': decodedFrameCount,
    'detectionSummary': detectionSummary.toJson(),
    'shadowDetectionSummary': shadowDetectionSummary.toJson(),
    'temporalBridgeDetectionSummary': temporalBridgeDetectionSummary.toJson(),
    'stationTriggerSummary': stationTriggerSummary.toJson(),
    'networkAssociationSummary': networkAssociationSummary.toJson(),
    'frames': frames.map((frame) => frame.toJson()).toList(growable: false),
  };

  void writeJson(File output) {
    output.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    output.writeAsStringSync('${encoder.convert(toJson())}\n');
  }
}

class EventDetectionBatchReport {
  final String suiteId;
  final List<EventDetectionBenchmarkReport> cases;
  final SourceEstimationBatchDetectionSummary summary;
  final SourceEstimationBatchDetectionSummary shadowSummary;
  final SourceEstimationBatchDetectionSummary temporalBridgeSummary;

  const EventDetectionBatchReport({
    required this.suiteId,
    required this.cases,
    required this.summary,
    required this.shadowSummary,
    required this.temporalBridgeSummary,
  });

  Map<String, Object?> toJson() => {
    'reportSchemaVersion': 2,
    'suiteId': suiteId,
    'caseCount': cases.length,
    'summary': summary.toJson(),
    'shadowSummary': shadowSummary.toJson(),
    'temporalBridgeSummary': temporalBridgeSummary.toJson(),
    'cases': cases
        .map(
          (report) => {
            'caseId': report.replayCase.caseId,
            'caseType': report.replayCase.caseType.name,
            'requestedFrameCount': report.requestedFrameCount,
            'decodedFrameCount': report.decodedFrameCount,
            'detectionSummary': report.detectionSummary.toJson(),
            'shadowDetectionSummary': report.shadowDetectionSummary.toJson(),
            'temporalBridgeDetectionSummary': report
                .temporalBridgeDetectionSummary
                .toJson(),
            'stationTriggerSummary': report.stationTriggerSummary.toJson(),
            'networkAssociationSummary': report.networkAssociationSummary
                .toJson(),
          },
        )
        .toList(growable: false),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Event Detection Benchmark: `$suiteId`')
      ..writeln()
      ..writeln(
        '> This file is generated by replay tests. Do not edit by hand.',
      )
      ..writeln()
      ..writeln('## Summary')
      ..writeln()
      ..writeln(
        '> Detection denominator: ${summary.eventCaseCount} eligible observable events; '
        '${summary.excludedEventCaseCount} of '
        '${summary.catalogEventCaseCount} catalog/reference events excluded.',
      )
      ..writeln()
      ..writeln(
        '| Detector | Candidate coverage | Confirmed coverage | Missed candidates | Missed confirmed events | Noise candidate frames | Noise confirmed frames | Median candidate delay | Median confirmation delay |',
      )
      ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
      ..writeln(
        '| `${_markdownCell(summary.detectorId)}` '
        '| ${summary.eventCasesWithCandidate}/${summary.eventCaseCount} '
        '| ${summary.eventCasesConfirmed}/${summary.eventCaseCount} '
        '| ${summary.detectionMissedCandidateCount} '
        '| ${summary.detectionMissedEventCount} '
        '| ${summary.noiseCandidateFrameCount}/${summary.noiseFrameCount} '
        '| ${summary.noiseConfirmedFrameCount}/${summary.noiseFrameCount} '
        '| ${_formatSeconds(summary.medianCandidateDelaySeconds)} '
        '| ${_formatSeconds(summary.medianConfirmationDelaySeconds)} |',
      )
      ..writeln(
        '| `${_markdownCell(shadowSummary.detectorId)}` '
        '| ${shadowSummary.eventCasesWithCandidate}/${shadowSummary.eventCaseCount} '
        '| ${shadowSummary.eventCasesConfirmed}/${shadowSummary.eventCaseCount} '
        '| ${shadowSummary.detectionMissedCandidateCount} '
        '| ${shadowSummary.detectionMissedEventCount} '
        '| ${shadowSummary.noiseCandidateFrameCount}/${shadowSummary.noiseFrameCount} '
        '| ${shadowSummary.noiseConfirmedFrameCount}/${shadowSummary.noiseFrameCount} '
        '| ${_formatSeconds(shadowSummary.medianCandidateDelaySeconds)} '
        '| ${_formatSeconds(shadowSummary.medianConfirmationDelaySeconds)} |',
      )
      ..writeln(
        '| `${_markdownCell(temporalBridgeSummary.detectorId)}` '
        '| ${temporalBridgeSummary.eventCasesWithCandidate}/${temporalBridgeSummary.eventCaseCount} '
        '| ${temporalBridgeSummary.eventCasesConfirmed}/${temporalBridgeSummary.eventCaseCount} '
        '| ${temporalBridgeSummary.detectionMissedCandidateCount} '
        '| ${temporalBridgeSummary.detectionMissedEventCount} '
        '| ${temporalBridgeSummary.noiseCandidateFrameCount}/${temporalBridgeSummary.noiseFrameCount} '
        '| ${temporalBridgeSummary.noiseConfirmedFrameCount}/${temporalBridgeSummary.noiseFrameCount} '
        '| ${_formatSeconds(temporalBridgeSummary.medianCandidateDelaySeconds)} '
        '| ${_formatSeconds(temporalBridgeSummary.medianConfirmationDelaySeconds)} |',
      )
      ..writeln()
      ..writeln('## Cases')
      ..writeln()
      ..writeln(
        '| Case | Type | Frames | Max active stations | Max shindo | Max detect level | Max activity | Legacy candidate frames | Legacy confirmed frames | Shadow candidate frames | Shadow confirmed frames | Bridge candidate frames | Bridge confirmed frames | Shadow rising frames | Shadow triggered frames | Max shadow triggered stations | Unique shadow triggered stations | Max components | Max connected stations | Max component diameter | Max trigger span | Peak component sizes | Legacy candidate delay | Legacy confirmation delay | Shadow candidate delay | Shadow confirmation delay | Bridge candidate delay | Bridge confirmation delay |',
      )
      ..writeln(
        '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|',
      );
    for (final report in cases) {
      final summary = report.detectionSummary;
      buffer.writeln(
        '| `${_markdownCell(report.replayCase.caseId)}` '
        '| ${report.replayCase.caseType.name} '
        '| ${report.decodedFrameCount}/${report.requestedFrameCount} '
        '| ${summary.maxActiveStationCount} '
        '| ${summary.maxShindo} '
        '| ${summary.maxStationDetectLevel} '
        '| ${_formatNumber(summary.maxStationActivity)} '
        '| ${summary.candidateFrameCount} '
        '| ${summary.confirmedFrameCount} '
        '| ${report.shadowDetectionSummary.candidateFrameCount} '
        '| ${report.shadowDetectionSummary.confirmedFrameCount} '
        '| ${report.temporalBridgeDetectionSummary.candidateFrameCount} '
        '| ${report.temporalBridgeDetectionSummary.confirmedFrameCount} '
        '| ${report.stationTriggerSummary.framesWithRisingStations} '
        '| ${report.stationTriggerSummary.framesWithTriggeredStations} '
        '| ${report.stationTriggerSummary.maxTriggeredStationCount} '
        '| ${report.stationTriggerSummary.uniqueTriggeredStationCount} '
        '| ${report.networkAssociationSummary.maxComponentCount} '
        '| ${report.networkAssociationSummary.maxLargestComponentSize} '
        '| ${_formatKm(report.networkAssociationSummary.maxLargestComponentDiameterKm)} '
        '| ${_formatSeconds(report.networkAssociationSummary.maxTriggerTimeSpanSeconds)} '
        '| ${report.networkAssociationSummary.peakTriggeredComponentSizes.join(',')} '
        '| ${_formatSeconds(summary.firstCandidateDelaySeconds)} '
        '| ${_formatSeconds(summary.firstConfirmedDelaySeconds)} '
        '| ${_formatSeconds(report.shadowDetectionSummary.firstCandidateDelaySeconds)} '
        '| ${_formatSeconds(report.shadowDetectionSummary.firstConfirmedDelaySeconds)} '
        '| ${_formatSeconds(report.temporalBridgeDetectionSummary.firstCandidateDelaySeconds)} '
        '| ${_formatSeconds(report.temporalBridgeDetectionSummary.firstConfirmedDelaySeconds)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Radius Sweep')
      ..writeln()
      ..writeln(
        '| Case | Radius | Max connected stations | Candidate frames (>=4) | Confirmed frames (>=6) |',
      )
      ..writeln('|---|---:|---:|---:|---:|');
    for (final report in cases) {
      for (final sweep in report.networkAssociationSummary.radiusSweep) {
        buffer.writeln(
          '| `${_markdownCell(report.replayCase.caseId)}` '
          '| ${sweep.radiusKm}km '
          '| ${sweep.maxLargestComponentSize} '
          '| ${sweep.candidateFrameCount} '
          '| ${sweep.confirmedFrameCount} |',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('## Temporal Bridge Sweep')
      ..writeln()
      ..writeln(
        '| Case | Bridge | Gap | Candidate frames | Confirmed frames | Candidate delay | Confirmation delay | Cluster-truth distance | First candidate stations | Strong edges | Weak edges |',
      )
      ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|');
    for (final report in cases) {
      for (final sweep
          in report.networkAssociationSummary.temporalBridgeSweep) {
        buffer.writeln(
          '| `${_markdownCell(report.replayCase.caseId)}` '
          '| ${sweep.bridgeDistanceKm}km '
          '| ${sweep.maxGapSeconds}s '
          '| ${sweep.candidateFrameCount} '
          '| ${sweep.confirmedFrameCount} '
          '| ${_formatSeconds(sweep.firstCandidateDelaySeconds)} '
          '| ${_formatSeconds(sweep.firstConfirmedDelaySeconds)} '
          '| ${sweep.firstCandidateClusterDistanceToTruthKm == null ? '-' : _formatKm(sweep.firstCandidateClusterDistanceToTruthKm!)} '
          '| ${sweep.firstCandidateStationIds.join(',')} '
          '| ${sweep.firstCandidateStrongEdgeCount} '
          '| ${sweep.firstCandidateWeakEdgeCount} |',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('## Local Observability')
      ..writeln()
      ..writeln(
        '| Case | Included in detection metrics | Radius | Max rising stations | Max triggered stations | Max connected stations | Candidate evidence frames | Confirmed evidence frames |',
      )
      ..writeln('|---|---|---:|---:|---:|---:|---:|---:|');
    for (final report in cases) {
      for (final local in report.networkAssociationSummary.localObservability) {
        buffer.writeln(
          '| `${_markdownCell(report.replayCase.caseId)}` '
          '| ${report.replayCase.eventLabels.includeInDetectionMetrics} '
          '| ${local.radiusKm}km '
          '| ${local.maxRisingStationCount} '
          '| ${local.maxTriggeredStationCount} '
          '| ${local.maxConnectedStationCount} '
          '| ${local.candidateEvidenceFrameCount} '
          '| ${local.confirmedEvidenceFrameCount} |',
        );
      }
    }
    return buffer.toString();
  }

  void writeJson(File output) {
    output.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    output.writeAsStringSync('${encoder.convert(toJson())}\n');
  }

  void writeMarkdown(File output) {
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(toMarkdown());
  }
}

class EventDetectionBatchRunner {
  final SourceEstimationBenchmarkSuite suite;
  final Directory workspaceRoot;

  const EventDetectionBatchRunner({
    required this.suite,
    required this.workspaceRoot,
  });

  Future<EventDetectionBatchReport> run({
    Directory? perCaseOutputDirectory,
  }) async {
    final reports = <EventDetectionBenchmarkReport>[];
    for (final manifest in suite.caseManifests) {
      final replayCase = SourceEstimationReplayCase.fromManifest(
        manifest,
        workspaceRoot: workspaceRoot,
      );
      if (!replayCase.captureDirectory.existsSync()) {
        throw StateError(
          'Missing replay capture for ${replayCase.caseId}: '
          '${replayCase.captureDirectory.path}',
        );
      }
      final report = await EventDetectionBenchmarkRunner(replayCase).run();
      reports.add(report);
      if (perCaseOutputDirectory != null) {
        report.writeJson(
          File.fromUri(
            perCaseOutputDirectory.uri.resolve('${replayCase.caseId}.json'),
          ),
        );
      }
    }

    return EventDetectionBatchReport(
      suiteId: suite.suiteId,
      cases: List.unmodifiable(reports),
      summary: _summarizeEventDetectionBatch(reports),
      shadowSummary: _summarizeEventDetectionBatch(reports, shadow: true),
      temporalBridgeSummary: _summarizeEventDetectionBatch(
        reports,
        temporalBridge: true,
      ),
    );
  }
}

class EventDetectionBenchmarkRunner {
  final SourceEstimationReplayCase replayCase;

  const EventDetectionBenchmarkRunner(this.replayCase);

  Future<EventDetectionBenchmarkReport> run() async {
    final truth = replayCase.truth;
    final imageService = LmoniImageService()..start();
    final detector = ShakeDetectionService()
      ..setSensitivity(replayCase.sensitivity);
    final stationTriggerDetector = RobustStationTriggerDetector();
    final shadowEventDetector = SpatiotemporalEventDetector();
    final temporalBridgeEventDetector = SpatiotemporalEventDetector(
      detectorId: 'spatiotemporal_event_detector_temporal_bridge_v0',
      config: const SpatiotemporalEventDetectorConfig(
        temporalBridgeDistanceKm: 160,
        temporalBridgeMaxGap: Duration(seconds: 8),
      ),
    );
    final temporalBridgeSweepDetectors = {
      for (final distanceKm in const [120, 140, 160])
        for (final gapSeconds in const [4, 8, 12])
          _temporalBridgeSweepKey(
            distanceKm,
            gapSeconds,
          ): SpatiotemporalEventDetector(
            detectorId: 'spatiotemporal_bridge_${distanceKm}km_${gapSeconds}s',
            config: SpatiotemporalEventDetectorConfig(
              temporalBridgeDistanceKm: distanceKm.toDouble(),
              temporalBridgeMaxGap: Duration(seconds: gapSeconds),
            ),
          ),
    };
    final radiusDiagnosticDetectors = {
      for (final radiusKm in const [80, 120, 160, 240])
        radiusKm: SpatiotemporalEventDetector(
          config: SpatiotemporalEventDetectorConfig(
            maxLinkDistanceKm: radiusKm.toDouble(),
          ),
        ),
    };
    const observationAdapter = NiedStationObservationAdapter();

    var latestSnapshot = const ShakeDetectionSnapshot(
      stage: ShakeDetectStage.idle,
      weakCount: 0,
      detectedCount: 0,
      strongCount: 0,
      maxShindo: -1,
    );
    EventDetection? latestEventDetection;
    EventDetection? latestShadowEventDetection;
    EventDetection? latestTemporalBridgeEventDetection;
    NetworkAssociationDiagnostics? latestNetworkDiagnostics;
    List<NiedStation> latestStations = const [];
    Completer<void>? stationFrameReady;
    detector.onDetectionSnapshotChanged = (snapshot) {
      latestSnapshot = snapshot;
    };
    detector.onEventDetectionChanged = (detection) {
      latestEventDetection = detection;
    };
    final subscription = imageService.stationStream.listen((stations) {
      if (stations == null) return;
      latestStations = stations;
      detector.setStations(stations);
      detector.processUpdate();
      stationFrameReady?.complete();
    });

    final frames = <EventDetectionFrameReport>[];
    final stationTriggerAccumulators = <String, _StationTriggerAccumulator>{};
    var requestedFrames = 0;
    var decodedFrames = 0;

    try {
      for (
        var observedAt = replayCase.startTimeJst;
        !observedAt.isAfter(replayCase.endTimeJst);
        observedAt = observedAt.add(const Duration(seconds: 1))
      ) {
        requestedFrames++;
        final surface = await decodeNiedGifFile(
          File(
            '${replayCase.captureDirectory.path}${Platform.pathSeparator}'
            '${replayCase.gifFileName(observedAt, 'jma_s')}',
          ),
        );
        if (surface == null) {
          frames.add(
            EventDetectionFrameReport(
              observedAtJst: observedAt,
              decoded: false,
              detectionStage: latestSnapshot.stage.name,
              eventDetection: latestEventDetection,
              shadowEventDetection: latestShadowEventDetection,
              temporalBridgeEventDetection: latestTemporalBridgeEventDetection,
              activeStationCount: latestStations
                  .where((station) => station.isActive)
                  .length,
              maxShindo: latestSnapshot.maxShindo,
              maxStationDetectLevel: _maxStationDetectLevel(latestStations),
              maxStationActivity: _maxStationActivity(latestStations),
              stationTriggerCounts: const {},
              networkDiagnostics: null,
              networkDiagnosticsByRadius: const {},
              temporalBridgeSweepDetections: const {},
              temporalBridgeSweepDiagnostics: const {},
              localObservabilityByRadius: const {},
            ),
          );
          continue;
        }
        await decodeNiedGifFile(
          File(
            '${replayCase.captureDirectory.path}${Platform.pathSeparator}'
            '${replayCase.gifFileName(observedAt, 'jma_b')}',
          ),
        );

        stationFrameReady = Completer<void>();
        imageService.processPixels(
          surface.packedRgb,
          surfaceGifBytes: surface.gifBytes,
          dataTime: observedAt,
        );
        await stationFrameReady.future;
        stationFrameReady = null;
        decodedFrames++;
        final stationTriggers = observationAdapter
            .fromStations(latestStations, observedAt: observedAt)
            .map(stationTriggerDetector.update)
            .toList(growable: false);
        for (final trigger in stationTriggers) {
          stationTriggerAccumulators
              .putIfAbsent(
                trigger.stationId,
                () => _StationTriggerAccumulator.fromSnapshot(
                  trigger,
                  truth?.epicenter,
                ),
              )
              .update(trigger);
        }
        latestShadowEventDetection = shadowEventDetector.update(
          observedAt: observedAt,
          stations: stationTriggers,
        );
        latestTemporalBridgeEventDetection = temporalBridgeEventDetector.update(
          observedAt: observedAt,
          stations: stationTriggers,
        );
        latestNetworkDiagnostics = shadowEventDetector.diagnose(
          stationTriggers,
        );
        final networkDiagnosticsByRadius = {
          for (final entry in radiusDiagnosticDetectors.entries)
            entry.key: entry.value.diagnose(stationTriggers),
        };
        final temporalBridgeSweepDetections = {
          for (final entry in temporalBridgeSweepDetectors.entries)
            entry.key: entry.value.update(
              observedAt: observedAt,
              stations: stationTriggers,
            ),
        };
        final temporalBridgeSweepDiagnostics = {
          for (final entry in temporalBridgeSweepDetectors.entries)
            entry.key: entry.value.diagnose(stationTriggers),
        };
        final localObservabilityByRadius = truth == null
            ? const <int, LocalObservabilityFrameDiagnostics>{}
            : {
                for (final radiusKm in const [50, 100, 160])
                  radiusKm: _localObservabilityDiagnostics(
                    stationTriggers,
                    truth.epicenter,
                    radiusKm.toDouble(),
                    shadowEventDetector,
                  ),
              };

        frames.add(
          EventDetectionFrameReport(
            observedAtJst: observedAt,
            decoded: true,
            detectionStage: latestSnapshot.stage.name,
            eventDetection: latestEventDetection,
            shadowEventDetection: latestShadowEventDetection,
            temporalBridgeEventDetection: latestTemporalBridgeEventDetection,
            activeStationCount: latestStations
                .where((station) => station.isActive)
                .length,
            maxShindo: latestSnapshot.maxShindo,
            maxStationDetectLevel: _maxStationDetectLevel(latestStations),
            maxStationActivity: _maxStationActivity(latestStations),
            stationTriggerCounts: _stationTriggerCounts(stationTriggers),
            networkDiagnostics: latestNetworkDiagnostics,
            networkDiagnosticsByRadius: Map.unmodifiable(
              networkDiagnosticsByRadius,
            ),
            temporalBridgeSweepDetections: Map.unmodifiable(
              temporalBridgeSweepDetections,
            ),
            temporalBridgeSweepDiagnostics: Map.unmodifiable(
              temporalBridgeSweepDiagnostics,
            ),
            localObservabilityByRadius: Map.unmodifiable(
              localObservabilityByRadius,
            ),
          ),
        );
      }
    } finally {
      detector.onDetectionSnapshotChanged = null;
      detector.onEventDetectionChanged = null;
      await subscription.cancel();
      for (final station in latestStations) {
        station.terminate();
      }
      imageService.stop();
    }

    final sourceFrames = frames
        .map(
          (frame) => SourceEstimationFrameReport(
            observedAtJst: frame.observedAtJst,
            decoded: frame.decoded,
            detectionStage: frame.detectionStage,
            eventDetection: frame.eventDetection,
            activeStationCount: frame.activeStationCount,
            maxShindo: frame.maxShindo,
            maxStationDetectLevel: frame.maxStationDetectLevel,
            maxStationActivity: frame.maxStationActivity,
            methods: const {},
          ),
        )
        .toList(growable: false);
    final shadowSourceFrames = frames
        .map(
          (frame) => SourceEstimationFrameReport(
            observedAtJst: frame.observedAtJst,
            decoded: frame.decoded,
            detectionStage: frame.detectionStage,
            eventDetection: frame.shadowEventDetection,
            activeStationCount: frame.activeStationCount,
            maxShindo: frame.maxShindo,
            maxStationDetectLevel: frame.maxStationDetectLevel,
            maxStationActivity: frame.maxStationActivity,
            methods: const {},
          ),
        )
        .toList(growable: false);
    final temporalBridgeSourceFrames = frames
        .map(
          (frame) => SourceEstimationFrameReport(
            observedAtJst: frame.observedAtJst,
            decoded: frame.decoded,
            detectionStage: frame.detectionStage,
            eventDetection: frame.temporalBridgeEventDetection,
            activeStationCount: frame.activeStationCount,
            maxShindo: frame.maxShindo,
            maxStationDetectLevel: frame.maxStationDetectLevel,
            maxStationActivity: frame.maxStationActivity,
            methods: const {},
          ),
        )
        .toList(growable: false);

    return EventDetectionBenchmarkReport(
      replayCase: replayCase,
      requestedFrameCount: requestedFrames,
      decodedFrameCount: decodedFrames,
      frames: List.unmodifiable(frames),
      detectionSummary: _summarizeDetection(
        sourceFrames,
        replayCase.caseType,
        truth?.originTimeJst,
      ),
      shadowDetectionSummary: _summarizeDetection(
        shadowSourceFrames,
        replayCase.caseType,
        truth?.originTimeJst,
      ),
      temporalBridgeDetectionSummary: _summarizeDetection(
        temporalBridgeSourceFrames,
        replayCase.caseType,
        truth?.originTimeJst,
      ),
      stationTriggerSummary: _summarizeStationTriggers(
        frames,
        stationTriggerDetector.detectorId,
        stationTriggerAccumulators,
      ),
      networkAssociationSummary: _summarizeNetworkAssociation(
        frames,
        shadowEventDetector.detectorId,
        truth?.originTimeJst,
        truth?.epicenter,
      ),
    );
  }
}

class SourceEstimationBenchmarkRunner {
  static const weightedMethod = 'weighted_centroid_baseline';
  static const hybridMethod = 'nied_gif_hybrid_v1';
  static const scratchMethod = 'scratch_scan_v1';
  static const jqScoringHypMethod = 'nied_gif_hyp_jq_scoring_experiment';
  static const kotoho7HypMethod = 'nied_gif_hyp_kotoho7_reference_replay_v1';
  static const kotoho7JsReceiverMethod = 'nied_gif_kotoho7_js_receiver_v1';
  static const kotoho7JsReceiverReplayEnabled = bool.fromEnvironment(
    'SOURCE_ESTIMATION_KOTOHO7_JS_RECEIVER_REPLAY',
  );
  static const kotoho7RawIdDiagnosticMethod =
      'nied_gif_hyp_kotoho7_reference_raw_id_diagnostic_v1';
  static const kotoho7UncappedAssignmentExperimentMethod =
      'nied_gif_hyp_kotoho7_uncapped_assignment_experiment_v1';
  static const kotoho7UncappedAssignmentExperimentEnabled =
      bool.fromEnvironment(
        'SOURCE_ESTIMATION_KOTOHO7_UNCAPPED_ASSIGNMENT_EXPERIMENT',
      );
  static const kotoho7Id2GatedAssignmentExperimentMethod =
      'nied_gif_hyp_kotoho7_id2_gated_assignment_experiment_v1';
  static const kotoho7Id2GatedAssignmentExperimentEnabled =
      bool.fromEnvironment(
        'SOURCE_ESTIMATION_KOTOHO7_ID2_GATED_ASSIGNMENT_EXPERIMENT',
      );
  static const kotoho7AssignmentOnlyPsCacheExperimentMethod =
      'nied_gif_hyp_kotoho7_assignment_only_ps_cache_experiment_v1';
  static const kotoho7AssignmentOnlyPsCacheExperimentEnabled =
      bool.fromEnvironment(
        'SOURCE_ESTIMATION_KOTOHO7_ASSIGNMENT_ONLY_PS_CACHE_EXPERIMENT',
      );
  static const kotoho7ScratchTenPlus1TimeExperimentMethod =
      'nied_gif_hyp_kotoho7_scratch_ten_plus_1_time_experiment_v1';
  static const kotoho7ScratchTenPlus1TimeExperimentEnabled =
      bool.fromEnvironment(
        'SOURCE_ESTIMATION_KOTOHO7_SCRATCH_TEN_PLUS_1_TIME_EXPERIMENT',
      );
  static const jqReferenceStateMachineMethod =
      'jq_reference_hyp_state_machine_experiment';

  final SourceEstimationReplayCase replayCase;
  final SourceEstimator hybridEstimator;
  final SourceEstimationBenchmarkInputMode inputMode;

  const SourceEstimationBenchmarkRunner(
    this.replayCase, {
    this.inputMode = SourceEstimationBenchmarkInputMode.dualLayer,
    this.hybridEstimator = const NiedGifHybridSourceEstimator(
      fallback: WeightedCentroidSourceEstimator(),
      emitOneSidedBoundaryCentroidGuardCandidate: true,
      oneSidedBoundaryCentroidGuardMinUncertaintyP90Km: 180.0,
      oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm: 80.0,
    ),
  });

  Future<SourceEstimationBenchmarkReport> run() async {
    final truth = replayCase.truth;
    final imageService = LmoniImageService()..start();
    final detector = ShakeDetectionService()
      ..setSensitivity(replayCase.sensitivity);
    final stationTriggerDetector = RobustStationTriggerDetector();
    final sourceEventDetector = SpatiotemporalEventDetector(
      detectorId: NiedSourceEstimationDriver.sourceEventDetectorId,
      config: NiedSourceEstimationDriver.sourceEventDetectorConfig,
    );
    final sourceContinuityGate = SourceTriggerContinuityGate();
    const observationAdapter = NiedStationObservationAdapter();
    const sourceTriggerGate = SourceEstimationTriggerGate();
    final weightedTracker = SeismicSourceTracker()
      ..setEstimator(weightedMethod, const WeightedCentroidSourceEstimator());
    final hybridTracker = SeismicSourceTracker()
      ..setEstimator(hybridMethod, hybridEstimator)
      ..setStabilityConfig(
        hybridMethod,
        StationEventTracker.niedStabilityConfig,
      );
    final kotoho7Tracker = SeismicSourceTracker()
      ..setEstimator(kotoho7HypMethod, Kotoho7ReferenceHypSourceEstimator());
    final kotoho7JsReceiverTracker = kotoho7JsReceiverReplayEnabled
        ? (SeismicSourceTracker()
            ..setEstimator(
              kotoho7JsReceiverMethod,
              Kotoho7JsReceiverSourceEstimator(),
            )
            ..setStabilityConfig(
              kotoho7JsReceiverMethod,
              StationEventTracker.niedStabilityConfig,
            ))
        : null;
    final kotoho7RawIdDiagnosticTracker = SeismicSourceTracker()
      ..setEstimator(
        kotoho7RawIdDiagnosticMethod,
        Kotoho7ReferenceHypSourceEstimator(),
      );
    final kotoho7UncappedAssignmentExperimentTracker =
        kotoho7UncappedAssignmentExperimentEnabled
        ? (SeismicSourceTracker()..setEstimator(
            kotoho7UncappedAssignmentExperimentMethod,
            Kotoho7ReferenceHypSourceEstimator(),
          ))
        : null;
    final kotoho7Id2GatedAssignmentExperimentTracker =
        kotoho7Id2GatedAssignmentExperimentEnabled
        ? (SeismicSourceTracker()..setEstimator(
            kotoho7Id2GatedAssignmentExperimentMethod,
            Kotoho7ReferenceHypSourceEstimator(),
          ))
        : null;
    final kotoho7AssignmentOnlyPsCacheExperimentTracker =
        kotoho7AssignmentOnlyPsCacheExperimentEnabled
        ? (SeismicSourceTracker()..setEstimator(
            kotoho7AssignmentOnlyPsCacheExperimentMethod,
            Kotoho7ReferenceHypSourceEstimator(),
          ))
        : null;
    final kotoho7ScratchTenPlus1TimeExperimentTracker =
        kotoho7ScratchTenPlus1TimeExperimentEnabled
        ? (SeismicSourceTracker()..setEstimator(
            kotoho7ScratchTenPlus1TimeExperimentMethod,
            Kotoho7ReferenceHypSourceEstimator(),
          ))
        : null;
    final jqReferenceStateMachine = _JqReferenceHypStateMachine();

    var latestSnapshot = const ShakeDetectionSnapshot(
      stage: ShakeDetectStage.idle,
      weakCount: 0,
      detectedCount: 0,
      strongCount: 0,
      maxShindo: -1,
    );
    EventDetection? latestLegacyEventDetection;
    EventDetection? latestSourceEventDetection;
    List<NiedStation> latestStations = const [];
    Completer<void>? stationFrameReady;
    detector.onDetectionSnapshotChanged = (snapshot) {
      latestSnapshot = snapshot;
    };
    detector.onEventDetectionChanged = (detection) {
      latestLegacyEventDetection = detection;
    };
    final subscription = imageService.stationStream.listen((stations) {
      if (stations == null) return;
      latestStations = stations;
      detector.setStations(stations);
      detector.processUpdate();
      stationFrameReady?.complete();
    });

    final reports = <SourceEstimationFrameReport>[];
    final previousPoints = <String, LatLng>{};
    var requestedFrames = 0;
    var decodedFrames = 0;

    try {
      for (
        var observedAt = replayCase.startTimeJst;
        !observedAt.isAfter(replayCase.endTimeJst);
        observedAt = observedAt.add(const Duration(seconds: 1))
      ) {
        requestedFrames++;
        final surface = await decodeNiedGifFile(
          File(
            '${replayCase.captureDirectory.path}${Platform.pathSeparator}'
            '${replayCase.gifFileName(observedAt, 'jma_s')}',
          ),
        );
        if (surface == null) {
          reports.add(
            SourceEstimationFrameReport(
              observedAtJst: observedAt,
              decoded: false,
              detectionStage: latestSnapshot.stage.name,
              eventDetection: latestSourceEventDetection,
              activeStationCount: latestStations
                  .where((station) => station.isActive)
                  .length,
              maxShindo: latestSnapshot.maxShindo,
              maxStationDetectLevel: _maxStationDetectLevel(latestStations),
              maxStationActivity: _maxStationActivity(latestStations),
              methods: const {},
            ),
          );
          continue;
        }
        if (inputMode.usesBoreholeImage) {
          await decodeNiedGifFile(
            File(
              '${replayCase.captureDirectory.path}${Platform.pathSeparator}'
              '${replayCase.gifFileName(observedAt, 'jma_b')}',
            ),
          );
        }

        stationFrameReady = Completer<void>();
        imageService.processPixels(
          surface.packedRgb,
          surfaceGifBytes: surface.gifBytes,
          dataTime: observedAt,
        );
        await stationFrameReady.future;
        stationFrameReady = null;
        decodedFrames++;

        final stationTriggers = observationAdapter
            .fromStations(latestStations, observedAt: observedAt)
            .map(stationTriggerDetector.update)
            .toList(growable: false);
        final rawSourceEventDetection = sourceEventDetector.update(
          observedAt: observedAt,
          stations: stationTriggers,
        );
        final sourceContinuity = sourceContinuityGate.update(
          detection: rawSourceEventDetection,
          stations: stationTriggers,
          observedAt: observedAt,
          activeEstimate: hybridTracker.currentEvent(hybridMethod)?.estimate,
        );
        latestSourceEventDetection = _continuityAwareEventDetection(
          rawSourceEventDetection,
          sourceContinuity,
        );

        final sourceTrigger = sourceTriggerGate.evaluate(
          latestSourceEventDetection,
        );
        final estimationStage = sourceTrigger.shouldIngestFrame == true
            ? sourceTrigger.stageName
            : ShakeDetectStage.idle.name;
        final sourceTriggerMetadata = {
          ...sourceTrigger.metadata,
          'legacy_detection_state': latestLegacyEventDetection?.state.name,
          'legacy_detection_detector_id':
              latestLegacyEventDetection?.detectorId,
          'benchmark_input_mode': inputMode.id,
          'benchmark_input_layers': inputMode.layers,
          'source_trigger_member_ids': List<String>.unmodifiable(
            latestSourceEventDetection.memberStationIds,
          ),
          'source_trigger_raw_member_ids': List<String>.unmodifiable(
            rawSourceEventDetection.memberStationIds,
          ),
          'source_trigger_continuity_member_ids': List<String>.unmodifiable(
            sourceContinuity.effectiveMemberStationIds,
          ),
          ...sourceContinuity.metadata,
        };
        final effectiveSourceEventId =
            sourceContinuity.effectiveEventId ?? sourceTrigger.eventId;
        final rawSourceEventId =
            rawSourceEventDetection.eventId ?? sourceTrigger.eventId;
        final rawDiagnosticStage = switch (rawSourceEventDetection.state) {
          EventDetectionState.candidate ||
          EventDetectionState.confirmed ||
          EventDetectionState.strong => rawSourceEventDetection.state.name,
          EventDetectionState.idle ||
          EventDetectionState.ended ||
          EventDetectionState.rejected => estimationStage,
        };
        final triggersByCode = {
          for (final trigger in stationTriggers) trigger.code: trigger,
        };
        sourceTriggerMetadata['station_trigger_observation_times'] =
            _stationTriggerObservationTimesJson(triggersByCode);
        final samples = _samplesFromNiedStations(
          latestStations,
          observedAt,
          triggersByCode,
        );
        final kotoho7ReceiverMetadata = {
          'nied_input_kind': 'gif',
          'kotoho7_receiver_frame_key': observedAt.toUtc().toIso8601String(),
          'kotoho7_receiver_current_frame_observations':
              _kotoho7ReceiverFrameObservationsFromSamples(
                samples,
                observedAt: observedAt,
              ),
        };
        final methodFrames = <String, SourceEstimationMethodFrame>{};

        methodFrames[weightedMethod] = _runTrackerFrame(
          tracker: weightedTracker,
          sourceId: weightedMethod,
          observedAt: observedAt,
          stageName: estimationStage,
          maxShindo: latestSnapshot.maxShindo,
          samples: samples,
          truth: truth?.epicenter,
          previousPoints: previousPoints,
          eventId: effectiveSourceEventId,
          metadata: sourceTriggerMetadata,
        );
        final hybridFrame = _runTrackerFrame(
          tracker: hybridTracker,
          sourceId: hybridMethod,
          observedAt: observedAt,
          stageName: estimationStage,
          maxShindo: latestSnapshot.maxShindo,
          samples: samples,
          truth: truth?.epicenter,
          previousPoints: previousPoints,
          eventId: effectiveSourceEventId,
          metadata: {'nied_input_kind': 'gif', ...sourceTriggerMetadata},
        );
        methodFrames[hybridMethod] = hybridFrame;
        methodFrames[kotoho7HypMethod] = _runTrackerFrame(
          tracker: kotoho7Tracker,
          sourceId: kotoho7HypMethod,
          observedAt: observedAt,
          stageName: estimationStage,
          maxShindo: latestSnapshot.maxShindo,
          samples: samples,
          truth: truth?.epicenter,
          previousPoints: previousPoints,
          eventId: effectiveSourceEventId,
          metadata: {
            'nied_input_kind': 'gif',
            'kotoho7_prefer_raw_member_ids': true,
            ...sourceTriggerMetadata,
          },
        );
        if (kotoho7JsReceiverTracker != null) {
          methodFrames[kotoho7JsReceiverMethod] = _runTrackerFrame(
            tracker: kotoho7JsReceiverTracker,
            sourceId: kotoho7JsReceiverMethod,
            observedAt: observedAt,
            stageName: estimationStage,
            maxShindo: latestSnapshot.maxShindo,
            samples: samples,
            truth: truth?.epicenter,
            previousPoints: previousPoints,
            eventId: effectiveSourceEventId,
            metadata: {...sourceTriggerMetadata, ...kotoho7ReceiverMetadata},
          );
        }
        methodFrames[kotoho7RawIdDiagnosticMethod] = _runTrackerFrame(
          tracker: kotoho7RawIdDiagnosticTracker,
          sourceId: kotoho7RawIdDiagnosticMethod,
          observedAt: observedAt,
          stageName: rawDiagnosticStage,
          maxShindo: latestSnapshot.maxShindo,
          samples: samples,
          truth: truth?.epicenter,
          previousPoints: previousPoints,
          eventId: rawSourceEventId,
          metadata: {
            'nied_input_kind': 'gif',
            'kotoho7_event_id_mode': 'raw_diagnostic',
            'kotoho7_prefer_raw_member_ids': true,
            'kotoho7_effective_event_id': effectiveSourceEventId,
            ...sourceTriggerMetadata,
          },
          splitOnEventIdChange: true,
        );
        if (kotoho7UncappedAssignmentExperimentTracker != null) {
          methodFrames[kotoho7UncappedAssignmentExperimentMethod] =
              _runTrackerFrame(
                tracker: kotoho7UncappedAssignmentExperimentTracker,
                sourceId: kotoho7UncappedAssignmentExperimentMethod,
                observedAt: observedAt,
                stageName: estimationStage,
                maxShindo: latestSnapshot.maxShindo,
                samples: samples,
                truth: truth?.epicenter,
                previousPoints: previousPoints,
                eventId: effectiveSourceEventId,
                metadata: {
                  'nied_input_kind': 'gif',
                  'kotoho7_prefer_raw_member_ids': true,
                  'kotoho7_assignment_candidate_mode': 'uncapped',
                  'kotoho7_experiment':
                      'uncapped_assignment_current_detection_pool',
                  ...sourceTriggerMetadata,
                },
              );
        }
        if (kotoho7Id2GatedAssignmentExperimentTracker != null) {
          methodFrames[kotoho7Id2GatedAssignmentExperimentMethod] =
              _runTrackerFrame(
                tracker: kotoho7Id2GatedAssignmentExperimentTracker,
                sourceId: kotoho7Id2GatedAssignmentExperimentMethod,
                observedAt: observedAt,
                stageName: estimationStage,
                maxShindo: latestSnapshot.maxShindo,
                samples: samples,
                truth: truth?.epicenter,
                previousPoints: previousPoints,
                eventId: effectiveSourceEventId,
                metadata: {
                  'nied_input_kind': 'gif',
                  'kotoho7_prefer_raw_member_ids': true,
                  'kotoho7_assignment_candidate_mode': 'uncapped_id2_gate',
                  'kotoho7_experiment':
                      'uncapped_assignment_current_detection_pool_after_id2_gate',
                  ...sourceTriggerMetadata,
                },
              );
        }
        if (kotoho7AssignmentOnlyPsCacheExperimentTracker != null) {
          methodFrames[kotoho7AssignmentOnlyPsCacheExperimentMethod] =
              _runTrackerFrame(
                tracker: kotoho7AssignmentOnlyPsCacheExperimentTracker,
                sourceId: kotoho7AssignmentOnlyPsCacheExperimentMethod,
                observedAt: observedAt,
                stageName: estimationStage,
                maxShindo: latestSnapshot.maxShindo,
                samples: samples,
                truth: truth?.epicenter,
                previousPoints: previousPoints,
                eventId: effectiveSourceEventId,
                metadata: {
                  'nied_input_kind': 'gif',
                  'kotoho7_prefer_raw_member_ids': true,
                  'kotoho7_ps_cache_refresh_mode': 'assignment_only',
                  'kotoho7_experiment':
                      'assignment_only_ps_cache_no_member_wide_bridge',
                  ...sourceTriggerMetadata,
                },
              );
        }
        if (kotoho7ScratchTenPlus1TimeExperimentTracker != null) {
          methodFrames[kotoho7ScratchTenPlus1TimeExperimentMethod] =
              _runTrackerFrame(
                tracker: kotoho7ScratchTenPlus1TimeExperimentTracker,
                sourceId: kotoho7ScratchTenPlus1TimeExperimentMethod,
                observedAt: observedAt,
                stageName: estimationStage,
                maxShindo: latestSnapshot.maxShindo,
                samples: samples,
                truth: truth?.epicenter,
                previousPoints: previousPoints,
                eventId: effectiveSourceEventId,
                metadata: {
                  'nied_input_kind': 'gif',
                  'kotoho7_prefer_raw_member_ids': true,
                  'kotoho7_observed_time_mode': 'scratch_ten_plus_1',
                  'kotoho7_experiment': 'hyp_uses_scratch_ten_plus_1_time',
                  ...sourceTriggerMetadata,
                },
              );
        }
        final jqScoringFrame = _runHypDiagnosticFrame(
          methodId: jqScoringHypMethod,
          sourceEstimate: hybridFrame.estimate,
          truth: truth?.epicenter,
          previousPoints: previousPoints,
        );
        if (jqScoringFrame.estimate != null ||
            jqReferenceStateMachine.isActive) {
          methodFrames[jqScoringHypMethod] = jqScoringFrame;
          methodFrames[jqReferenceStateMachineMethod] = jqReferenceStateMachine
              .runFrame(
                observedAt: observedAt,
                event: hybridTracker.currentEvent(hybridMethod),
                bridgeEstimate: jqScoringFrame.estimate,
                truth: truth?.epicenter,
                previousPoints: previousPoints,
              );
        }
        methodFrames[scratchMethod] = _runScratchFrame(
          latestStations,
          truth?.epicenter,
          previousPoints,
          enabled: sourceTrigger.shouldRunEstimator == true,
        );

        reports.add(
          SourceEstimationFrameReport(
            observedAtJst: observedAt,
            decoded: true,
            detectionStage: latestSnapshot.stage.name,
            eventDetection: latestSourceEventDetection,
            activeStationCount: latestStations
                .where((station) => station.isActive)
                .length,
            maxShindo: latestSnapshot.maxShindo,
            maxStationDetectLevel: _maxStationDetectLevel(latestStations),
            maxStationActivity: _maxStationActivity(latestStations),
            sourceTriggerMetadata: sourceTriggerMetadata,
            methods: methodFrames,
          ),
        );
      }
    } finally {
      detector.onDetectionSnapshotChanged = null;
      detector.onEventDetectionChanged = null;
      await subscription.cancel();
      for (final station in latestStations) {
        station.terminate();
      }
      imageService.stop();
    }

    final summaries = {
      for (final method in [
        weightedMethod,
        hybridMethod,
        jqScoringHypMethod,
        kotoho7HypMethod,
        if (kotoho7JsReceiverReplayEnabled) kotoho7JsReceiverMethod,
        kotoho7RawIdDiagnosticMethod,
        if (kotoho7UncappedAssignmentExperimentEnabled)
          kotoho7UncappedAssignmentExperimentMethod,
        if (kotoho7Id2GatedAssignmentExperimentEnabled)
          kotoho7Id2GatedAssignmentExperimentMethod,
        if (kotoho7AssignmentOnlyPsCacheExperimentEnabled)
          kotoho7AssignmentOnlyPsCacheExperimentMethod,
        if (kotoho7ScratchTenPlus1TimeExperimentEnabled)
          kotoho7ScratchTenPlus1TimeExperimentMethod,
        jqReferenceStateMachineMethod,
        scratchMethod,
      ])
        method: _summarize(
          method,
          reports,
          replayCase.caseType,
          truth?.originTimeJst,
        ),
    };
    return SourceEstimationBenchmarkReport(
      replayCase: replayCase,
      requestedFrameCount: requestedFrames,
      decodedFrameCount: decodedFrames,
      frames: List.unmodifiable(reports),
      detectionSummary: _summarizeDetection(
        reports,
        replayCase.caseType,
        truth?.originTimeJst,
      ),
      summaries: Map.unmodifiable(summaries),
    );
  }
}

SourceEstimationDetectionCaseSummary _summarizeDetection(
  List<SourceEstimationFrameReport> frames,
  SourceEstimationReplayCaseType caseType,
  DateTime? originTimeJst,
) {
  final decodedFrames = frames.where((frame) => frame.decoded).toList();
  final detections = decodedFrames
      .map((frame) => (frame.observedAtJst, frame.eventDetection))
      .where((entry) => entry.$2 != null)
      .toList(growable: false);
  final detectorId = detections.isEmpty
      ? 'unknown'
      : detections.first.$2!.detectorId;

  DateTime? firstCandidateAt;
  DateTime? firstConfirmedAt;
  var candidateFrames = 0;
  var confirmedFrames = 0;
  var maxActiveStationCount = 0;
  var maxShindo = -1;
  var maxStationDetectLevel = -1;
  var maxStationActivity = 0.0;

  for (final frame in decodedFrames) {
    if (frame.activeStationCount > maxActiveStationCount) {
      maxActiveStationCount = frame.activeStationCount;
    }
    if (frame.maxShindo > maxShindo) {
      maxShindo = frame.maxShindo;
    }
    if (frame.maxStationDetectLevel > maxStationDetectLevel) {
      maxStationDetectLevel = frame.maxStationDetectLevel;
    }
    if (frame.maxStationActivity > maxStationActivity) {
      maxStationActivity = frame.maxStationActivity;
    }
  }
  for (final entry in detections) {
    final state = entry.$2!.state;
    if (_isCandidateDetectionState(state)) {
      candidateFrames++;
      firstCandidateAt ??= entry.$1;
    }
    if (_isConfirmedDetectionState(state)) {
      confirmedFrames++;
      firstConfirmedAt ??= entry.$1;
    }
  }

  return SourceEstimationDetectionCaseSummary(
    detectorId: detectorId,
    caseType: caseType,
    decodedFrameCount: decodedFrames.length,
    candidateFrameCount: candidateFrames,
    confirmedFrameCount: confirmedFrames,
    maxActiveStationCount: maxActiveStationCount,
    maxShindo: maxShindo,
    maxStationDetectLevel: maxStationDetectLevel,
    maxStationActivity: maxStationActivity,
    firstCandidateAtJst: firstCandidateAt,
    firstConfirmedAtJst: firstConfirmedAt,
    firstCandidateDelaySeconds:
        firstCandidateAt == null || originTimeJst == null
        ? null
        : firstCandidateAt.difference(originTimeJst).inMilliseconds / 1000.0,
    firstConfirmedDelaySeconds:
        firstConfirmedAt == null || originTimeJst == null
        ? null
        : firstConfirmedAt.difference(originTimeJst).inMilliseconds / 1000.0,
  );
}

Map<StationTriggerState, int> _stationTriggerCounts(
  List<StationTriggerSnapshot> snapshots,
) {
  final counts = <StationTriggerState, int>{};
  for (final snapshot in snapshots) {
    counts.update(snapshot.state, (value) => value + 1, ifAbsent: () => 1);
  }
  return Map.unmodifiable(counts);
}

LocalObservabilityFrameDiagnostics _localObservabilityDiagnostics(
  List<StationTriggerSnapshot> snapshots,
  LatLng truth,
  double radiusKm,
  SpatiotemporalEventDetector detector,
) {
  final local = snapshots
      .where((snapshot) {
        final latitude = snapshot.latitude;
        final longitude = snapshot.longitude;
        if (latitude == null || longitude == null) return false;
        return _distanceKm(LatLng(latitude, longitude), truth) <= radiusKm;
      })
      .toList(growable: false);
  final rising = local
      .where((snapshot) => snapshot.state == StationTriggerState.rising)
      .length;
  final triggered = local.where((snapshot) {
    return snapshot.state == StationTriggerState.triggered ||
        snapshot.state == StationTriggerState.strong;
  }).length;
  final network = detector.diagnose(local);
  return LocalObservabilityFrameDiagnostics(
    risingStationCount: rising,
    triggeredStationCount: triggered,
    largestConnectedComponentSize: network.largestComponentSize,
  );
}

StationTriggerCaseSummary _summarizeStationTriggers(
  List<EventDetectionFrameReport> frames,
  String detectorId,
  Map<String, _StationTriggerAccumulator> accumulators,
) {
  var framesWithRisingStations = 0;
  var framesWithTriggeredStations = 0;
  var framesWithStrongStations = 0;
  var maxRisingStationCount = 0;
  var maxTriggeredStationCount = 0;
  var maxStrongStationCount = 0;

  for (final frame in frames.where((frame) => frame.decoded)) {
    final rising = frame.stationTriggerCounts[StationTriggerState.rising] ?? 0;
    final triggered =
        frame.stationTriggerCounts[StationTriggerState.triggered] ?? 0;
    final strong = frame.stationTriggerCounts[StationTriggerState.strong] ?? 0;
    if (rising > 0) framesWithRisingStations++;
    if (triggered > 0) framesWithTriggeredStations++;
    if (strong > 0) framesWithStrongStations++;
    if (rising > maxRisingStationCount) maxRisingStationCount = rising;
    if (triggered > maxTriggeredStationCount) {
      maxTriggeredStationCount = triggered;
    }
    if (strong > maxStrongStationCount) maxStrongStationCount = strong;
  }

  final stationSummaries = accumulators.values
      .where((station) => station.maxActivity >= 1 || station.wasEverActive)
      .map((station) => station.toSummary())
      .toList();
  stationSummaries.sort((left, right) {
    final triggeredOrder = right.triggeredFrameCount.compareTo(
      left.triggeredFrameCount,
    );
    if (triggeredOrder != 0) return triggeredOrder;
    final activityOrder = right.maxActivity.compareTo(left.maxActivity);
    if (activityOrder != 0) return activityOrder;
    return left.stationId.compareTo(right.stationId);
  });
  final triggeredStations = stationSummaries
      .where((station) => station.triggeredFrameCount > 0)
      .toList(growable: false);

  return StationTriggerCaseSummary(
    detectorId: detectorId,
    framesWithRisingStations: framesWithRisingStations,
    framesWithTriggeredStations: framesWithTriggeredStations,
    framesWithStrongStations: framesWithStrongStations,
    maxRisingStationCount: maxRisingStationCount,
    maxTriggeredStationCount: maxTriggeredStationCount,
    maxStrongStationCount: maxStrongStationCount,
    uniqueActivityAtLeast1StationCount: stationSummaries.length,
    uniqueActivityAtLeast2StationCount: stationSummaries
        .where((station) => station.maxActivity >= 2)
        .length,
    uniqueActivityAtLeast3StationCount: stationSummaries
        .where((station) => station.maxActivity >= 3)
        .length,
    uniqueRisingStationCount: stationSummaries
        .where((station) => station.risingFrameCount > 0)
        .length,
    uniqueTriggeredStationCount: triggeredStations.length,
    uniqueStrongStationCount: stationSummaries
        .where((station) => station.strongFrameCount > 0)
        .length,
    uniqueTriggeredStationCountByRadiusKm: {
      for (final radiusKm in const [50, 100, 160])
        radiusKm: triggeredStations
            .where(
              (station) =>
                  station.distanceToTruthKm != null &&
                  station.distanceToTruthKm! <= radiusKm,
            )
            .length,
    },
    stations: List.unmodifiable(stationSummaries),
  );
}

class _StationTriggerAccumulator {
  final String stationId;
  final double? latitude;
  final double? longitude;
  final double? distanceToTruthKm;
  DateTime? firstRisingAtJst;
  DateTime? firstTriggeredAtJst;
  double maxActivity = 0;
  int maxAscend = 0;
  int? maxDetectLevel;
  int risingFrameCount = 0;
  int triggeredFrameCount = 0;
  int strongFrameCount = 0;

  _StationTriggerAccumulator({
    required this.stationId,
    required this.latitude,
    required this.longitude,
    required this.distanceToTruthKm,
  });

  factory _StationTriggerAccumulator.fromSnapshot(
    StationTriggerSnapshot snapshot,
    LatLng? truth,
  ) {
    final latitude = snapshot.latitude;
    final longitude = snapshot.longitude;
    final coordinate = latitude == null || longitude == null
        ? null
        : LatLng(latitude, longitude);
    return _StationTriggerAccumulator(
      stationId: snapshot.stationId,
      latitude: latitude,
      longitude: longitude,
      distanceToTruthKm: coordinate == null || truth == null
          ? null
          : _distanceKm(coordinate, truth),
    );
  }

  bool get wasEverActive =>
      risingFrameCount > 0 || triggeredFrameCount > 0 || strongFrameCount > 0;

  void update(StationTriggerSnapshot snapshot) {
    if (snapshot.activity > maxActivity) maxActivity = snapshot.activity;
    if (snapshot.ascend > maxAscend) maxAscend = snapshot.ascend;
    final detectLevel = snapshot.detectLevel;
    if (detectLevel != null &&
        (maxDetectLevel == null || detectLevel > maxDetectLevel!)) {
      maxDetectLevel = detectLevel;
    }
    switch (snapshot.state) {
      case StationTriggerState.rising:
        firstRisingAtJst ??= snapshot.observedAt;
        risingFrameCount++;
      case StationTriggerState.triggered:
        firstRisingAtJst ??= snapshot.observedAt;
        firstTriggeredAtJst ??= snapshot.observedAt;
        triggeredFrameCount++;
      case StationTriggerState.strong:
        firstRisingAtJst ??= snapshot.observedAt;
        firstTriggeredAtJst ??= snapshot.observedAt;
        triggeredFrameCount++;
        strongFrameCount++;
      case StationTriggerState.idle ||
          StationTriggerState.decaying ||
          StationTriggerState.ended:
        break;
    }
  }

  StationTriggerStationSummary toSummary() => StationTriggerStationSummary(
    stationId: stationId,
    latitude: latitude,
    longitude: longitude,
    distanceToTruthKm: distanceToTruthKm,
    firstRisingAtJst: firstRisingAtJst,
    firstTriggeredAtJst: firstTriggeredAtJst,
    maxActivity: maxActivity,
    maxAscend: maxAscend,
    maxDetectLevel: maxDetectLevel,
    risingFrameCount: risingFrameCount,
    triggeredFrameCount: triggeredFrameCount,
    strongFrameCount: strongFrameCount,
  );
}

NetworkAssociationCaseSummary _summarizeNetworkAssociation(
  List<EventDetectionFrameReport> frames,
  String detectorId,
  DateTime? originTimeJst,
  LatLng? truth,
) {
  var maxTriggeredStationCount = 0;
  var maxComponentCount = 0;
  var maxLargestComponentSize = 0;
  var maxLargestComponentDiameterKm = 0.0;
  var maxQualityWeightedSupport = 0.0;
  double? maxTriggerTimeSpanSeconds;
  DateTime? peakTriggeredAtJst;
  List<int> peakTriggeredComponentSizes = const [];

  for (final frame in frames.where((frame) => frame.decoded)) {
    final diagnostics = frame.networkDiagnostics;
    if (diagnostics == null) continue;
    if (diagnostics.triggeredStationCount > maxTriggeredStationCount) {
      maxTriggeredStationCount = diagnostics.triggeredStationCount;
      peakTriggeredAtJst = frame.observedAtJst;
      peakTriggeredComponentSizes = diagnostics.componentSizes;
    }
    if (diagnostics.componentCount > maxComponentCount) {
      maxComponentCount = diagnostics.componentCount;
    }
    if (diagnostics.largestComponentSize > maxLargestComponentSize) {
      maxLargestComponentSize = diagnostics.largestComponentSize;
    }
    if (diagnostics.largestComponentDiameterKm >
        maxLargestComponentDiameterKm) {
      maxLargestComponentDiameterKm = diagnostics.largestComponentDiameterKm;
    }
    if (diagnostics.largestComponentQualityWeightedSupport >
        maxQualityWeightedSupport) {
      maxQualityWeightedSupport =
          diagnostics.largestComponentQualityWeightedSupport;
    }
    final triggerSpan = diagnostics.largestComponentTriggerTimeSpanSeconds;
    if (triggerSpan != null &&
        (maxTriggerTimeSpanSeconds == null ||
            triggerSpan > maxTriggerTimeSpanSeconds)) {
      maxTriggerTimeSpanSeconds = triggerSpan;
    }
  }

  return NetworkAssociationCaseSummary(
    detectorId: detectorId,
    maxTriggeredStationCount: maxTriggeredStationCount,
    maxComponentCount: maxComponentCount,
    maxLargestComponentSize: maxLargestComponentSize,
    maxLargestComponentDiameterKm: maxLargestComponentDiameterKm,
    maxQualityWeightedSupport: maxQualityWeightedSupport,
    maxTriggerTimeSpanSeconds: maxTriggerTimeSpanSeconds,
    peakTriggeredAtJst: peakTriggeredAtJst,
    peakTriggeredComponentSizes: List.unmodifiable(peakTriggeredComponentSizes),
    radiusSweep: _summarizeRadiusSweep(frames),
    temporalBridgeSweep: _summarizeTemporalBridgeSweep(
      frames,
      originTimeJst,
      truth,
    ),
    localObservability: _summarizeLocalObservability(frames),
  );
}

List<LocalObservabilityRadiusSummary> _summarizeLocalObservability(
  List<EventDetectionFrameReport> frames,
) {
  final radii = <int>{
    for (final frame in frames) ...frame.localObservabilityByRadius.keys,
  }.toList(growable: false)..sort();
  return List.unmodifiable(
    radii.map((radiusKm) {
      var maxRising = 0;
      var maxTriggered = 0;
      var maxConnected = 0;
      var candidateFrames = 0;
      var confirmedFrames = 0;
      for (final frame in frames.where((frame) => frame.decoded)) {
        final diagnostics = frame.localObservabilityByRadius[radiusKm];
        if (diagnostics == null) continue;
        if (diagnostics.risingStationCount > maxRising) {
          maxRising = diagnostics.risingStationCount;
        }
        if (diagnostics.triggeredStationCount > maxTriggered) {
          maxTriggered = diagnostics.triggeredStationCount;
        }
        if (diagnostics.largestConnectedComponentSize > maxConnected) {
          maxConnected = diagnostics.largestConnectedComponentSize;
        }
        if (diagnostics.largestConnectedComponentSize >= 4) candidateFrames++;
        if (diagnostics.largestConnectedComponentSize >= 6) confirmedFrames++;
      }
      return LocalObservabilityRadiusSummary(
        radiusKm: radiusKm,
        maxRisingStationCount: maxRising,
        maxTriggeredStationCount: maxTriggered,
        maxConnectedStationCount: maxConnected,
        candidateEvidenceFrameCount: candidateFrames,
        confirmedEvidenceFrameCount: confirmedFrames,
      );
    }),
  );
}

List<NetworkRadiusSweepSummary> _summarizeRadiusSweep(
  List<EventDetectionFrameReport> frames,
) {
  final radii = <int>{
    for (final frame in frames) ...frame.networkDiagnosticsByRadius.keys,
  }.toList(growable: false)..sort();
  return List.unmodifiable(
    radii.map((radiusKm) {
      var maxLargestComponentSize = 0;
      var candidateFrameCount = 0;
      var confirmedFrameCount = 0;
      for (final frame in frames.where((frame) => frame.decoded)) {
        final diagnostics = frame.networkDiagnosticsByRadius[radiusKm];
        if (diagnostics == null) continue;
        final size = diagnostics.largestComponentSize;
        if (size > maxLargestComponentSize) {
          maxLargestComponentSize = size;
        }
        if (size >= 4) candidateFrameCount++;
        if (size >= 6) confirmedFrameCount++;
      }
      return NetworkRadiusSweepSummary(
        radiusKm: radiusKm,
        maxLargestComponentSize: maxLargestComponentSize,
        candidateFrameCount: candidateFrameCount,
        confirmedFrameCount: confirmedFrameCount,
      );
    }),
  );
}

List<TemporalBridgeSweepCaseSummary> _summarizeTemporalBridgeSweep(
  List<EventDetectionFrameReport> frames,
  DateTime? originTimeJst,
  LatLng? truth,
) {
  final keys =
      <String>{
        for (final frame in frames) ...frame.temporalBridgeSweepDetections.keys,
      }.toList(growable: false)..sort((a, b) {
        final left = _parseTemporalBridgeSweepKey(a);
        final right = _parseTemporalBridgeSweepKey(b);
        final distanceOrder = left.$1.compareTo(right.$1);
        return distanceOrder != 0 ? distanceOrder : left.$2.compareTo(right.$2);
      });
  return List.unmodifiable(
    keys.map((key) {
      final config = _parseTemporalBridgeSweepKey(key);
      var candidateFrameCount = 0;
      var confirmedFrameCount = 0;
      DateTime? firstCandidateAtJst;
      DateTime? firstConfirmedAtJst;
      NetworkAssociationDiagnostics? firstCandidateDiagnostics;
      String detectorId = 'unknown';

      for (final frame in frames.where((frame) => frame.decoded)) {
        final detection = frame.temporalBridgeSweepDetections[key];
        if (detection == null) continue;
        detectorId = detection.detectorId;
        if (_isCandidateDetectionState(detection.state)) {
          candidateFrameCount++;
          if (firstCandidateAtJst == null) {
            firstCandidateAtJst = frame.observedAtJst;
            firstCandidateDiagnostics =
                frame.temporalBridgeSweepDiagnostics[key];
          }
        }
        if (_isConfirmedDetectionState(detection.state)) {
          confirmedFrameCount++;
          firstConfirmedAtJst ??= frame.observedAtJst;
        }
      }

      return TemporalBridgeSweepCaseSummary(
        detectorId: detectorId,
        bridgeDistanceKm: config.$1,
        maxGapSeconds: config.$2,
        candidateFrameCount: candidateFrameCount,
        confirmedFrameCount: confirmedFrameCount,
        firstCandidateAtJst: firstCandidateAtJst,
        firstConfirmedAtJst: firstConfirmedAtJst,
        firstCandidateDelaySeconds:
            firstCandidateAtJst == null || originTimeJst == null
            ? null
            : firstCandidateAtJst.difference(originTimeJst).inMilliseconds /
                  1000.0,
        firstConfirmedDelaySeconds:
            firstConfirmedAtJst == null || originTimeJst == null
            ? null
            : firstConfirmedAtJst.difference(originTimeJst).inMilliseconds /
                  1000.0,
        firstCandidateStationIds:
            firstCandidateDiagnostics?.largestComponentStationIds ?? const [],
        firstCandidateStrongEdgeCount:
            firstCandidateDiagnostics?.largestComponentStrongEdgeCount ?? 0,
        firstCandidateWeakEdgeCount:
            firstCandidateDiagnostics?.largestComponentWeakEdgeCount ?? 0,
        firstCandidateTriggerIntervals:
            firstCandidateDiagnostics?.largestComponentTriggerIntervals ??
            const {},
        firstCandidateClusterDistanceToTruthKm:
            truth == null ||
                firstCandidateDiagnostics?.largestComponentCentroidLatitude ==
                    null ||
                firstCandidateDiagnostics?.largestComponentCentroidLongitude ==
                    null
            ? null
            : _distanceKm(
                LatLng(
                  firstCandidateDiagnostics!.largestComponentCentroidLatitude!,
                  firstCandidateDiagnostics.largestComponentCentroidLongitude!,
                ),
                truth,
              ),
      );
    }),
  );
}

String _temporalBridgeSweepKey(int distanceKm, int gapSeconds) {
  return 'd${distanceKm}_g$gapSeconds';
}

(int, int) _parseTemporalBridgeSweepKey(String key) {
  final match = RegExp(r'^d(\d+)_g(\d+)$').firstMatch(key);
  if (match == null) {
    throw FormatException('Invalid temporal bridge sweep key: $key');
  }
  return (int.parse(match.group(1)!), int.parse(match.group(2)!));
}

bool _isCandidateDetectionState(EventDetectionState state) {
  return state == EventDetectionState.candidate ||
      state == EventDetectionState.confirmed ||
      state == EventDetectionState.strong;
}

bool _isConfirmedDetectionState(EventDetectionState state) {
  return state == EventDetectionState.confirmed ||
      state == EventDetectionState.strong;
}

int _maxStationDetectLevel(List<NiedStation> stations) {
  var maxLevel = -1;
  for (final station in stations) {
    if (station.detectLevel > maxLevel) {
      maxLevel = station.detectLevel;
    }
  }
  return maxLevel;
}

double _maxStationActivity(List<NiedStation> stations) {
  var maxActivity = 0.0;
  for (final station in stations) {
    if (station.activity > maxActivity) {
      maxActivity = station.activity;
    }
  }
  return maxActivity;
}

List<SeismicStationSample> _samplesFromNiedStations(
  List<NiedStation> stations,
  DateTime observedAt,
  Map<String, StationTriggerSnapshot> triggersByCode,
) {
  return stations
      .map((station) {
        final isKik = station.network.toLowerCase().contains('kik');
        final trigger = triggersByCode[station.code];
        return SeismicStationSample(
          descriptor: SeismicStationDescriptor(
            stationId: station.code,
            code: station.code,
            sourceId: 'nied_benchmark',
            network: station.network,
            coordinate: station.coordinate,
            sensorRole: StationSensorRole.surface,
            tags: {
              'prefecture': station.prefecture,
              'gif_display_primary_layer': 'jma_s',
              'physical_sensor_role': isKik
                  ? 'kik_surface_or_borehole'
                  : 'surface',
            },
          ),
          observedAt: observedAt,
          valueType: StationValueType.jmaShindo,
          value: station.gifObservation?.shindo,
          observedPga: station.gifObservation?.pga,
          observedPgv: station.gifObservation?.pgv,
          observedPgd: station.gifObservation?.pgd,
          rawLevel: station.level >= 0 ? station.level : null,
          detectLevel: station.detectLevel >= 0 ? station.detectLevel : null,
          activity: trigger?.activity ?? 0,
          ascend: trigger?.ascend ?? 0,
          isTriggered:
              trigger?.state == StationTriggerState.triggered ||
              trigger?.state == StationTriggerState.strong,
          firstRiseInterval: trigger?.firstRiseInterval,
          firstTriggerInterval: trigger?.firstTriggerInterval,
        );
      })
      .toList(growable: false);
}

List<Map<String, Object?>> _kotoho7ReceiverFrameObservationsFromSamples(
  List<SeismicStationSample> samples, {
  required DateTime observedAt,
}) {
  final observedAtUtc = observedAt.toUtc().toIso8601String();
  final observations = <Map<String, Object?>>[];
  for (final sample in samples) {
    final shindo = sample.value;
    if (shindo == null || !shindo.isFinite) continue;
    observations.add({
      'stationCode': sample.descriptor.code,
      'observedAtUtc': observedAtUtc,
      'gifDecodedShindo': shindo,
    });
  }
  return observations;
}

Map<String, Object?> _stationTriggerObservationTimesJson(
  Map<String, StationTriggerSnapshot> triggersByCode,
) {
  final entries = triggersByCode.entries.toList(growable: false)
    ..sort((left, right) => left.key.compareTo(right.key));
  return {
    for (final entry in entries)
      if (entry.value.firstRiseInterval != null ||
          entry.value.firstTriggerInterval != null)
        entry.key: {
          'state': entry.value.state.name,
          'observed_at': entry.value.observedAt.toIso8601String(),
          'first_rise_start_at': entry.value.firstRiseInterval?.start
              .toIso8601String(),
          'first_rise_at': entry.value.firstRiseInterval?.end.toIso8601String(),
          'first_trigger_start_at': entry.value.firstTriggerInterval?.start
              .toIso8601String(),
          'first_trigger_at': entry.value.firstTriggerInterval?.end
              .toIso8601String(),
          'observed_time_source': entry.value.firstTriggerInterval != null
              ? 'first_trigger_at'
              : 'first_rise_at',
        },
  };
}

SourceEstimationMethodFrame _runTrackerFrame({
  required SeismicSourceTracker tracker,
  required String sourceId,
  required DateTime observedAt,
  required String stageName,
  required int maxShindo,
  required List<SeismicStationSample> samples,
  required LatLng? truth,
  required Map<String, LatLng> previousPoints,
  String? eventId,
  Map<String, Object?> metadata = const {},
  bool splitOnEventIdChange = false,
}) {
  final stopwatch = Stopwatch()..start();
  tracker.ingestFrame(
    sourceId: sourceId,
    observedAt: observedAt,
    stageName: stageName,
    maxShindo: maxShindo,
    samples: samples,
    eventId: eventId,
    metadata: metadata,
    splitOnEventIdChange: splitOnEventIdChange,
  );
  final estimate = tracker.currentEvent(sourceId)?.estimate;
  final eventMetadata = tracker.currentEvent(sourceId)?.metadata;
  stopwatch.stop();
  return _methodFrame(
    methodId: sourceId,
    estimate: estimate,
    truth: truth,
    previousPoints: previousPoints,
    runtimeMicros: stopwatch.elapsedMicroseconds,
    eventMetadata: eventMetadata,
  );
}

SourceEstimationMethodFrame _runScratchFrame(
  List<NiedStation> stations,
  LatLng? truth,
  Map<String, LatLng> previousPoints, {
  required bool enabled,
}) {
  final stopwatch = Stopwatch()..start();
  final scratch = enabled ? HypocenterEstimator.estimate(stations) : null;
  stopwatch.stop();
  final estimate = scratch == null
      ? null
      : SourceEstimate(
          latitude: scratch.latitude,
          longitude: scratch.longitude,
          confidence: scratch.confidence,
          method: SourceEstimationBenchmarkRunner.scratchMethod,
          supportingStationCount: stations
              .where((station) => station.isActive && station.level >= 0)
              .length,
        );
  return _methodFrame(
    methodId: SourceEstimationBenchmarkRunner.scratchMethod,
    estimate: estimate,
    truth: truth,
    previousPoints: previousPoints,
    runtimeMicros: stopwatch.elapsedMicroseconds,
  );
}

SourceEstimationMethodFrame _runHypDiagnosticFrame({
  required String methodId,
  required SourceEstimate? sourceEstimate,
  required LatLng? truth,
  required Map<String, LatLng> previousPoints,
}) {
  final stopwatch = Stopwatch()..start();
  final hyp = sourceEstimate?.diagnostics[methodId];
  final estimate = hyp is Map<String, Object?>
      ? _estimateFromHypDiagnostic(methodId, hyp)
      : null;
  stopwatch.stop();
  return _methodFrame(
    methodId: methodId,
    estimate: estimate,
    truth: truth,
    previousPoints: previousPoints,
    runtimeMicros: stopwatch.elapsedMicroseconds,
    eventMetadata: hyp is Map<String, Object?>
        ? {
            'diagnostic_source_method': sourceEstimate?.method,
            'diagnostic_supported': hyp['supported'],
            'diagnostic_p_only_supported': hyp['p_only_supported'],
            'diagnostic_depth_supported': hyp['depth_supported'],
            'diagnostic_scoring_model': hyp['scoring_model'],
          }
        : const {'diagnostic_present': false},
  );
}

SourceEstimate? _estimateFromHypDiagnostic(
  String methodId,
  Map<String, Object?> hyp,
) {
  final latitude = (hyp['latitude'] as num?)?.toDouble();
  final longitude = (hyp['longitude'] as num?)?.toDouble();
  if (latitude == null ||
      longitude == null ||
      !latitude.isFinite ||
      !longitude.isFinite) {
    return null;
  }
  final pCount = (hyp['phase_p_count'] as num?)?.toInt() ?? 0;
  final sCount = (hyp['phase_s_count'] as num?)?.toInt() ?? 0;
  final otherCount = (hyp['phase_other_count'] as num?)?.toInt() ?? 0;
  final weightedCount = (hyp['weighted_count'] as num?)?.toInt();
  final supported = hyp['supported'] == true;
  final pOnlySupported = hyp['p_only_supported'] == true;
  final depthSupported = hyp['depth_supported'] == true;
  final phaseMeanResidual =
      (hyp['phase_mean_residual_s'] as num?)?.toDouble() ?? double.infinity;
  final residualFit = phaseMeanResidual.isFinite
      ? 1.0 / (1.0 + phaseMeanResidual)
      : 0.0;
  final confidence =
      (0.12 +
              (supported ? 0.26 : 0.0) +
              (pOnlySupported ? 0.08 : 0.0) +
              (depthSupported ? 0.08 : 0.0) +
              residualFit * 0.22 +
              math.min(0.18, math.max(pCount + sCount, 0) * 0.015))
          .clamp(0.0, 0.92);
  DateTime? originTime;
  final rawOriginTime = hyp['origin_time'];
  if (rawOriginTime is String) {
    originTime = DateTime.tryParse(rawOriginTime);
  }
  return SourceEstimate(
    latitude: latitude,
    longitude: longitude,
    depthKm: (hyp['depth_km'] as num?)?.toDouble(),
    originTime: originTime,
    confidence: confidence,
    method: methodId,
    supportingStationCount: weightedCount ?? pCount + sCount + otherCount,
    diagnostics: {
      ...hyp,
      'benchmark_method_bridge':
          'hybrid_diagnostics_promoted_to_independent_method_frame_v1',
    },
  );
}

class _JqReferenceHypStateMachine {
  static const _residualToleranceSeconds = 2.8;
  static const _stationRowLimit = 16;
  static const _unscoredSeedScore = 1.0e9;

  DateTime? _firstDetectionAt;
  int _sourceRevision = 0;
  _JqSourceCache? _sourceCache;
  _JqSourceSearchResult? _lastSearch;
  String? _lastSourceCacheDecision;
  Map<String, Object?>? _lastSourceCacheDecisionTrace;
  SourceEstimate? _lastBridgeEstimate;
  final Map<String, _JqStationState> _stations = {};

  bool get isActive => _firstDetectionAt != null;

  SourceEstimationMethodFrame runFrame({
    required DateTime observedAt,
    required SeismicActiveEvent? event,
    required SourceEstimate? bridgeEstimate,
    required LatLng? truth,
    required Map<String, LatLng> previousPoints,
  }) {
    final stopwatch = Stopwatch()..start();
    final diagnosticsEnabled =
        bridgeEstimate != null || _firstDetectionAt != null;
    if (diagnosticsEnabled && event != null) {
      _firstDetectionAt ??= event.startedAt;
      _lastBridgeEstimate = bridgeEstimate;
      final memberIds = _sourceTriggerMemberIds(event.metadata);
      for (final record in event.records.where(
        (record) => _isStateMachineMember(record, memberIds),
      )) {
        _updateStationObservation(record, observedAt);
      }
      _clearStaleMembership(observedAt, memberIds);
      _updateSourceCache(observedAt);
      _recomputeStationPredictions();
    }
    final estimate = _buildEstimate(observedAt);
    stopwatch.stop();
    return _methodFrame(
      methodId: SourceEstimationBenchmarkRunner.jqReferenceStateMachineMethod,
      estimate: estimate,
      truth: truth,
      previousPoints: previousPoints,
      runtimeMicros: stopwatch.elapsedMicroseconds,
      eventMetadata: {
        'state_machine_present': estimate != null,
        'state_machine_model':
            'jq_reference_state_machine_v5_depth_pair_origin_scoring',
        'source_cache_revision': _sourceRevision,
        'station_state_count': _stations.length,
      },
    );
  }

  void _updateSourceCache(DateTime observedAt) {
    final firstDetectionAt = _firstDetectionAt;
    if (firstDetectionAt == null) return;
    final usable = _usableStationStates(observedAt);
    final ageSeconds = _secondsBetween(observedAt, firstDetectionAt);
    final next = ageSeconds < 10.0 || usable.length < 3
        ? _seedSourceCache(firstDetectionAt)
        : _searchSourceCache(
            observedAt: observedAt,
            firstDetectionAt: firstDetectionAt,
            usable: usable,
          )?.cache;
    if (next == null) return;
    final previous = _sourceCache;
    _JqSourceCacheUpdateDecision? updateDecision;
    if (previous != null) {
      updateDecision = _sourceCacheUpdateDecision(previous, next);
      _lastSourceCacheDecisionTrace = _sourceCacheDecisionTrace(
        previous: previous,
        next: next,
        decision: updateDecision,
      );
      if (!updateDecision.accepted) {
        _lastSourceCacheDecision = updateDecision.label;
        return;
      }
    } else {
      _lastSourceCacheDecisionTrace = {
        'decision': 'accepted_initial_source_cache',
        'accepted': true,
        'previous': null,
        'next': next.toJson(),
      };
    }
    final changed =
        previous == null ||
        (previous.latitude - next.latitude).abs() > 0.0001 ||
        (previous.longitude - next.longitude).abs() > 0.0001 ||
        (previous.depthKm - next.depthKm).abs() > 0.001 ||
        previous.originTime != next.originTime;
    if (!changed) return;
    _sourceCache = next;
    _sourceRevision++;
    _lastSourceCacheDecision = previous == null
        ? 'accepted_initial_source_cache'
        : updateDecision?.label ?? 'accepted_refinement';
  }

  void _updateStationObservation(
    SeismicStationEventRecord record,
    DateTime observedAt,
  ) {
    final state = _stations.putIfAbsent(
      record.descriptor.code,
      () => _JqStationState(descriptor: record.descriptor),
    );
    state.descriptor = record.descriptor;
    state.tenPlus2LastUpdateTime = record.lastObservedAt ?? observedAt;
    state.tenPlus3DetectionId = 1;
    state.tenPlus1ObservedTime =
        record.firstTriggerAt ?? record.firstRiseAt ?? record.firstObservedAt;
    state.tenPlus1ObservedSource = record.firstTriggerAt != null
        ? 'first_trigger_at'
        : record.firstRiseAt != null
        ? 'first_rise_at'
        : 'first_observed_at';

    final signal = _recordSignal(record);
    final activeLike = record.isActiveLike;
    if (!activeLike) {
      state.tenPlus5PretriggerCacheTime = null;
    } else {
      final risingBySignal =
          signal != null &&
          (state.previousSignal == null ||
              signal > state.previousSignal! + 0.01);
      final detectLevel = record.lastDetectLevel;
      final risingByDetectLevel =
          detectLevel != null &&
          (state.previousDetectLevel == null ||
              detectLevel > state.previousDetectLevel!);
      final risingByState =
          record.state == StationLifecycleState.triggered ||
          record.state == StationLifecycleState.strong;
      if (risingBySignal || risingByDetectLevel || risingByState) {
        state.tenPlus5PretriggerCacheTime ??= observedAt;
      }
    }
    state.previousSignal = signal ?? state.previousSignal;
    state.previousDetectLevel =
        record.lastDetectLevel ?? state.previousDetectLevel;
  }

  void _clearStaleMembership(DateTime observedAt, Set<String> memberIds) {
    for (final state in _stations.values) {
      final isCurrentMember =
          memberIds.isEmpty ||
          memberIds.contains(state.descriptor.stationId) ||
          memberIds.contains(state.descriptor.code);
      final updatedAt = state.tenPlus2LastUpdateTime;
      final staleSeconds = updatedAt == null
          ? double.infinity
          : observedAt.difference(updatedAt).inMilliseconds / 1000.0;
      if (!isCurrentMember || staleSeconds > 12.0) {
        state
          ..tenPlus3DetectionId = null
          ..tenPlus5PretriggerCacheTime = null
          ..tenPlus6SCloserThanP = null
          ..tenPlus7PredictedPArrivalSeconds = null
          ..tenPlus8PredictedSArrivalSeconds = null
          ..pResidualSeconds = null
          ..sResidualSeconds = null;
      }
    }
  }

  void _recomputeStationPredictions() {
    final source = _sourceCache;
    final firstDetectionAt = _firstDetectionAt;
    if (source == null || firstDetectionAt == null) return;
    for (final state in _stations.values) {
      final observed = state.referenceLikeObservedTime;
      if (observed == null) continue;
      _recomputeStationPrediction(
        state,
        source: source,
        firstDetectionAt: firstDetectionAt,
        observed: observed,
      );
    }
  }

  void _recomputeStationPrediction(
    _JqStationState state, {
    required _JqSourceCache source,
    required DateTime firstDetectionAt,
    required DateTime observed,
  }) {
    final surfaceDistanceKm = _distanceKm(
      LatLng(source.latitude, source.longitude),
      state.descriptor.coordinate,
    );
    state.tenPlus4DistanceKm = surfaceDistanceKm;
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + source.depthKm * source.depthKm,
    );
    final sourceOriginSeconds = _secondsBetween(
      source.originTime,
      firstDetectionAt,
    );
    final pTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: source.depthKm,
      pWave: true,
    );
    final sTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: source.depthKm,
      pWave: false,
    );
    state
      ..tenPlus7PredictedPArrivalSeconds = sourceOriginSeconds + pTravelSeconds
      ..tenPlus8PredictedSArrivalSeconds = sourceOriginSeconds + sTravelSeconds
      ..lastRecomputedSourceRevision = _sourceRevision
      ..recomputeCount += 1;
    final observedSeconds = _secondsBetween(observed, firstDetectionAt);
    final pResidual =
        (observedSeconds - state.tenPlus7PredictedPArrivalSeconds!).abs();
    final sResidual =
        (observedSeconds - state.tenPlus8PredictedSArrivalSeconds!).abs();
    state
      ..pResidualSeconds = pResidual
      ..sResidualSeconds = sResidual
      ..tenPlus6SCloserThanP = sResidual < pResidual;
  }

  List<_JqStationState> _usableStationStates(DateTime observedAt) {
    final firstDetectionAt = _firstDetectionAt;
    if (firstDetectionAt == null) return const [];
    return _stations.values
        .where((state) {
          if (state.tenPlus3DetectionId == null ||
              state.referenceLikeObservedTime == null) {
            return false;
          }
          final updatedAt = state.tenPlus2LastUpdateTime;
          if (updatedAt == null) return false;
          final staleSeconds =
              observedAt.difference(updatedAt).inMilliseconds / 1000.0;
          if (staleSeconds > 20.0) return false;
          final observedSeconds = _secondsBetween(
            state.referenceLikeObservedTime!,
            firstDetectionAt,
          );
          return observedSeconds.isFinite && observedSeconds > -20.0;
        })
        .toList(growable: false);
  }

  _JqSourceCache? _seedSourceCache(DateTime firstDetectionAt) {
    final states = _stations.values
        .where((state) => state.referenceLikeObservedTime != null)
        .toList(growable: false);
    if (states.isEmpty) return null;
    states.sort((a, b) {
      final at = a.referenceLikeObservedTime!;
      final bt = b.referenceLikeObservedTime!;
      return at.compareTo(bt);
    });
    final first = states.first;
    return _JqSourceCache(
      latitude: first.descriptor.coordinate.latitude,
      longitude: first.descriptor.coordinate.longitude,
      depthKm: 10.0,
      originTime: firstDetectionAt.subtract(const Duration(seconds: 2)),
      score: _unscoredSeedScore,
      phasePCount: 0,
      phaseSCount: 0,
      phaseOtherCount: 0,
      phaseMeanResidualSeconds: null,
      searchModel: 'reference_seed_first_detection_point_depth10_origin_minus2',
    );
  }

  _JqSourceSearchResult? _searchSourceCache({
    required DateTime observedAt,
    required DateTime firstDetectionAt,
    required List<_JqStationState> usable,
  }) {
    if (usable.length < 3) return null;
    final geometry = _geometryContextForUsableStations(
      usable,
      bridgeEstimate: _lastBridgeEstimate,
    );
    final bounds = _searchBoundsForUsableStations(usable, geometry);
    final current = _sourceCache;
    final center =
        current ??
        _JqSourceCache(
          latitude: _mean([
            for (final state in usable) state.descriptor.coordinate.latitude,
          ]),
          longitude: _mean([
            for (final state in usable) state.descriptor.coordinate.longitude,
          ]),
          depthKm: 10.0,
          originTime: firstDetectionAt.subtract(const Duration(seconds: 2)),
          score: double.infinity,
          phasePCount: 0,
          phaseSCount: 0,
          phaseOtherCount: 0,
          phaseMeanResidualSeconds: null,
          searchModel: 'centroid_seed',
        );
    final ageSeconds = _secondsBetween(observedAt, firstDetectionAt);
    final sGateOpen = ageSeconds > 15.0;
    final currentIsUnscoredSeed =
        current == null || current.score >= _unscoredSeedScore * 0.5;
    final stages = currentIsUnscoredSeed || ageSeconds < 18.0
        ? const [
            (radiusDeg: 1.2, stepDeg: 0.3),
            (radiusDeg: 0.36, stepDeg: 0.12),
          ]
        : ageSeconds < 35.0
        ? const [
            (radiusDeg: 0.72, stepDeg: 0.18),
            (radiusDeg: 0.24, stepDeg: 0.06),
          ]
        : const [
            (radiusDeg: 0.36, stepDeg: 0.12),
            (radiusDeg: 0.18, stepDeg: 0.06),
            (radiusDeg: 0.09, stepDeg: 0.03),
          ];
    const depthCandidatesKm = [10.0, 20.0, 40.0, 60.0, 80.0, 100.0, 140.0];
    final initialLat = center.latitude.clamp(bounds.minLat, bounds.maxLat);
    final initialLng = center.longitude.clamp(bounds.minLng, bounds.maxLng);
    var best = _scoreSourceCandidate(
      initialLat.toDouble(),
      initialLng.toDouble(),
      center.depthKm,
      usable: usable,
      firstDetectionAt: firstDetectionAt,
      sGateOpen: sGateOpen,
      geometry: geometry,
    );
    var stageCenterLat = initialLat.toDouble();
    var stageCenterLng = initialLng.toDouble();
    for (final stage in stages) {
      final latSteps = (stage.radiusDeg / stage.stepDeg).ceil();
      final lngSteps = (stage.radiusDeg / stage.stepDeg).ceil();
      for (var latIndex = -latSteps; latIndex <= latSteps; latIndex++) {
        final lat = stageCenterLat + latIndex * stage.stepDeg;
        if (lat < 20.0 || lat > 50.0) continue;
        for (var lngIndex = -lngSteps; lngIndex <= lngSteps; lngIndex++) {
          final lng = stageCenterLng + lngIndex * stage.stepDeg;
          if (lng < 120.0 || lng > 155.0) continue;
          for (final depthKm in depthCandidatesKm) {
            if (!bounds.contains(lat, lng)) continue;
            final candidate = _scoreSourceCandidate(
              lat,
              lng,
              depthKm,
              usable: usable,
              firstDetectionAt: firstDetectionAt,
              sGateOpen: sGateOpen,
              geometry: geometry,
            );
            if (candidate.score < best.score) best = candidate;
          }
        }
      }
      stageCenterLat = best.cache.latitude;
      stageCenterLng = best.cache.longitude;
    }
    _lastSearch = best;
    return best;
  }

  _JqSourceSearchResult _scoreSourceCandidate(
    double latitude,
    double longitude,
    double depthKm, {
    required List<_JqStationState> usable,
    required DateTime firstDetectionAt,
    required bool sGateOpen,
    required _JqGeometryContext geometry,
  }) {
    final picks = <_JqCandidatePick>[];
    final pOriginOffsets = <double>[];
    for (final state in usable) {
      final observed = state.referenceLikeObservedTime;
      if (observed == null) continue;
      final observedSeconds = _secondsBetween(observed, firstDetectionAt);
      final surfaceDistanceKm = _distanceKm(
        LatLng(latitude, longitude),
        state.descriptor.coordinate,
      );
      final hypocentralDistanceKm = math.sqrt(
        surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
      );
      final pTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: depthKm,
        pWave: true,
      );
      final sTravel = Jma2001TravelTimeApproximation.travelTimeSeconds(
        hypocentralDistanceKm: hypocentralDistanceKm,
        depthKm: depthKm,
        pWave: false,
      );
      final pOrigin = observedSeconds - pTravel;
      final sOrigin = observedSeconds - sTravel;
      pOriginOffsets.add(pOrigin);
      picks.add(
        _JqCandidatePick(
          observedSeconds: observedSeconds,
          pTravelSeconds: pTravel,
          sTravelSeconds: sTravel,
          pOriginOffsetSeconds: pOrigin,
          sOriginOffsetSeconds: sOrigin,
        ),
      );
    }
    if (picks.isEmpty) {
      return _JqSourceSearchResult(
        cache: _JqSourceCache(
          latitude: latitude,
          longitude: longitude,
          depthKm: depthKm,
          originTime: firstDetectionAt,
          score: double.infinity,
          phasePCount: 0,
          phaseSCount: 0,
          phaseOtherCount: 0,
          phaseMeanResidualSeconds: null,
          searchModel: 'owned_grid_search_v1',
          pOriginSpreadSeconds: null,
          pOriginClusterCount: 0,
        ),
        score: double.infinity,
      );
    }
    final pOriginMedian = _median(pOriginOffsets);
    final pOriginResiduals = [
      for (final offset in pOriginOffsets) (offset - pOriginMedian).abs(),
    ];
    final pOriginSpreadSeconds = _percentile(pOriginResiduals, 0.75) ?? 0.0;
    final pOriginClusterCount = pOriginResiduals
        .where((residual) => residual <= _residualToleranceSeconds)
        .length;
    final selectedOrigins = <double>[];
    var sCloserCount = 0;
    for (final pick in picks) {
      final pResidualToSeed = (pick.pOriginOffsetSeconds - pOriginMedian).abs();
      final sResidualToSeed = (pick.sOriginOffsetSeconds - pOriginMedian).abs();
      final useS = sGateOpen && sResidualToSeed < pResidualToSeed;
      if (useS) sCloserCount++;
      selectedOrigins.add(
        useS ? pick.sOriginOffsetSeconds : pick.pOriginOffsetSeconds,
      );
    }
    final originOffsetSeconds = _median(selectedOrigins);
    var pCount = 0;
    var sCount = 0;
    var otherCount = 0;
    var residualTotal = 0.0;
    final acceptedObservedSeconds = <double>[];
    final acceptedPredictedSeconds = <double>[];
    final acceptedPOrigins = <double>[];
    final acceptedSOrigins = <double>[];
    for (final pick in picks) {
      final pResidual = (pick.pOriginOffsetSeconds - originOffsetSeconds).abs();
      final sResidual = (pick.sOriginOffsetSeconds - originOffsetSeconds).abs();
      final useS = sGateOpen && sResidual < pResidual;
      final selectedResidual = useS ? sResidual : pResidual;
      residualTotal += selectedResidual;
      if (selectedResidual > _residualToleranceSeconds) {
        otherCount++;
      } else if (useS) {
        sCount++;
        acceptedObservedSeconds.add(pick.observedSeconds);
        acceptedPredictedSeconds.add(originOffsetSeconds + pick.sTravelSeconds);
        acceptedSOrigins.add(pick.sOriginOffsetSeconds);
      } else {
        pCount++;
        acceptedObservedSeconds.add(pick.observedSeconds);
        acceptedPredictedSeconds.add(originOffsetSeconds + pick.pTravelSeconds);
        acceptedPOrigins.add(pick.pOriginOffsetSeconds);
      }
    }
    final meanResidual = residualTotal / picks.length;
    final pair = _jqPairResidual(
      acceptedObservedSeconds,
      acceptedPredictedSeconds,
      maxPairs: 80,
    );
    final sOriginMedian = acceptedSOrigins.isEmpty
        ? null
        : _median(acceptedSOrigins);
    final sOriginResiduals = sOriginMedian == null
        ? const <double>[]
        : [
            for (final offset in acceptedSOrigins)
              (offset - sOriginMedian).abs(),
          ];
    final sOriginSpreadSeconds = sOriginResiduals.isEmpty
        ? null
        : (_percentile(sOriginResiduals, 0.75) ?? 0.0);
    final sOriginClusterCount = sOriginResiduals
        .where((residual) => residual <= _residualToleranceSeconds)
        .length;
    final acceptedPOriginMedian = acceptedPOrigins.isEmpty
        ? null
        : _median(acceptedPOrigins);
    final phaseOriginMeanGapSeconds =
        acceptedPOriginMedian == null || sOriginMedian == null
        ? null
        : (acceptedPOriginMedian - sOriginMedian).abs();
    final supportCount = pCount + sCount;
    final supportPenalty = math.max(0, 5 - supportCount) * 7.0;
    final pClusterPenalty = math.max(0, 5 - pOriginClusterCount) * 2.4;
    final pSpreadPenalty = math.min(12.0, pOriginSpreadSeconds * 0.45);
    final sClusterPenalty = sGateOpen
        ? math.max(0, 3 - sOriginClusterCount) * 1.8
        : 0.0;
    final sSpreadPenalty = sOriginSpreadSeconds == null
        ? (sGateOpen && sCount > 0 ? 4.0 : 0.0)
        : math.min(10.0, sOriginSpreadSeconds * 0.55);
    final phaseOriginGapPenalty = phaseOriginMeanGapSeconds == null
        ? 0.0
        : math.min(10.0, phaseOriginMeanGapSeconds * 0.75);
    final pairPenalty = math.min(
      12.0,
      pair.meanResidualSeconds * 0.85 + pair.score * 0.035,
    );
    final otherPenalty = otherCount * 1.6;
    final depthPenalty = depthKm * 0.01;
    final pOnlyDeepPenalty = sCount == 0
        ? math.max(0.0, depthKm - 40.0) * 0.08
        : 0.0;
    final weakSDeepPenalty = sGateOpen && sCount < 3
        ? math.max(0.0, depthKm - 60.0) * 0.04
        : 0.0;
    final geometryPenalty = _oneSidedGeometryPenalty(
      latitude: latitude,
      longitude: longitude,
      geometry: geometry,
    );
    final sOverfitPenalty = sGateOpen && pCount == 0 && sCount >= 6 ? 8.0 : 0.0;
    final score =
        meanResidual +
        supportPenalty +
        otherPenalty +
        depthPenalty +
        sOverfitPenalty +
        pClusterPenalty +
        pSpreadPenalty +
        geometryPenalty +
        pOnlyDeepPenalty +
        weakSDeepPenalty +
        sClusterPenalty +
        sSpreadPenalty +
        phaseOriginGapPenalty +
        pairPenalty;
    return _JqSourceSearchResult(
      cache: _JqSourceCache(
        latitude: latitude,
        longitude: longitude,
        depthKm: depthKm,
        originTime: firstDetectionAt.add(
          Duration(milliseconds: (originOffsetSeconds * 1000).round()),
        ),
        score: score,
        phasePCount: pCount,
        phaseSCount: sCount,
        phaseOtherCount: otherCount,
        phaseMeanResidualSeconds: meanResidual,
        searchModel: 'owned_grid_search_v1',
        sCloserCount: sCloserCount,
        pOriginSpreadSeconds: pOriginSpreadSeconds,
        pOriginClusterCount: pOriginClusterCount,
        sOriginSpreadSeconds: sOriginSpreadSeconds,
        sOriginClusterCount: sOriginClusterCount,
        phaseOriginMeanGapSeconds: phaseOriginMeanGapSeconds,
        pairMeanResidualSeconds: pair.meanResidualSeconds,
        pairCount: pair.count,
        geometryPenalty: geometryPenalty,
      ),
      score: score,
    );
  }

  _JqSourceCacheUpdateDecision _sourceCacheUpdateDecision(
    _JqSourceCache previous,
    _JqSourceCache next,
  ) {
    if (!next.score.isFinite) {
      return const _JqSourceCacheUpdateDecision(
        accepted: false,
        label: 'rejected_invalid_candidate',
      );
    }
    if (previous.score >= _unscoredSeedScore * 0.5) {
      final accepted = next.phasePCount + next.phaseSCount >= 3;
      return _JqSourceCacheUpdateDecision(
        accepted: accepted,
        label: accepted
            ? 'accepted_first_owned_search'
            : 'held_seed_waiting_for_support',
      );
    }
    final jumpKm = _distanceKm(
      LatLng(previous.latitude, previous.longitude),
      LatLng(next.latitude, next.longitude),
    );
    final previousScore = previous.score.isFinite ? previous.score : next.score;
    final improves = next.score <= previousScore + 0.8;
    if (jumpKm <= 45.0 && improves) {
      return const _JqSourceCacheUpdateDecision(
        accepted: true,
        label: 'accepted_refinement',
      );
    }
    if (jumpKm <= 90.0 && next.score + 4.0 < previousScore) {
      return const _JqSourceCacheUpdateDecision(
        accepted: true,
        label: 'accepted_strong_score_improvement',
      );
    }
    final previousPSpread = previous.pOriginSpreadSeconds ?? double.infinity;
    final nextPSpread = next.pOriginSpreadSeconds ?? double.infinity;
    if (jumpKm <= 90.0 &&
        next.pOriginClusterCount >= previous.pOriginClusterCount + 2 &&
        nextPSpread + 1.5 < previousPSpread) {
      return const _JqSourceCacheUpdateDecision(
        accepted: true,
        label: 'accepted_p_origin_cluster_improvement',
      );
    }
    if (next.phasePCount + next.phaseSCount >= 8 &&
        next.score + 7.0 < previousScore) {
      return const _JqSourceCacheUpdateDecision(
        accepted: true,
        label: 'accepted_high_support_score_improvement',
      );
    }
    final previousSupport = previous.phasePCount + previous.phaseSCount;
    final nextSupport = next.phasePCount + next.phaseSCount;
    final previousSpread = previous.pOriginSpreadSeconds ?? double.infinity;
    final heldGoodCache =
        previousSupport >= 5 &&
        previous.pOriginClusterCount >= 5 &&
        nextSupport <= previousSupport + 3 &&
        previous.score <= next.score + 2.5 &&
        previousSpread <= nextPSpread + 1.0;
    return _JqSourceCacheUpdateDecision(
      accepted: false,
      label: heldGoodCache
          ? 'held_good_cache'
          : 'blocked_needed_correction_or_low_quality_jump',
    );
  }

  Map<String, Object?> _sourceCacheDecisionTrace({
    required _JqSourceCache previous,
    required _JqSourceCache next,
    required _JqSourceCacheUpdateDecision decision,
  }) {
    final jumpKm = _distanceKm(
      LatLng(previous.latitude, previous.longitude),
      LatLng(next.latitude, next.longitude),
    );
    final previousSpread = previous.pOriginSpreadSeconds;
    final nextSpread = next.pOriginSpreadSeconds;
    return {
      'decision': decision.label,
      'accepted': decision.accepted,
      'jump_km': jumpKm,
      'score_delta': next.score - previous.score,
      'p_origin_spread_delta_s': previousSpread == null || nextSpread == null
          ? null
          : nextSpread - previousSpread,
      'p_origin_cluster_delta':
          next.pOriginClusterCount - previous.pOriginClusterCount,
      'support_delta':
          (next.phasePCount + next.phaseSCount) -
          (previous.phasePCount + previous.phaseSCount),
      'previous': previous.toJson(),
      'next': next.toJson(),
    };
  }

  SourceEstimate? _buildEstimate(DateTime observedAt) {
    final source = _sourceCache;
    final firstDetectionAt = _firstDetectionAt;
    if (source == null || firstDetectionAt == null) return null;
    final sGateOpen =
        observedAt.difference(firstDetectionAt).inMilliseconds / 1000.0 > 15.0;
    var pCount = 0;
    var sCount = 0;
    var otherCount = 0;
    var residualTotal = 0.0;
    var residualCount = 0;
    final rows = <Map<String, Object?>>[];

    for (final state in _stations.values) {
      if (state.tenPlus3DetectionId == null) continue;
      final pResidual = state.pResidualSeconds;
      final sResidual = state.sResidualSeconds;
      final useS = sGateOpen && state.tenPlus6SCloserThanP == true;
      final selectedResidual = useS ? sResidual : pResidual;
      final accepted =
          selectedResidual != null &&
          selectedResidual <= _residualToleranceSeconds;
      if (!accepted) {
        otherCount++;
      } else if (useS) {
        sCount++;
      } else {
        pCount++;
      }
      if (selectedResidual != null && selectedResidual.isFinite) {
        residualTotal += selectedResidual;
        residualCount++;
      }
      rows.add(
        state.toJson(
          firstDetectionAt: firstDetectionAt,
          sGateOpen: sGateOpen,
          selectedResidualSeconds: selectedResidual,
          accepted: accepted,
        ),
      );
    }

    rows.sort((left, right) {
      final leftResidual =
          (left['selected_residual_s'] as num?)?.toDouble() ?? double.infinity;
      final rightResidual =
          (right['selected_residual_s'] as num?)?.toDouble() ?? double.infinity;
      return leftResidual.compareTo(rightResidual);
    });
    final meanResidual = residualCount == 0
        ? null
        : residualTotal / residualCount;
    final confidence =
        (0.10 +
                math.min(0.24, (pCount + sCount) * 0.018) +
                (meanResidual == null ? 0.0 : 0.24 / (1.0 + meanResidual)))
            .clamp(0.0, 0.88);
    return SourceEstimate(
      latitude: source.latitude,
      longitude: source.longitude,
      depthKm: source.depthKm,
      originTime: source.originTime,
      confidence: confidence,
      method: SourceEstimationBenchmarkRunner.jqReferenceStateMachineMethod,
      supportingStationCount: pCount + sCount + otherCount,
      diagnostics: {
        'method': SourceEstimationBenchmarkRunner.jqReferenceStateMachineMethod,
        'model': 'jq_reference_state_machine_v5_depth_pair_origin_scoring',
        'status':
            'stateful_station_fields_with_owned_source_cache_depth_pair_origin_scoring',
        'diagnostic_only': true,
        'caveats': const [
          'ten_plus_3 detection membership is collapsed to one detection id in this first state-machine layer',
          'candidate search is owned by this state machine but still uses a compact diagnostic grid',
          'membership aging and multi-id split semantics are not complete',
        ],
        'bridge_source_cache_debug': _lastBridgeEstimate == null
            ? null
            : {
                'latitude': _lastBridgeEstimate!.latitude,
                'longitude': _lastBridgeEstimate!.longitude,
                'depth_km': _lastBridgeEstimate!.depthKm,
                'origin_time': _lastBridgeEstimate!.originTime
                    ?.toIso8601String(),
              },
        'first_detection_time': firstDetectionAt.toIso8601String(),
        'current_cloud_time_s': _secondsBetween(observedAt, firstDetectionAt),
        's_gate_threshold_s': 15.0,
        's_gate_open': sGateOpen,
        'source_cache_4_4': {
          'revision': _sourceRevision,
          'plus_2_longitude': source.longitude,
          'plus_3_latitude': source.latitude,
          'plus_4_depth_km': source.depthKm,
          'plus_5_origin_time_s': _secondsBetween(
            source.originTime,
            firstDetectionAt,
          ),
          'origin_time': source.originTime.toIso8601String(),
          'search_model': source.searchModel,
          'score': source.score,
          'phase_p_count': source.phasePCount,
          'phase_s_count': source.phaseSCount,
          'phase_other_count': source.phaseOtherCount,
          'phase_mean_residual_s': source.phaseMeanResidualSeconds,
          's_closer_count': source.sCloserCount,
          'p_origin_spread_s': source.pOriginSpreadSeconds,
          'p_origin_cluster_count': source.pOriginClusterCount,
          's_origin_spread_s': source.sOriginSpreadSeconds,
          's_origin_cluster_count': source.sOriginClusterCount,
          'phase_origin_mean_gap_s': source.phaseOriginMeanGapSeconds,
          'pair_mean_residual_s': source.pairMeanResidualSeconds,
          'pair_count': source.pairCount,
          'geometry_penalty': source.geometryPenalty,
        },
        'source_search': _lastSearch?.toJson(),
        'source_cache_update_decision': _lastSourceCacheDecision,
        'source_cache_update_trace': _lastSourceCacheDecisionTrace,
        'detection_id_4_3': {
          'id': 1,
          'first_detection_time_s': 0.0,
          'current_age_s': _secondsBetween(observedAt, firstDetectionAt),
          'station_state_count': _stations.length,
        },
        'station_state_counts': {
          'accepted_p_count': pCount,
          'accepted_s_count': sCount,
          'other_count': otherCount,
          'ten_plus_6_s_closer_than_p_count': _stations.values
              .where((state) => state.tenPlus6SCloserThanP == true)
              .length,
          'ten_plus_5_pretrigger_cache_count': _stations.values
              .where((state) => state.tenPlus5PretriggerCacheTime != null)
              .length,
          'recomputed_station_count': _stations.values
              .where((state) => state.lastRecomputedSourceRevision != null)
              .length,
        },
        'phase_p_count': pCount,
        'phase_s_count': sCount,
        'phase_other_count': otherCount,
        'phase_mean_residual_s': meanResidual,
        'station_row_limit': _stationRowLimit,
        'stations': rows.take(_stationRowLimit).toList(growable: false),
      },
    );
  }
}

class _JqSourceCache {
  final double latitude;
  final double longitude;
  final double depthKm;
  final DateTime originTime;
  final double score;
  final int phasePCount;
  final int phaseSCount;
  final int phaseOtherCount;
  final double? phaseMeanResidualSeconds;
  final String searchModel;
  final int? sCloserCount;
  final double? pOriginSpreadSeconds;
  final int pOriginClusterCount;
  final double? sOriginSpreadSeconds;
  final int sOriginClusterCount;
  final double? phaseOriginMeanGapSeconds;
  final double? pairMeanResidualSeconds;
  final int pairCount;
  final double geometryPenalty;

  const _JqSourceCache({
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.originTime,
    required this.score,
    required this.phasePCount,
    required this.phaseSCount,
    required this.phaseOtherCount,
    required this.phaseMeanResidualSeconds,
    required this.searchModel,
    this.sCloserCount,
    this.pOriginSpreadSeconds,
    this.pOriginClusterCount = 0,
    this.sOriginSpreadSeconds,
    this.sOriginClusterCount = 0,
    this.phaseOriginMeanGapSeconds,
    this.pairMeanResidualSeconds,
    this.pairCount = 0,
    this.geometryPenalty = 0.0,
  });

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'depth_km': depthKm,
    'origin_time': originTime.toIso8601String(),
    'score': score,
    'phase_p_count': phasePCount,
    'phase_s_count': phaseSCount,
    'phase_other_count': phaseOtherCount,
    'phase_mean_residual_s': phaseMeanResidualSeconds,
    'search_model': searchModel,
    's_closer_count': sCloserCount,
    'p_origin_spread_s': pOriginSpreadSeconds,
    'p_origin_cluster_count': pOriginClusterCount,
    's_origin_spread_s': sOriginSpreadSeconds,
    's_origin_cluster_count': sOriginClusterCount,
    'phase_origin_mean_gap_s': phaseOriginMeanGapSeconds,
    'pair_mean_residual_s': pairMeanResidualSeconds,
    'pair_count': pairCount,
    'geometry_penalty': geometryPenalty,
  };
}

class _JqSourceSearchResult {
  final _JqSourceCache cache;
  final double score;

  const _JqSourceSearchResult({required this.cache, required this.score});

  Map<String, Object?> toJson() => {
    'model': cache.searchModel,
    'score': score,
    'latitude': cache.latitude,
    'longitude': cache.longitude,
    'depth_km': cache.depthKm,
    'origin_time': cache.originTime.toIso8601String(),
    'phase_p_count': cache.phasePCount,
    'phase_s_count': cache.phaseSCount,
    'phase_other_count': cache.phaseOtherCount,
    'phase_mean_residual_s': cache.phaseMeanResidualSeconds,
    's_closer_count': cache.sCloserCount,
    'p_origin_spread_s': cache.pOriginSpreadSeconds,
    'p_origin_cluster_count': cache.pOriginClusterCount,
    's_origin_spread_s': cache.sOriginSpreadSeconds,
    's_origin_cluster_count': cache.sOriginClusterCount,
    'phase_origin_mean_gap_s': cache.phaseOriginMeanGapSeconds,
    'pair_mean_residual_s': cache.pairMeanResidualSeconds,
    'pair_count': cache.pairCount,
    'geometry_penalty': cache.geometryPenalty,
  };
}

class _JqGeometryContext {
  final double centroidLat;
  final double centroidLng;
  final double hintUnitLat;
  final double hintUnitLng;
  final double hintDistanceKm;
  final bool hasOffshoreHint;

  const _JqGeometryContext({
    required this.centroidLat,
    required this.centroidLng,
    required this.hintUnitLat,
    required this.hintUnitLng,
    required this.hintDistanceKm,
    required this.hasOffshoreHint,
  });
}

class _JqSourceCacheUpdateDecision {
  final bool accepted;
  final String label;

  const _JqSourceCacheUpdateDecision({
    required this.accepted,
    required this.label,
  });
}

class _JqSearchBounds {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final double marginDeg;

  const _JqSearchBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.marginDeg,
  });

  bool contains(double latitude, double longitude) =>
      latitude >= minLat &&
      latitude <= maxLat &&
      longitude >= minLng &&
      longitude <= maxLng;
}

class _JqCandidatePick {
  final double observedSeconds;
  final double pTravelSeconds;
  final double sTravelSeconds;
  final double pOriginOffsetSeconds;
  final double sOriginOffsetSeconds;

  const _JqCandidatePick({
    required this.observedSeconds,
    required this.pTravelSeconds,
    required this.sTravelSeconds,
    required this.pOriginOffsetSeconds,
    required this.sOriginOffsetSeconds,
  });
}

class _JqStationState {
  SeismicStationDescriptor descriptor;
  DateTime? tenPlus1ObservedTime;
  String? tenPlus1ObservedSource;
  DateTime? tenPlus2LastUpdateTime;
  int? tenPlus3DetectionId;
  double? tenPlus4DistanceKm;
  DateTime? tenPlus5PretriggerCacheTime;
  bool? tenPlus6SCloserThanP;
  double? tenPlus7PredictedPArrivalSeconds;
  double? tenPlus8PredictedSArrivalSeconds;
  double? pResidualSeconds;
  double? sResidualSeconds;
  double? previousSignal;
  int? previousDetectLevel;
  int? lastRecomputedSourceRevision;
  int recomputeCount = 0;

  _JqStationState({required this.descriptor});

  DateTime? get referenceLikeObservedTime =>
      tenPlus5PretriggerCacheTime ?? tenPlus1ObservedTime;

  Map<String, Object?> toJson({
    required DateTime firstDetectionAt,
    required bool sGateOpen,
    required double? selectedResidualSeconds,
    required bool accepted,
  }) {
    final observed = referenceLikeObservedTime;
    return {
      'station_id': descriptor.stationId,
      'code': descriptor.code,
      'network': descriptor.network,
      'latitude': descriptor.coordinate.latitude,
      'longitude': descriptor.coordinate.longitude,
      'sensor_role': descriptor.sensorRole.name,
      'ten_plus_1_observed_time_s': tenPlus1ObservedTime == null
          ? null
          : _secondsBetween(tenPlus1ObservedTime!, firstDetectionAt),
      'ten_plus_1_observed_time': tenPlus1ObservedTime?.toIso8601String(),
      'ten_plus_1_observed_source': tenPlus1ObservedSource,
      'reference_like_observed_time_s': observed == null
          ? null
          : _secondsBetween(observed, firstDetectionAt),
      'reference_like_observed_time_source': tenPlus5PretriggerCacheTime == null
          ? tenPlus1ObservedSource
          : 'ten_plus_5_pretrigger_cache_state',
      'ten_plus_2_last_update_time_s': tenPlus2LastUpdateTime == null
          ? null
          : _secondsBetween(tenPlus2LastUpdateTime!, firstDetectionAt),
      'ten_plus_3_detection_id': tenPlus3DetectionId,
      'ten_plus_4_distance_km': tenPlus4DistanceKm,
      'ten_plus_5_pretrigger_cache_s': tenPlus5PretriggerCacheTime == null
          ? null
          : _secondsBetween(tenPlus5PretriggerCacheTime!, firstDetectionAt),
      'ten_plus_6_s_closer_than_p': tenPlus6SCloserThanP,
      'ten_plus_7_predicted_p_arrival_s': tenPlus7PredictedPArrivalSeconds,
      'ten_plus_8_predicted_s_arrival_s': tenPlus8PredictedSArrivalSeconds,
      'p_residual_s': pResidualSeconds,
      's_residual_s': sResidualSeconds,
      's_gate_open': sGateOpen,
      'phase_after_gate': sGateOpen && tenPlus6SCloserThanP == true ? 'S' : 'P',
      'selected_residual_s': selectedResidualSeconds,
      'accepted_by_residual': accepted,
      'last_recomputed_source_revision': lastRecomputedSourceRevision,
      'recompute_count': recomputeCount,
    };
  }
}

double? _recordSignal(SeismicStationEventRecord record) {
  if (record.lastValue != null) return record.lastValue;
  if (record.lastDetectLevel != null) return record.lastDetectLevel!.toDouble();
  if (record.lastRawLevel != null) return record.lastRawLevel!.toDouble();
  return null;
}

Set<String> _sourceTriggerMemberIds(Map<String, Object?> metadata) {
  final raw = metadata['source_trigger_member_ids'];
  if (raw is! Iterable) return const {};
  return raw.whereType<String>().toSet();
}

bool _isStateMachineMember(
  SeismicStationEventRecord record,
  Set<String> memberIds,
) {
  if (memberIds.isNotEmpty) {
    return memberIds.contains(record.descriptor.stationId) ||
        memberIds.contains(record.descriptor.code);
  }
  return record.hasTriggered || record.isActiveLike;
}

_JqSearchBounds _searchBoundsForUsableStations(
  List<_JqStationState> usable,
  _JqGeometryContext geometry,
) {
  var minLat = double.infinity;
  var maxLat = -double.infinity;
  var minLng = double.infinity;
  var maxLng = -double.infinity;
  for (final state in usable) {
    final coordinate = state.descriptor.coordinate;
    minLat = math.min(minLat, coordinate.latitude);
    maxLat = math.max(maxLat, coordinate.latitude);
    minLng = math.min(minLng, coordinate.longitude);
    maxLng = math.max(maxLng, coordinate.longitude);
  }
  if (!minLat.isFinite ||
      !maxLat.isFinite ||
      !minLng.isFinite ||
      !maxLng.isFinite) {
    return const _JqSearchBounds(
      minLat: 20.0,
      maxLat: 50.0,
      minLng: 120.0,
      maxLng: 155.0,
      marginDeg: 30.0,
    );
  }
  final span = math.max(maxLat - minLat, maxLng - minLng);
  final margin = (span * 0.8 + 0.45).clamp(0.45, 1.15).toDouble();
  final hintLatExtension = geometry.hasOffshoreHint
      ? geometry.hintUnitLat * 0.45
      : 0.0;
  final hintLngExtension = geometry.hasOffshoreHint
      ? geometry.hintUnitLng * 0.45
      : 0.0;
  return _JqSearchBounds(
    minLat: math.max(20.0, minLat - margin + math.min(0.0, hintLatExtension)),
    maxLat: math.min(50.0, maxLat + margin + math.max(0.0, hintLatExtension)),
    minLng: math.max(120.0, minLng - margin + math.min(0.0, hintLngExtension)),
    maxLng: math.min(155.0, maxLng + margin + math.max(0.0, hintLngExtension)),
    marginDeg: margin,
  );
}

_JqGeometryContext _geometryContextForUsableStations(
  List<_JqStationState> usable, {
  required SourceEstimate? bridgeEstimate,
}) {
  final centroidLat = _mean([
    for (final state in usable) state.descriptor.coordinate.latitude,
  ]);
  final centroidLng = _mean([
    for (final state in usable) state.descriptor.coordinate.longitude,
  ]);
  if (bridgeEstimate == null) {
    return _JqGeometryContext(
      centroidLat: centroidLat,
      centroidLng: centroidLng,
      hintUnitLat: 0.0,
      hintUnitLng: 0.0,
      hintDistanceKm: 0.0,
      hasOffshoreHint: false,
    );
  }
  final dLatKm = (bridgeEstimate.latitude - centroidLat) * 111.0;
  final dLngKm =
      (bridgeEstimate.longitude - centroidLng) *
      111.0 *
      math.cos(centroidLat * math.pi / 180.0);
  final distanceKm = math.sqrt(dLatKm * dLatKm + dLngKm * dLngKm);
  if (distanceKm < 25.0 || !distanceKm.isFinite) {
    return _JqGeometryContext(
      centroidLat: centroidLat,
      centroidLng: centroidLng,
      hintUnitLat: 0.0,
      hintUnitLng: 0.0,
      hintDistanceKm: distanceKm.isFinite ? distanceKm : 0.0,
      hasOffshoreHint: false,
    );
  }
  return _JqGeometryContext(
    centroidLat: centroidLat,
    centroidLng: centroidLng,
    hintUnitLat: dLatKm / distanceKm,
    hintUnitLng: dLngKm / distanceKm,
    hintDistanceKm: distanceKm,
    hasOffshoreHint: true,
  );
}

double _oneSidedGeometryPenalty({
  required double latitude,
  required double longitude,
  required _JqGeometryContext geometry,
}) {
  if (!geometry.hasOffshoreHint) return 0.0;
  final dLatKm = (latitude - geometry.centroidLat) * 111.0;
  final dLngKm =
      (longitude - geometry.centroidLng) *
      111.0 *
      math.cos(geometry.centroidLat * math.pi / 180.0);
  final projectionKm =
      dLatKm * geometry.hintUnitLat + dLngKm * geometry.hintUnitLng;
  final behindPenalty = math.max(0.0, -projectionKm) * 0.12;
  final collapsePenalty =
      math.max(0.0, geometry.hintDistanceKm * 0.95 - projectionKm) * 0.18;
  return math.min(30.0, behindPenalty + collapsePenalty);
}

({double score, double meanResidualSeconds, int count}) _jqPairResidual(
  List<double> observedSeconds,
  List<double> predictedSeconds, {
  required int maxPairs,
}) {
  if (observedSeconds.length < 2 || predictedSeconds.length < 2) {
    return (score: 0.0, meanResidualSeconds: 0.0, count: 0);
  }
  final length = math.min(observedSeconds.length, predictedSeconds.length);
  var score = 0.0;
  var sum = 0.0;
  var count = 0;
  for (var left = 0; left < length; left++) {
    for (var right = left + 1; right < length; right++) {
      final observedDelta = observedSeconds[left] - observedSeconds[right];
      final predictedDelta = predictedSeconds[left] - predictedSeconds[right];
      final residual = (observedDelta - predictedDelta).abs();
      final capped = math.min(6.0, residual);
      score += capped * capped;
      sum += residual;
      count += 1;
      if (count >= maxPairs) {
        return (
          score: score / count * length,
          meanResidualSeconds: sum / count,
          count: count,
        );
      }
    }
  }
  return (
    score: count == 0 ? 0.0 : score / count * length,
    meanResidualSeconds: count == 0 ? 0.0 : sum / count,
    count: count,
  );
}

double _mean(List<double> values) {
  if (values.isEmpty) return 0.0;
  var total = 0.0;
  for (final value in values) {
    total += value;
  }
  return total / values.length;
}

double _median(List<double> values) {
  if (values.isEmpty) return 0.0;
  final sorted = values.toList(growable: false)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

double _secondsBetween(DateTime value, DateTime origin) =>
    value.difference(origin).inMilliseconds / 1000.0;

SourceEstimationMethodFrame _methodFrame({
  required String methodId,
  required SourceEstimate? estimate,
  required LatLng? truth,
  required Map<String, LatLng> previousPoints,
  required int runtimeMicros,
  Map<String, Object?>? eventMetadata,
}) {
  if (estimate == null) {
    return SourceEstimationMethodFrame(
      estimate: null,
      errorKm: null,
      jumpKm: null,
      runtimeMicros: runtimeMicros,
      eventMetadata: eventMetadata == null
          ? const {}
          : Map<String, Object?>.unmodifiable(eventMetadata),
    );
  }
  final point = LatLng(estimate.latitude, estimate.longitude);
  final previous = previousPoints[methodId];
  previousPoints[methodId] = point;
  return SourceEstimationMethodFrame(
    estimate: estimate,
    errorKm: truth == null ? null : _distanceKm(point, truth),
    jumpKm: previous == null ? null : _distanceKm(previous, point),
    runtimeMicros: runtimeMicros,
    eventMetadata: eventMetadata == null
        ? const {}
        : Map<String, Object?>.unmodifiable(eventMetadata),
  );
}

SourceEstimationMethodSummary _summarize(
  String methodId,
  List<SourceEstimationFrameReport> frames,
  SourceEstimationReplayCaseType caseType,
  DateTime? originTimeJst,
) {
  final estimates = <(DateTime, SourceEstimationMethodFrame)>[];
  final runtimes = <double>[];
  for (final frame in frames) {
    final method = frame.methods[methodId];
    if (method == null) continue;
    runtimes.add(method.runtimeMicros.toDouble());
    if (method.estimate != null) {
      estimates.add((frame.observedAtJst, method));
    }
  }
  final errors = estimates
      .map((entry) => entry.$2.errorKm)
      .whereType<double>()
      .toList(growable: false);
  final jumps = estimates
      .map((entry) => entry.$2.jumpKm)
      .whereType<double>()
      .toList(growable: false);
  final firstAt = estimates.isEmpty ? null : estimates.first.$1;
  return SourceEstimationMethodSummary(
    methodId: methodId,
    estimateCount: estimates.length,
    firstEstimateAtJst: firstAt,
    firstEstimateDelaySeconds: firstAt == null || originTimeJst == null
        ? null
        : firstAt.difference(originTimeJst).inMilliseconds / 1000.0,
    medianErrorKm: _percentile(errors, 0.5),
    p90ErrorKm: _percentile(errors, 0.9),
    errorAtSeconds: {
      for (final seconds in [5, 10, 20])
        '$seconds': _errorAt(
          estimates,
          originTimeJst?.add(Duration(seconds: seconds)),
        ),
    },
    medianJumpKm: _percentile(jumps, 0.5),
    p90JumpKm: _percentile(jumps, 0.9),
    p95RuntimeMicros: _percentile(runtimes, 0.95) ?? 0,
    falseEstimateFrameCount: caseType == SourceEstimationReplayCaseType.noise
        ? estimates.length
        : 0,
  );
}

double? _errorAt(
  List<(DateTime, SourceEstimationMethodFrame)> estimates,
  DateTime? target,
) {
  if (target == null) return null;
  for (final entry in estimates) {
    if (entry.$1 == target) return entry.$2.errorKm;
  }
  return null;
}

SourceEstimationBatchDetectionSummary _summarizeBatchDetection(
  List<SourceEstimationBenchmarkReport> reports,
) {
  final allEventReports = reports
      .where(
        (report) =>
            report.replayCase.caseType == SourceEstimationReplayCaseType.event,
      )
      .toList(growable: false);
  final eventReports = allEventReports
      .where(
        (report) => report.replayCase.eventLabels.includeInDetectionMetrics,
      )
      .toList(growable: false);
  final noiseReports = reports
      .where(
        (report) =>
            report.replayCase.caseType == SourceEstimationReplayCaseType.noise,
      )
      .toList(growable: false);
  final detectorId = reports.isEmpty
      ? 'unknown'
      : reports.first.detectionSummary.detectorId;

  final candidateDelays = eventReports
      .map((report) => report.detectionSummary.firstCandidateDelaySeconds)
      .whereType<double>()
      .toList(growable: false);
  final confirmationDelays = eventReports
      .map((report) => report.detectionSummary.firstConfirmedDelaySeconds)
      .whereType<double>()
      .toList(growable: false);

  final noiseFrameCount = noiseReports.fold<int>(
    0,
    (sum, report) => sum + report.detectionSummary.decodedFrameCount,
  );
  final noiseCandidateFrameCount = noiseReports.fold<int>(
    0,
    (sum, report) => sum + report.detectionSummary.falseCandidateFrameCount,
  );
  final noiseConfirmedFrameCount = noiseReports.fold<int>(
    0,
    (sum, report) => sum + report.detectionSummary.falseConfirmedFrameCount,
  );

  final eventCasesWithCandidate = eventReports
      .where((report) => report.detectionSummary.hasCandidate)
      .length;
  final eventCasesConfirmed = eventReports
      .where((report) => report.detectionSummary.hasConfirmed)
      .length;

  return SourceEstimationBatchDetectionSummary(
    detectorId: detectorId,
    catalogEventCaseCount: allEventReports
        .where((report) => report.replayCase.eventLabels.catalogEvent)
        .length,
    excludedEventCaseCount: allEventReports.length - eventReports.length,
    eventCaseCount: eventReports.length,
    eventCasesWithCandidate: eventCasesWithCandidate,
    eventCasesConfirmed: eventCasesConfirmed,
    detectionMissedCandidateCount:
        eventReports.length - eventCasesWithCandidate,
    detectionMissedEventCount: eventReports.length - eventCasesConfirmed,
    noiseCaseCount: noiseReports.length,
    noiseFrameCount: noiseFrameCount,
    noiseCandidateFrameCount: noiseCandidateFrameCount,
    noiseConfirmedFrameCount: noiseConfirmedFrameCount,
    falseCandidateFrameRate: noiseFrameCount == 0
        ? 0
        : noiseCandidateFrameCount / noiseFrameCount,
    falseConfirmedFrameRate: noiseFrameCount == 0
        ? 0
        : noiseConfirmedFrameCount / noiseFrameCount,
    medianCandidateDelaySeconds: _percentile(candidateDelays, 0.5),
    medianConfirmationDelaySeconds: _percentile(confirmationDelays, 0.5),
  );
}

SourceEstimationBatchDetectionSummary _summarizeEventDetectionBatch(
  List<EventDetectionBenchmarkReport> reports, {
  bool shadow = false,
  bool temporalBridge = false,
}) {
  assert(!(shadow && temporalBridge));
  SourceEstimationDetectionCaseSummary summaryOf(
    EventDetectionBenchmarkReport report,
  ) {
    if (temporalBridge) return report.temporalBridgeDetectionSummary;
    if (shadow) return report.shadowDetectionSummary;
    return report.detectionSummary;
  }

  final allEventReports = reports
      .where(
        (report) =>
            report.replayCase.caseType == SourceEstimationReplayCaseType.event,
      )
      .toList(growable: false);
  final eventReports = allEventReports
      .where(
        (report) => report.replayCase.eventLabels.includeInDetectionMetrics,
      )
      .toList(growable: false);
  final noiseReports = reports
      .where(
        (report) =>
            report.replayCase.caseType == SourceEstimationReplayCaseType.noise,
      )
      .toList(growable: false);
  final detectorId = reports.isEmpty
      ? 'unknown'
      : summaryOf(reports.first).detectorId;

  final candidateDelays = eventReports
      .map((report) => summaryOf(report).firstCandidateDelaySeconds)
      .whereType<double>()
      .toList(growable: false);
  final confirmationDelays = eventReports
      .map((report) => summaryOf(report).firstConfirmedDelaySeconds)
      .whereType<double>()
      .toList(growable: false);

  final noiseFrameCount = noiseReports.fold<int>(
    0,
    (sum, report) => sum + summaryOf(report).decodedFrameCount,
  );
  final noiseCandidateFrameCount = noiseReports.fold<int>(
    0,
    (sum, report) => sum + summaryOf(report).falseCandidateFrameCount,
  );
  final noiseConfirmedFrameCount = noiseReports.fold<int>(
    0,
    (sum, report) => sum + summaryOf(report).falseConfirmedFrameCount,
  );
  final eventCasesWithCandidate = eventReports
      .where((report) => summaryOf(report).hasCandidate)
      .length;
  final eventCasesConfirmed = eventReports
      .where((report) => summaryOf(report).hasConfirmed)
      .length;

  return SourceEstimationBatchDetectionSummary(
    detectorId: detectorId,
    catalogEventCaseCount: allEventReports
        .where((report) => report.replayCase.eventLabels.catalogEvent)
        .length,
    excludedEventCaseCount: allEventReports.length - eventReports.length,
    eventCaseCount: eventReports.length,
    eventCasesWithCandidate: eventCasesWithCandidate,
    eventCasesConfirmed: eventCasesConfirmed,
    detectionMissedCandidateCount:
        eventReports.length - eventCasesWithCandidate,
    detectionMissedEventCount: eventReports.length - eventCasesConfirmed,
    noiseCaseCount: noiseReports.length,
    noiseFrameCount: noiseFrameCount,
    noiseCandidateFrameCount: noiseCandidateFrameCount,
    noiseConfirmedFrameCount: noiseConfirmedFrameCount,
    falseCandidateFrameRate: noiseFrameCount == 0
        ? 0
        : noiseCandidateFrameCount / noiseFrameCount,
    falseConfirmedFrameRate: noiseFrameCount == 0
        ? 0
        : noiseConfirmedFrameCount / noiseFrameCount,
    medianCandidateDelaySeconds: _percentile(candidateDelays, 0.5),
    medianConfirmationDelaySeconds: _percentile(confirmationDelays, 0.5),
  );
}

SourceEstimationBatchMethodSummary _summarizeBatch(
  String methodId,
  List<SourceEstimationBenchmarkReport> reports,
) {
  final eventReports = reports
      .where(
        (report) =>
            report.replayCase.caseType == SourceEstimationReplayCaseType.event,
      )
      .toList(growable: false);
  final confirmedEventReports = eventReports
      .where((report) => report.detectionSummary.hasConfirmed)
      .toList(growable: false);
  final noiseReports = reports
      .where(
        (report) =>
            report.replayCase.caseType == SourceEstimationReplayCaseType.noise,
      )
      .toList(growable: false);
  final eventErrors = <double>[];
  var eventEstimateFrames = 0;
  var eventCasesWithEstimates = 0;
  for (final report in eventReports) {
    var caseHasEstimate = false;
    for (final frame in report.frames) {
      final method = frame.methods[methodId];
      if (method?.estimate == null) continue;
      eventEstimateFrames++;
      caseHasEstimate = true;
      if (method!.errorKm != null) eventErrors.add(method.errorKm!);
    }
    if (caseHasEstimate) eventCasesWithEstimates++;
  }

  var confirmedEventCasesWithEstimates = 0;
  for (final report in confirmedEventReports) {
    final caseHasEstimate = report.frames.any(
      (frame) => frame.methods[methodId]?.estimate != null,
    );
    if (caseHasEstimate) confirmedEventCasesWithEstimates++;
  }

  var noiseEstimateFrames = 0;
  var noiseFrames = 0;
  var noiseCasesWithEstimates = 0;
  for (final report in noiseReports) {
    var caseHasEstimate = false;
    for (final frame in report.frames.where((frame) => frame.decoded)) {
      noiseFrames++;
      if (frame.methods[methodId]?.estimate != null) {
        noiseEstimateFrames++;
        caseHasEstimate = true;
      }
    }
    if (caseHasEstimate) noiseCasesWithEstimates++;
  }

  return SourceEstimationBatchMethodSummary(
    methodId: methodId,
    eventCaseCount: eventReports.length,
    eventCasesWithEstimates: eventCasesWithEstimates,
    missedEventCaseCount: eventReports.length - eventCasesWithEstimates,
    confirmedEventCaseCount: confirmedEventReports.length,
    confirmedEventCasesWithEstimates: confirmedEventCasesWithEstimates,
    sourceMissedConfirmedEventCount:
        confirmedEventReports.length - confirmedEventCasesWithEstimates,
    noiseCaseCount: noiseReports.length,
    eventEstimateFrameCount: eventEstimateFrames,
    noiseEstimateFrameCount: noiseEstimateFrames,
    noiseFrameCount: noiseFrames,
    noiseCasesWithEstimates: noiseCasesWithEstimates,
    medianEventErrorKm: _percentile(eventErrors, 0.5),
    p90EventErrorKm: _percentile(eventErrors, 0.9),
    falseEstimateFrameRate: noiseFrames == 0
        ? 0
        : noiseEstimateFrames / noiseFrames,
  );
}

double? _percentile(List<double> values, double percentile) {
  return ReplayMetricCalculator.percentile(values, percentile);
}

double _distanceKm(LatLng a, LatLng b) {
  const distance = Distance();
  return distance.as(LengthUnit.Kilometer, a, b);
}

String _formatKilometers(double? value) {
  if (value == null) return '-';
  final formatted = value.toStringAsFixed(1);
  final number = formatted.endsWith('.0')
      ? formatted.substring(0, formatted.length - 2)
      : formatted;
  return '$number km';
}

String _formatSeconds(double? value) {
  if (value == null) return '-';
  return '${_formatNumber(value)}s';
}

String _formatKm(double value) => '${_formatNumber(value)}km';

String _formatNumber(double value) {
  final formatted = value.toStringAsFixed(1);
  return formatted.endsWith('.0')
      ? formatted.substring(0, formatted.length - 2)
      : formatted;
}

String _markdownCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll(RegExp(r'[\r\n]+'), ' ');
}

DateTime _parseJstWallClock(String value) {
  final parsed = DateTime.parse(value);
  return DateTime(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}
