import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/replay/jma_catalog.dart';

void main(List<String> args) {
  final catalogPath = _argument(args, '--catalog');
  final casePath = _argument(args, '--case');
  final shouldWrite = args.contains('--write');
  if (catalogPath == null || casePath == null) {
    stderr.writeln(
      'Usage: dart run tools/link_jma_catalog.dart '
      '--catalog <catalog.json> --case <fixture.json> [--write]',
    );
    exitCode = 64;
    return;
  }

  final catalogFile = File(catalogPath);
  final caseFile = File(casePath);
  final catalog = JmaCatalog.fromFile(catalogFile);
  final catalogIssues = catalog.validate();
  if (catalogIssues.isNotEmpty) {
    stderr.writeln(jsonEncode({'catalogIssues': catalogIssues}));
    exitCode = 65;
    return;
  }

  final replayCase =
      jsonDecode(caseFile.readAsStringSync()) as Map<String, Object?>;
  if (replayCase['caseType'] != 'event') {
    stderr.writeln('JMA catalog labels can only be linked to event cases.');
    exitCode = 65;
    return;
  }
  final truth = replayCase['truth']! as Map<String, Object?>;
  final result = const JmaCatalogMatcher().match(
    catalog,
    JmaCatalogReference(
      originTime: _parseJstInstant(truth['originTimeJst']! as String),
      latitude: (truth['latitude']! as num).toDouble(),
      longitude: (truth['longitude']! as num).toDouble(),
      magnitude: (truth['magnitude'] as num?)?.toDouble(),
    ),
  );
  final output = <String, Object?>{
    'caseId': replayCase['caseId'],
    'catalogId': catalog.catalogId,
    'catalogRevision': catalog.revision,
    'status': result.status.name,
    'match': result.match?.toJson(),
    'candidates': result.candidates
        .take(5)
        .map((candidate) => candidate.toJson())
        .toList(growable: false),
    'written': false,
  };
  if (result.status != JmaCatalogMatchStatus.matched) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
    exitCode = result.status == JmaCatalogMatchStatus.ambiguous ? 2 : 1;
    return;
  }

  if (shouldWrite) {
    final candidate = result.match!;
    final event = candidate.event;
    truth
      ..['originTimeJst'] = _jstWallClock(event.originTime)
      ..['latitude'] = event.latitude
      ..['longitude'] = event.longitude
      ..['depthKm'] = event.depthKm
      ..['magnitude'] = event.magnitude
      ..['source'] = 'jma_final_catalog'
      ..['catalog'] = {
        'agency': 'JMA',
        'catalogId': catalog.catalogId,
        'catalogRevision': catalog.revision,
        'eventId': event.eventId,
        'resourceId': event.resourceId,
        'revision': event.revision,
        'status': event.status,
        'sourceUrl': event.sourceUrl ?? catalog.sourceUrl,
        'matchedAt': DateTime.now().toUtc().toIso8601String(),
        'match': candidate.toJson(),
      };
    final labels = replayCase['eventLabels']! as Map<String, Object?>;
    labels['catalogTruthVerified'] = true;
    final classification =
        replayCase['classification'] as Map<String, Object?>? ??
        <String, Object?>{};
    classification['truthQuality'] = 'catalog_verified';
    replayCase['classification'] = classification;
    caseFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(replayCase)}\n',
    );
    output['written'] = true;
  }

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

DateTime _parseJstInstant(String value) {
  if (RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value)) {
    return DateTime.parse(value).toUtc();
  }
  final wallClock = DateTime.parse(value);
  return DateTime.utc(
    wallClock.year,
    wallClock.month,
    wallClock.day,
    wallClock.hour - 9,
    wallClock.minute,
    wallClock.second,
    wallClock.millisecond,
    wallClock.microsecond,
  );
}

String _jstWallClock(DateTime instant) {
  final jst = instant.toUtc().add(const Duration(hours: 9));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${jst.year.toString().padLeft(4, '0')}-'
      '${two(jst.month)}-${two(jst.day)}T'
      '${two(jst.hour)}:${two(jst.minute)}:${two(jst.second)}';
}
