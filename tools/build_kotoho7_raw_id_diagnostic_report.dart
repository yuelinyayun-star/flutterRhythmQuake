import 'dart:convert';
import 'dart:io';

const _defaultInputDirectory = '.dart_tool/source_estimation_benchmark';
const _defaultOutputPath = '.dart_tool/kotoho7_raw_id_diagnostic/report.json';
const _rawMethod = 'nied_gif_hyp_kotoho7_reference_raw_id_diagnostic_v1';
const _effectiveMethod = 'nied_gif_hyp_kotoho7_reference_replay_v1';

void main(List<String> args) {
  final inputDirectory = Directory(
    _argument(args, '--input') ?? _defaultInputDirectory,
  );
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final outputFile = File(outputPath);
  final cases = <Map<String, Object?>>[];

  if (inputDirectory.existsSync()) {
    final files =
        inputDirectory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
      if (decoded is! Map<String, Object?>) continue;
      final summary = _summarizeCase(file, decoded);
      if (summary != null) cases.add(summary);
    }
  }

  final report = <String, Object?>{
    'schemaVersion': 'kotoho7_raw_id_diagnostic_report_v1',
    'inputDirectory': inputDirectory.path,
    'caseCount': cases.length,
    'casesWithRawMultiId': cases
        .where((entry) => (entry['rawEventIdCount'] as int) > 1)
        .length,
    'casesWithRawSelection': cases
        .where((entry) => (entry['rawExistingSelectionFrameCount'] as int) > 0)
        .length,
    'casesWithRawMerge': cases
        .where((entry) => (entry['rawMergeFrameCount'] as int) > 0)
        .length,
    'cases': cases,
  };

  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    encoding: utf8,
  );
  stdout.writeln('Wrote ${outputFile.path}');
}

Map<String, Object?>? _summarizeCase(File file, Map<String, Object?> json) {
  final frames = json['frames'];
  if (frames is! List) return null;
  final caseJson = _map(json['case']);
  final caseId =
      _string(caseJson['caseId']) ??
      file.uri.pathSegments.last.replaceAll('.reference.json', '');

  final rawIds = <String, int>{};
  final effectiveIds = <String, int>{};
  var heldReplacementFrames = 0;
  final rawModels = <String, int>{};
  final effectiveModels = <String, int>{};
  final rawSelectionFrames = <Map<String, Object?>>[];
  final rawMergeFrames = <Map<String, Object?>>[];
  var rawEstimateCount = 0;
  var effectiveEstimateCount = 0;
  Map<String, Object?>? rawLastEstimate;
  Map<String, Object?>? effectiveLastEstimate;

  for (final rawFrame in frames) {
    final frame = _map(rawFrame);
    final observedAt = _string(frame['observedAtJst']);
    final metadata = _map(frame['sourceTriggerMetadata']);
    final rawId = _string(metadata['source_trigger_continuity_raw_event_id']);
    final effectiveId = _string(
      metadata['source_trigger_continuity_effective_event_id'],
    );
    if (rawId != null) rawIds[rawId] = (rawIds[rawId] ?? 0) + 1;
    if (effectiveId != null) {
      effectiveIds[effectiveId] = (effectiveIds[effectiveId] ?? 0) + 1;
    }
    if (metadata['source_trigger_continuity_held_replacement'] == true) {
      heldReplacementFrames += 1;
    }

    final methods = _map(frame['methods']);
    final rawMethod = _map(methods[_rawMethod]);
    final rawEstimate = _map(rawMethod['estimate']);
    if (rawEstimate.isNotEmpty) {
      rawEstimateCount += 1;
      rawLastEstimate = _estimateSummary(observedAt, rawMethod, rawEstimate);
      final cache = _statefulCache(rawEstimate);
      final model = _string(cache['source_selection_model']) ?? 'unknown';
      rawModels[model] = (rawModels[model] ?? 0) + 1;
      final mergeCount = _int(cache['same_source_merge_count']);
      if (model.contains('existing_source_cache')) {
        rawSelectionFrames.add(_frameSelectionSummary(observedAt, rawMethod));
      }
      if (mergeCount > 0) {
        rawMergeFrames.add(_frameSelectionSummary(observedAt, rawMethod));
      }
    }

    final effectiveMethod = _map(methods[_effectiveMethod]);
    final effectiveEstimate = _map(effectiveMethod['estimate']);
    if (effectiveEstimate.isNotEmpty) {
      effectiveEstimateCount += 1;
      effectiveLastEstimate = _estimateSummary(
        observedAt,
        effectiveMethod,
        effectiveEstimate,
      );
      final cache = _statefulCache(effectiveEstimate);
      final model = _string(cache['source_selection_model']) ?? 'unknown';
      effectiveModels[model] = (effectiveModels[model] ?? 0) + 1;
    }
  }

  return {
    'caseId': caseId,
    'path': file.path,
    'rawEventIdCount': rawIds.length,
    'rawEventIds': rawIds,
    'effectiveEventIdCount': effectiveIds.length,
    'effectiveEventIds': effectiveIds,
    'heldReplacementFrames': heldReplacementFrames,
    'rawEstimateCount': rawEstimateCount,
    'effectiveEstimateCount': effectiveEstimateCount,
    'rawSelectionModels': rawModels,
    'effectiveSelectionModels': effectiveModels,
    'rawExistingSelectionFrameCount': rawSelectionFrames.length,
    'rawMergeFrameCount': rawMergeFrames.length,
    'rawSelectionFrames': rawSelectionFrames,
    'rawMergeFrames': rawMergeFrames,
    'rawLastEstimate': rawLastEstimate,
    'effectiveLastEstimate': effectiveLastEstimate,
  };
}

Map<String, Object?> _frameSelectionSummary(
  String? observedAt,
  Map<String, Object?> method,
) {
  final estimate = _map(method['estimate']);
  final cache = _statefulCache(estimate);
  return {
    'observedAtJst': observedAt,
    'errorKm': method['errorKm'],
    'sourceSelectionModel': cache['source_selection_model'],
    'sourceSelectionSelectedKey': cache['source_selection_selected_key'],
    'sameSourceMergeCount': cache['same_source_merge_count'],
    'sameSourceMergeKeys': cache['same_source_merge_keys'],
    'sourceKeys': cache['source_keys'],
    'assignedStationCount': cache['assigned_station_count'],
  };
}

Map<String, Object?> _estimateSummary(
  String? observedAt,
  Map<String, Object?> method,
  Map<String, Object?> estimate,
) {
  final cache = _statefulCache(estimate);
  final scratch43 = _map(cache['scratch_4_3_proxy']);
  return {
    'observedAtJst': observedAt,
    'errorKm': method['errorKm'],
    'latitude': estimate['latitude'],
    'longitude': estimate['longitude'],
    'depthKm': estimate['depthKm'],
    'supportingStationCount': estimate['supportingStationCount'],
    'sourceSelectionModel': cache['source_selection_model'],
    'sameSourceMergeCount': cache['same_source_merge_count'],
    'sourceKeys': cache['source_keys'],
    'assignedStationCount': cache['assigned_station_count'],
    'scratch43': scratch43,
  };
}

Map<String, Object?> _statefulCache(Map<String, Object?> estimate) {
  final diagnostics = _map(estimate['diagnostics']);
  return _map(diagnostics['stateful_source_cache']);
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
