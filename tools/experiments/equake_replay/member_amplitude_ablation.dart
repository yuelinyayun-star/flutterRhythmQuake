import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as images;
import 'package:path/path.dart' as path;
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_value_decoder.dart';

import '../../../test/support/nied_station_paired_candidate.dart';

String hash(List<int> bytes) => sha256.convert(bytes).toString();
String stamp(DateTime t) =>
    t.toIso8601String().substring(0, 19).replaceAll(RegExp('[-:T]'), '');

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('Pass shadow report and new output');
  }
  final input = File(args[0]);
  final inputBytes = input.readAsBytesSync();
  final report = jsonDecode(utf8.decode(inputBytes)) as Map;
  final output = File(args[1]);
  if (output.existsSync()) throw StateError('Output already exists');
  if (!output.parent.existsSync() || path.extension(output.path) != '.json') {
    throw StateError('Use a new JSON file in an existing .dart_tool directory');
  }
  final outputParent = output.parent.resolveSymbolicLinksSync();
  final experimentRoot = Directory('.dart_tool').resolveSymbolicLinksSync();
  if (!path.equals(experimentRoot, outputParent) &&
      !path.isWithin(experimentRoot, outputParent)) {
    throw StateError('Output must stay inside .dart_tool');
  }
  final sourceHashes = {
    for (final path in [
      'lib/models/nied_scan_positions.dart',
      'lib/models/nied_station_db.dart',
      'lib/core/source_estimation/source_estimator.dart',
      'lib/core/source_estimation/srev_kaizou_magnitude.dart',
    ])
      path: hash(File(path).readAsBytesSync()),
  };
  if (sourceHashes['lib/models/nied_scan_positions.dart'] !=
      report['scanPositionsSha256']) {
    throw StateError('Scan mapping differs from replay');
  }
  if (sourceHashes['lib/core/source_estimation/source_estimator.dart'] !=
      report['solverSha256']) {
    throw StateError('Solver differs from replay');
  }
  final results = <Map<String, Object?>>[];
  for (final replay in (report['cases'] as List).cast<Map>()) {
    final fixtureFile = File(
      'test/fixtures/source_estimation/${replay['label']}.json',
    );
    final fixtureBytes = fixtureFile.readAsBytesSync();
    final fixture = jsonDecode(utf8.decode(fixtureBytes)) as Map;
    if (fixture['caseId'] != replay['id']) throw StateError('Fixture mismatch');
    final capture = fixture['captureDirectory'] as String;
    final captureRoot = Directory(capture).resolveSymbolicLinksSync();
    if (path.equals(captureRoot, outputParent) ||
        path.isWithin(captureRoot, outputParent)) {
      throw StateError('Output must not be written inside raw captures');
    }
    final start = DateTime.parse(fixture['startTimeJst'] as String);
    final end = DateTime.parse(fixture['endTimeJst'] as String);
    final frames = <Map<String, Object?>>[];
    final originals = <String, String>{};
    final rawDigest = StringBuffer();
    final frameMap = {
      for (final f in (replay['frames'] as List).cast<Map>())
        f['observedAtJst'] as String: f,
    };
    if (frameMap.length != (replay['frames'] as List).length) {
      throw StateError('Duplicate replay frame');
    }
    String? previousKey;
    final extraPeaks = <String, double>{};
    var missing = 0;
    var checkedActiveValues = 0;
    for (
      var t = start;
      !t.isAfter(end);
      t = t.add(const Duration(seconds: 1))
    ) {
      final name = '${stamp(t)}.jma_s.gif';
      final file = File('$capture/$name');
      final time = t.toIso8601String();
      if (!file.existsSync()) {
        rawDigest.writeln('$name:MISSING');
        missing++;
        extraPeaks.clear();
        previousKey = null;
        if (frameMap.containsKey(time)) {
          throw StateError('Missing replay input');
        }
        continue;
      }
      final bytes = file.readAsBytesSync();
      final digest = hash(bytes);
      originals[file.path] = digest;
      rawDigest.writeln('$name:$digest');
      final frame = frameMap[time];
      if (frame == null) throw StateError('Unmatched raw frame: $time');
      final estimate = frame['estimate'] as Map?;
      final audit = frame['magnitudeAudit'] as Map?;
      final experiment = audit?['experiment'] as Map?;
      final baseline = experiment?['eventPeakCandidate'] as Map?;
      if (estimate == null || baseline?['supported'] != true) {
        extraPeaks.clear();
        previousKey = null;
        frames.add({
          'time': time,
          'supported': false,
          'reason': 'no_live_candidate',
        });
        continue;
      }
      final key = baseline!['eventKey'] as String;
      final multiple = baseline['multipleSources'] == true;
      if (key != previousKey || multiple) extraPeaks.clear();
      previousKey = key;
      final peaks = (baseline['stationPeaks'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      );
      extraPeaks.removeWhere((code, _) => !peaks.containsKey(code));
      final associated = (experiment!['associatedCodes'] as List)
          .cast<String>()
          .toSet();
      final active = {
        for (final s
            in ((audit!['stationTrace'] as Map)['stations'] as List)
                .cast<Map>())
          s['code'] as String: s['rawIntensity'],
      };
      final observed = <String, double>{};
      final skipped = <String, String>{};
      if (!multiple) {
        final decoded = images.decodeGif(bytes);
        if (decoded == null) throw StateError('Cannot decode original GIF');
        for (final code in peaks.keys) {
          final pixelPosition = NiedScanPositions.positions[code];
          if (pixelPosition == null) {
            skipped[code] = 'missing_scan_position';
            continue;
          }
          final x = pixelPosition[0], y = pixelPosition[1];
          if (x < 0 || y < 0 || x >= decoded.width || y >= decoded.height) {
            throw StateError('Pixel out of bounds: $code');
          }
          final pixel = decoded.getPixel(x, y);
          final value = NiedGifValueDecoder.decodeObservationFromRgba(
            pixel.r.toInt(),
            pixel.g.toInt(),
            pixel.b.toInt(),
          )?.shindo;
          if (value == null) {
            skipped[code] = 'unavailable_pixel';
            continue;
          }
          if (active[code] is num) {
            if ((value - (active[code] as num)).abs() > 1e-10) {
              throw StateError('Worker/raw mismatch: $code $time');
            }
            checkedActiveValues++;
          }
          // Only formerly associated, currently inactive members are added.
          if (associated.contains(code)) continue;
          if (active.containsKey(code)) {
            skipped[code] = 'active_but_not_currently_associated';
            continue;
          }
          observed[code] = value;
          if (value > (extraPeaks[code] ?? double.negativeInfinity)) {
            extraPeaks[code] = value;
          }
        }
      }
      final combined = Map<String, double>.of(peaks);
      for (final entry in extraPeaks.entries) {
        if (entry.value > combined[entry.key]!) {
          combined[entry.key] = entry.value;
        }
      }
      final maximum = combined.values.reduce((a, b) => a > b ? a : b);
      final strongest =
          combined.keys.where((code) => combined[code] == maximum).toList()
            ..sort();
      final paired = calculateNiedStationPairedCandidate(
        latitude: (estimate['latitude'] as num).toDouble(),
        longitude: (estimate['longitude'] as num).toDouble(),
        intensity: maximum,
        strongestCodes: strongest,
        multipleSources: multiple,
      );
      final baselinePaired = baseline['stationPairedCandidate'] as Map;
      frames.add({
        'time': time,
        'supported': true,
        'eventKey': key,
        'collectionEnabled': !multiple,
        'disabledReason': multiple ? 'multiple_sources' : null,
        'baselineMagnitude': baselinePaired['magnitude'],
        'baselinePeak': baseline['peakIntensity'],
        'observedInactiveMembers': observed,
        'skippedMembers': skipped,
        'extraPeaks': Map<String, double>.of(extraPeaks),
        'combinedPeaks': combined,
        'peakIntensity': maximum,
        'strongestCodes': strongest,
        'paired': paired,
      });
    }
    if (hash(utf8.encode(rawDigest.toString())) != replay['rawInputSha256']) {
      throw StateError('Original window hash differs from replay');
    }
    if (missing != replay['missingFrameCount'] ||
        frames.length != frameMap.length) {
      throw StateError('Frame coverage differs');
    }
    for (final entry in originals.entries) {
      if (hash(File(entry.key).readAsBytesSync()) != entry.value) {
        throw StateError('Raw file changed');
      }
    }
    if (hash(fixtureFile.readAsBytesSync()) != hash(fixtureBytes)) {
      throw StateError('Fixture changed');
    }
    final live = frames.where((f) => f['supported'] == true).toList();
    final changes = live
        .where(
          (f) =>
              ((f['paired'] as Map)['magnitude'] as num?) !=
              f['baselineMagnitude'],
        )
        .toList();
    results.add({
      'id': replay['id'],
      'rawInputSha256': replay['rawInputSha256'],
      'fixtureSha256': hash(fixtureBytes),
      'missingFrames': missing,
      'checkedActiveValues': checkedActiveValues,
      'summary': {
        'frames': frames.length,
        'estimateFrames': live.length,
        'changedMagnitudeFrames': changes.length,
        'raisedPeakFrames': live
            .where(
              (f) => (f['peakIntensity'] as num) > (f['baselinePeak'] as num),
            )
            .length,
        'collectedFrames': live
            .where((f) => (f['observedInactiveMembers'] as Map).isNotEmpty)
            .length,
        'multipleSourceFrames': live
            .where((f) => f['collectionEnabled'] == false)
            .length,
        'lastBaseline': live.lastOrNull?['baselineMagnitude'],
        'lastExtended': (live.lastOrNull?['paired'] as Map?)?['magnitude'],
      },
      'frames': frames,
    });
  }
  if (hash(input.readAsBytesSync()) != hash(inputBytes)) {
    throw StateError('Report changed');
  }
  for (final entry in sourceHashes.entries) {
    if (hash(File(entry.key).readAsBytesSync()) != entry.value) {
      throw StateError('Source changed');
    }
  }
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'feedsProduction': false,
      'readyForProduction': false,
      'labelsUsedInInference': false,
      'policy': 'Only previously associated inactive members while a single selected source is live. Reset added peaks on key changes, multiple sources, missing frames or no output; no post-event tail or new stations.',
      'limits': ['Prior membership does not prove every later signal belongs to the event.', 'No extra peak inheritance between event keys; collection stops with source output.', 'Existing intensity-magnitude conversion is not newly calibrated.'],
      'inputReportSha256': hash(inputBytes),
      'sourceHashes': sourceHashes,
      'cases': results,
    })}\n',
    encoding: utf8,
  );
  stdout.writeln(
    jsonEncode([
      for (final r in results) {'id': r['id'], ...r['summary'] as Map},
    ]),
  );
}
