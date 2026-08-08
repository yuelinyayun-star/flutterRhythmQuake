import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _regionNamesByEventId = {
  '2011031115254433-37.9143-144.7510': '三陸沖',
  '2011031204315560-36.9488-138.5725': '長野県北部',
  '2011031205421980-36.9732-138.5905': '長野県北部',
  '2011040723324346-38.2042-141.9202': '宮城県沖',
  '2011041214074228-37.0525-140.6435': '福島県中通り',
  '2013041305331775-34.4188-134.8290': '淡路島付近',
  '2014112222081790-36.6928-137.8910': '長野県北部',
  '2016041421263443-32.7417-130.8087': '熊本県熊本地方',
  '2016041422073529-32.7755-130.8495': '熊本県熊本地方',
  '2016041603555308-33.0265-131.1910': '熊本県阿蘇地方',
  '2016102114072257-35.3805-133.8562': '鳥取県中部',
  '2016122821384904-36.7202-140.5742': '茨城県北部',
  '2018061807583414-34.8443-135.6217': '大阪府北部',
  '2018090603075933-42.6908-142.0067': '胆振地方中東部',
};

const _compoundRegionNamesByOriginTime = {
  '2011-03-11T06:15:34.25Z': '茨城県沖',
  '2011-03-11T18:59:15.62Z': '長野県北部',
  '2011-03-15T13:31:46.34Z': '静岡県東部',
  '2011-04-11T08:16:12.02Z': '福島県浜通り',
  '2016-04-14T15:03:46.45Z': '熊本県熊本地方',
  '2016-04-15T16:25:05.47Z': '熊本県熊本地方',
  '2016-04-15T16:45:55.45Z': '熊本県熊本地方',
  '2016-04-16T00:48:32.68Z': '熊本県熊本地方',
  '2016-06-16T05:21:28.2Z': '内浦湾',
};

const _auditedFaultModelsByEventId = {
  '2011031115254433-37.9143-144.7510': {
    'status': 'audited_no_usable_finite_fault_model_found',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_sanriku_m75_finite_fault_audit.md',
  },
  '2011031204315560-36.9488-138.5725': {
    'status': 'audited_no_usable_finite_fault_model_found',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_nagano_m59_finite_fault_audit.md',
  },
  '2011031205421980-36.9732-138.5905': {
    'status': 'audited_no_usable_finite_fault_model_found',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_nagano_m53_finite_fault_audit.md',
  },
  '2011040723324346-38.2042-141.9202': {
    'status': 'audited_no_unambiguous_finite_rupture_boundary',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_miyagi_oki_m72_finite_fault_audit.md',
  },
  '2011041214074228-37.0525-140.6435': {
    'status': 'source_backed_finite_fault_diagnostic_complete',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_fukushima_nakadori_m64_finite_fault_diagnostic.md',
  },
  '2013041305331775-34.4188-134.8290': {
    'status': 'audited_no_unambiguous_finite_rupture_boundary',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_awaji_m63_finite_fault_audit.md',
  },
  '2014112222081790-36.6928-137.8910': {
    'status': 'source_backed_finite_fault_diagnostic_complete',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_nagano_2014_m67_finite_fault_diagnostic.md',
  },
  '2016041421263443-32.7417-130.8087': {
    'status': 'source_backed_finite_fault_diagnostic_complete',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_kumamoto_m65_finite_fault_diagnostic.md',
  },
  '2016041422073529-32.7755-130.8495': {
    'status': 'audited_no_usable_finite_fault_model_found',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_kumamoto_m58_finite_fault_audit.md',
  },
  '2016041603555308-33.0265-131.1910': {
    'status': 'audited_no_usable_finite_fault_model_found',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_aso_m58_finite_fault_audit.md',
  },
  '2016102114072257-35.3805-133.8562': {
    'status': 'source_backed_finite_fault_diagnostic_complete',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_tottori_m66_finite_fault_diagnostic.md',
  },
  '2016122821384904-36.7202-140.5742': {
    'status': 'source_backed_finite_fault_diagnostic_complete',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_ibaraki_m63_finite_fault_diagnostic.md',
  },
  '2018061807583414-34.8443-135.6217': {
    'status': 'source_backed_finite_fault_diagnostic_complete',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_osaka_finite_fault_diagnostic.md',
  },
  '2018090603075933-42.6908-142.0067': {
    'status':
        'source_backed_curved_fault_model_archived_no_nearfield_diagnostic',
    'record':
        'lib/core/intensity_reconstruction/experiments/experiment_1/'
        'matsuzaki_2006_iburi_m67_curved_fault_audit.md',
  },
};

