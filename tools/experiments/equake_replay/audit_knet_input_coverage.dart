import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';

String digest(List<int> bytes) => sha256.convert(bytes).toString();

void main(List<String> args) {
  if (args.length < 4) {
    throw ArgumentError(
      'Pass filtered report, replay report, case IDs in archive order, output',
    );
  }
  final filteredBytes = File(args[0]).readAsBytesSync();
  final replayBytes = File(args[1]).readAsBytesSync();
  final filtered = jsonDecode(utf8.decode(filteredBytes)) as Map;
  final replay = jsonDecode(utf8.decode(replayBytes)) as Map;
  final archives = (filtered['archives'] as List).cast<Map>();
  final ids = args.sublist(2, args.length - 1);
  if (ids.length != archives.length) {
    throw StateError('One explicit case ID per archive required');
  }
  final output = File(args.last);
  final root = Directory('.dart_tool').resolveSymbolicLinksSync();
  final parent = output.parent.resolveSymbolicLinksSync();
  if (output.existsSync() ||
      path.extension(output.path) != '.json' ||
      (!path.equals(root, parent) && !path.isWithin(root, parent))) {
    throw StateError('Use a new .dart_tool JSON output');
  }
  final scanHash = digest(
    File('lib/models/nied_scan_positions.dart').readAsBytesSync(),
  );
  if (scanHash != replay['scanPositionsSha256']) {
    throw StateError('Scan table changed');
  }
  final db = {for (final s in NiedStationDb.stations) s['code']: s};
  final results = <Map<String, Object?>>[];
  for (var i = 0; i < archives.length; i++) {
    final archive = archives[i];
    if (digest(File(archive['input'] as String).readAsBytesSync()) !=
        archive['sha256']) {
      throw StateError('Original waveform archive changed');
    }
    final event = (replay['cases'] as List).cast<Map>().singleWhere(
      (c) => c['id'] == ids[i],
    );
    final frames = (event['frames'] as List).cast<Map>();
    final last = frames.lastWhere((f) => f['estimate'] != null);
    final candidate =
        ((last['magnitudeAudit'] as Map)['experiment']
                as Map)['eventPeakCandidate']
            as Map;
    final saved = candidate['stationPeaks'] as Map;
    final activeCodes = <String>{
      for (final f in frames)
        for (final s
            in ((((f['magnitudeAudit'] as Map?)?['stationTrace']
                            as Map?)?['stations']
                        as List?) ??
                    [])
                .cast<Map>())
          s['code'] as String,
    };
    final rows = <Map<String, Object?>>[
      for (final s in (archive['stations'] as List).cast<Map>())
        {
          'code': s['station'],
          'name': db[s['station']]?['name'],
          'existsInStationDb': db.containsKey(s['station']),
          'hasScanPoint': NiedScanPositions.positions.containsKey(s['station']),
          'activeInAnyReplayFrame': activeCodes.contains(s['station']),
          'inFinalCandidate': saved.containsKey(s['station']),
          'finalCandidateGifPeak': saved[s['station']],
          'filteredWaveformRecordIntensity':
              (s['filteredRecord'] as Map)['continuousIntensity'],
          'unfilteredWaveformRecordIntensity':
              (s['unfilteredRecord'] as Map)['continuousIntensity'],
          'waveformFileSha256': s['fileSha256'],
        },
    ];
    rows.sort(
      (a, b) =>
          ((b['filteredWaveformRecordIntensity'] as num?) ??
                  double.negativeInfinity)
              .compareTo(
                (a['filteredWaveformRecordIntensity'] as num?) ??
                    double.negativeInfinity,
              ),
    );
    results.add({
      'caseId': ids[i],
      'waveformRecords': rows.length,
      'withoutScanPoint': rows.where((r) => r['hasScanPoint'] == false).length,
      'withScanPoint': rows.where((r) => r['hasScanPoint'] == true).length,
      'rows': rows,
    });
  }
  if (digest(File(args[0]).readAsBytesSync()) != digest(filteredBytes) ||
      digest(File(args[1]).readAsBytesSync()) != digest(replayBytes)) {
    throw StateError('Input report changed');
  }
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'feedsProduction': false, 'readyForCalibration': false, 'filteredReportSha256': digest(filteredBytes), 'replayReportSha256': digest(replayBytes), 'scanPositionsSha256': scanHash, 'scope': 'Explicit event pairing and exact station-code coverage only. No waveform/GIF time-window equivalence or magnitude conversion is assumed.', 'cases': results})}\n',
    encoding: utf8,
  );
  stdout.writeln(
    jsonEncode([
      for (final r in results)
        {
          'caseId': r['caseId'],
          'records': r['waveformRecords'],
          'withoutScanPoint': r['withoutScanPoint'],
          'strongest': (r['rows'] as List).first,
        },
    ]),
  );
}
