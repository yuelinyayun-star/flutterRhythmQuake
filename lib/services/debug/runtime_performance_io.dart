import 'dart:io';
import '../../providers/quake_provider.dart';
import '../native_unified_event_owner.dart';
import '../native_camera_focus.dart';
import '../sources/native_station_image_decoder.dart';
import '../sources/nied_realtime_pipeline.dart';
import '../../core/source_estimation/native_hyp_scorer.dart';
import '../../core/source_estimation/native_observation_history.dart';
import '../../core/source_estimation/native_station_record_owner.dart';

/// Explicit diagnostic request only. No sampling timer or source data exports.
Map<String, dynamic> collectRuntimePerformance() => {
  'schemaVersion': 1,
  'pid': pid,
  'sampledAtUtc': DateTime.now().toUtc().toIso8601String(),
  'processRssBytes': ProcessInfo.currentRss,
  'processPeakRssBytes': ProcessInfo.maxRss,
  'native': NativeStationImageDecoder.supported
      ? {
          ...NativeStationImageDecoder.memoryStats,
          'hypScorerSessions': NativeHypScorer.sessions,
          'observationHistory': NativeObservationHistory.diagnostics,
          'stationRecord': NativeStationRecordOwner.diagnostics,
          'unified': NativeUnifiedEventOwner.diagnostics,
          'cameraFocus': {
            'calls': NativeCameraFocus.calls,
            'outstandingOutputs': NativeCameraFocus.outputs,
          },
        }
      : {'supported': false},
  'unifiedOwners': NativeUnifiedEventOwner.supported
      ? NativeUnifiedEventOwner.runtimeDiagnostics
      : [],
  'nied': NiedRealtimePipeline.active?.diagnostics,
  'eventHistory': QuakeProvider.runtimePerformanceSnapshot,
};