void main(List<String> arguments) {
  final inputPaths = _values(arguments, '--input');
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_finite_fault_event_inventory',
  );
  if (inputPaths.isEmpty) {
    stderr.writeln(
      'Usage: dart run '
      'tool/matsuzaki_2006_finite_fault_event_inventory.dart '
      '--input <annual.json> [...] --allow-opened-2018 '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  if (!arguments.contains('--allow-opened-2018')) {
    stderr.writeln(
      'Refusing to inventory through 2018 without explicit '
      '--allow-opened-2018.',
    );
    exitCode = 65;
    return;
  }
  final missing = inputPaths.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing input files: ${missing.join(', ')}');
    exitCode = 66;
    return;
  }

  const expectedYears = {2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018};
  const evaluator = Matsuzaki2006JmaBaselineEvaluator();
  final loadedYears = <int>{};
  final candidates = <Map<String, Object?>>[];
  final excludedCompoundCandidates = <Map<String, Object?>>[];
  final annual = <Map<String, Object>>[];
  for (final inputPath in inputPaths) {
    final dataset = _readJsonObject(inputPath);
    final year = (dataset['year']! as num).toInt();
    if (!expectedYears.contains(year) || !loadedYears.add(year)) {
      throw FormatException('Unexpected or duplicate year $year.');
    }
    final rawEvents = dataset['events'];
    if (rawEvents is! List<Object?>) {
      throw FormatException('Invalid events list for year $year.');
    }
    for (final rawEvent in rawEvents) {
      if (rawEvent is! Map<String, Object?>) continue;
      final alternates = rawEvent['alternateHypocenters'];
      if (alternates is! List<Object?> || alternates.isEmpty) continue;
      final hypocenters = <(String, Map<String, Object?>)>[];
      final preferred = rawEvent['preferredHypocenter'];
      if (preferred is Map<String, Object?>) {
        hypocenters.add(('preferred', preferred));
      }
      for (final alternate in alternates) {
        if (alternate is Map<String, Object?>) {
          hypocenters.add(('alternate', alternate));
        }
      }
      for (final entry in hypocenters) {
        final reasons = _rawCandidateReasons(entry.$2);
        if (reasons.isEmpty) continue;
        final originTime = entry.$2['originTime'];
        final regionName = originTime is String
            ? _compoundRegionNamesByOriginTime[_canonicalOriginTime(originTime)]
            : null;
        if (regionName == null) {
          throw StateError(
            'Compound candidate $originTime has no audited CP932 region name.',
          );
        }
        excludedCompoundCandidates.add({
          'year': year,
          'parentEventId': rawEvent['eventId'] as String? ?? '',
          'hypocenterRole': entry.$1,
          'originTime': originTime,
          'regionName': regionName,
          'latitude': entry.$2['latitude'],
          'longitude': entry.$2['longitude'],
          'depthKm': entry.$2['depthKm'],
          'magnitude': entry.$2['magnitude'],
          'magnitudeType': entry.$2['magnitudeType'],
          'maximumIntensityClass': entry.$2['maximumIntensityClass'],
          'parentObservationCount':
              (rawEvent['observations'] as List<Object?>?)?.length ?? 0,
          'parentHypocenterCount': hypocenters.length,
          'candidateReasons': reasons,
          'exclusionReason':
              'observations_not_assignable_among_compound_hypocenters',
        });
      }
    }
    final result = evaluator.evaluate([dataset]);
    var annualCandidateCount = 0;
    for (final event in result.events) {
      final reasons = <String>[
        if (const {'C', 'D', '7'}.contains(event.maximumIntensityClass))
          'maximum_intensity_at_least_6_lower',
        if (event.magnitude >= 7.5) 'magnitude_at_least_7_5',
      ];
      if (reasons.isEmpty) continue;
      final regionName = _regionNamesByEventId[event.eventId];
      if (regionName == null) {
        throw StateError(
          'Candidate ${event.eventId} has no audited CP932 region name.',
        );
      }
      annualCandidateCount++;
      final nearStations = event.stationResiduals
          .where((station) => station.sourceDistanceKm < 30)
          .length;
      final auditedFaultModel = _auditedFaultModelsByEventId[event.eventId];
      candidates.add({
        'eventId': event.eventId,
        'year': event.year,
        'originTime': event.originTime,
        'regionName': regionName,
        'latitude': event.latitude,
        'longitude': event.longitude,
        'depthKm': event.depthKm,
        'magnitude': event.magnitude,
        'magnitudeType': event.magnitudeType,
        'maximumIntensityClass': event.maximumIntensityClass,
        'acceptedStationCount': event.stationResiduals.length,
        'pointSourceNearfieldStationCount': nearStations,
        'candidateReasons': reasons,
        'faultModelStatus': auditedFaultModel?['status'] ?? 'not_yet_audited',
        if (auditedFaultModel case {'record': final String record})
          'faultModelRecord': record,
      });
    }
    annual.add({
      'year': year,
      'acceptedEvents': result.events.length,
      'acceptedStations': result.stationResidualCount,
      'candidateEvents': annualCandidateCount,
    });
    stdout.writeln(
      'year=$year accepted=${result.events.length} '
      'candidates=$annualCandidateCount',
    );
  }
  if (!loadedYears.containsAll(expectedYears)) {
    throw FormatException(
      'Missing expected years: ${expectedYears.difference(loadedYears)}.',
    );
  }
  annual.sort(
    (left, right) => (left['year']! as int).compareTo(right['year']! as int),
  );
  candidates.sort(
    (left, right) => (left['originTime']! as String).compareTo(
      right['originTime']! as String,
    ),
  );
  excludedCompoundCandidates.sort(
    (left, right) => (left['originTime']! as String).compareTo(
      right['originTime']! as String,
    ),
  );

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_finite_fault_event_inventory_v1',
    'years': expectedYears.toList()..sort(),
    'productionAdoption': false,
    'distancePolicySource': {
      'paper': 'references/papers/2006_松崎久田福島_断層近傍まで適用可能な震度の距離減衰式の開発.pdf',
      'section': '3.2.2',
    },
    'candidatePolicy': {
      'maximumIntensityClasses': {
        'C': 'JMA intensity 6-lower',
        'D': 'JMA intensity 6-upper',
        '7': 'JMA intensity 7',
      },
      'magnitudeThreshold': 7.5,
      'candidateDoesNotImplyFaultModelAvailability': true,
      'noEmpiricalFaultDimensionsGenerated': true,
      'regionNameSource':
          'preferredHypocenter.rawRegionHex decoded as Windows-31J/CP932',
    },
    'annual': annual,
    'candidateCount': candidates.length,
    'candidates': candidates,
    'excludedCompoundCandidateCount': excludedCompoundCandidates.length,
    'excludedCompoundCandidates': excludedCompoundCandidates,
  };
  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  final markdownFile = File('${outputDirectory.path}/report.md');
  jsonFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    encoding: utf8,
  );
  markdownFile.writeAsStringSync(
    _toMarkdown(
      annual: annual,
      candidates: candidates,
      excludedCompoundCandidates: excludedCompoundCandidates,
    ),
    encoding: utf8,
  );
  stdout.writeln('candidateCount=${candidates.length}');
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

Map<String, Object?> _readJsonObject(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object in $path.');
  }
  return decoded;
}

List<String> _rawCandidateReasons(Map<String, Object?> hypocenter) {
  final magnitude = hypocenter['magnitude'];
  final maximumIntensityClass = hypocenter['maximumIntensityClass'];
  return [
    if (maximumIntensityClass is String &&
        const {'C', 'D', '7'}.contains(maximumIntensityClass.trim()))
      'maximum_intensity_at_least_6_lower',
    if (magnitude is num && magnitude.toDouble() >= 7.5)
      'magnitude_at_least_7_5',
  ];
}

String _canonicalOriginTime(String value) =>
    value.replaceFirst(RegExp(r'0+Z$'), 'Z').replaceFirst('.Z', 'Z');

String _toMarkdown({
  required List<Map<String, Object>> annual,
  required List<Map<String, Object?>> candidates,
  required List<Map<String, Object?>> excludedCompoundCandidates,
}) {
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Finite-Fault Event Inventory')
    ..writeln()
    ..writeln(
      'Candidates satisfy the strict JMA baseline and either reached maximum '
      'intensity 6-lower or greater, or have Mj >= 7.5. Candidate status does '
      'not assert that a usable finite-fault model exists.',
    )
    ..writeln()
    ..writeln('## Annual Counts')
    ..writeln()
    ..writeln('| Year | Accepted events | Accepted stations | Candidates |')
    ..writeln('|---:|---:|---:|---:|');
  for (final entry in annual) {
    buffer.writeln(
      '| ${entry['year']} | ${entry['acceptedEvents']} | '
      '${entry['acceptedStations']} | ${entry['candidateEvents']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Candidates')
    ..writeln()
    ..writeln(
      '| Origin time | Region | Event ID | Mj | Depth km | Max intensity | Stations | Near stations | Fault model | Reasons |',
    )
    ..writeln('|---|---|---|---:|---:|---|---:|---:|---|---|');
  for (final event in candidates) {
    buffer.writeln(
      '| ${event['originTime']} | ${event['regionName']} | '
      '`${event['eventId']}` | '
      '${event['magnitude']} | ${event['depthKm']} | '
      '${event['maximumIntensityClass']} | ${event['acceptedStationCount']} | '
      '${event['pointSourceNearfieldStationCount']} | '
      '${event['faultModelStatus']} | '
      '${(event['candidateReasons']! as List<Object?>).join(', ')} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Excluded Compound-Record Candidates')
    ..writeln()
    ..writeln(
      'These hypocenters meet the distance-policy condition, but their parent '
      'records contain multiple hypocenters whose observations cannot be '
      'assigned reliably. They are not calibration events.',
    )
    ..writeln()
    ..writeln(
      '| Origin time | Region | Parent event | Role | Mj | Max intensity | Hypocenters | Observations | Reasons |',
    )
    ..writeln('|---|---|---|---|---:|---|---:|---:|---|');
  for (final event in excludedCompoundCandidates) {
    buffer.writeln(
      '| ${event['originTime']} | ${event['regionName']} | '
      '`${event['parentEventId']}` | '
      '${event['hypocenterRole']} | ${event['magnitude']} | '
      '${event['maximumIntensityClass']} | ${event['parentHypocenterCount']} | '
      '${event['parentObservationCount']} | '
      '${(event['candidateReasons']! as List<Object?>).join(', ')} |',
    );
  }
  return buffer.toString();
}

List<String> _values(List<String> arguments, String name) {
  final values = <String>[];
  for (var index = 0; index < arguments.length - 1; index++) {
    if (arguments[index] == name) values.add(arguments[index + 1]);
  }
  return values;
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}
