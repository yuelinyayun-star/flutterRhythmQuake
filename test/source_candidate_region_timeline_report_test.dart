import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifestPath =
    'docs/data/source_candidate_region_validation_manifest.json';

void main() {
  test(
    'candidate-region timeline keeps local support diagnostic-only',
    () async {
      final manifestFile = File(_manifestPath);
      expect(manifestFile.existsSync(), isTrue);
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      expect(
        manifest['schemaVersion'],
        'source_candidate_region_validation_manifest_v1',
      );
      final manifestCases = (manifest['cases'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      final missingInputs = [
        for (final entry in manifestCases)
          if (entry['benchmarkInput'] case final String path)
            if (!File(path).existsSync()) path,
      ];
      if (missingInputs.isNotEmpty) {
        markTestSkipped(
          'Missing local benchmark reports: ${missingInputs.join(', ')}',
        );
        return;
      }

      final reportFile = File(
        '.dart_tool/source_candidate_region_timeline_report/report.json',
      );
      if (!reportFile.existsSync()) {
        markTestSkipped(
          'Missing candidate-region timeline report. Run '
          '`dart run tools/build_source_candidate_region_timeline_report.dart`.',
        );
        return;
      }

      final report =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(report['schemaVersion'], 'source_candidate_region_timeline_v2');
      expect(report['skippedFiles'], isEmpty);
      final validation = report['validation'] as Map<String, Object?>;
      expect(validation['status'], 'pass');
      expect(validation['violations'], isEmpty);
      final reportManifest =
          report['validationManifest'] as Map<String, Object?>;
      expect(reportManifest['path'], _manifestPath);

      final cases = {
        for (final rawCase in report['cases'] as List)
          (rawCase as Map)['caseId'] as String: rawCase.cast<String, Object?>(),
      };

      expect(
        cases.keys,
        containsAll(manifestCases.map((entry) => entry['caseId'] as String)),
      );
      expect(
        cases.values.every(
          (entry) => entry['coordinateSwitchAllowedCount'] == 0,
        ),
        isTrue,
        reason: 'candidate-region metadata must not switch production coords',
      );

      expect(
        cases['20260625_iwate_offshore_m32_jma']!['localSupportConfirmedCount'],
        1,
      );
      expect(
        cases['20260625_iwate_offshore_m32_jma']!['confirmedDelayedCount'],
        1,
      );
      expect(
        cases['20260625_iwate_offshore_m32_jma']!['localSupportConfirmedDelayedCount'],
        1,
      );
      expect(
        cases['20260625_iwate_offshore_m32_jma']!['residualConfirmedDelayedCount'],
        0,
      );
      expect(cases['20260625_iwate_offshore_m32_jma']!['pendingCount'], 3);

      expect(
        cases['20260621_fukushima_offshore_m32_eq6']!['localSupportConfirmedCount'],
        0,
      );
      expect(
        cases['20260621_fukushima_offshore_m32_eq6']!['confirmedDelayedCount'],
        0,
      );
      expect(
        cases['20260621_fukushima_offshore_m32_eq6']!['confirmedImmediateCount'],
        0,
      );

      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['localSupportConfirmedCount'],
        0,
      );
      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['confirmedDelayedCount'],
        1,
      );
      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['residualConfirmedDelayedCount'],
        1,
      );
      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['localSupportConfirmedDelayedCount'],
        0,
      );
      expect(
        cases['20260622_kushiro_offshore_m30_jma']!['confirmedImmediateCount'],
        4,
      );

      expect(
        cases['20260622_tomakomai_south_offshore_m35_hinet']!['localSupportConfirmedCount'],
        0,
      );
      expect(
        cases['20260622_tomakomai_south_offshore_m35_hinet']!['confirmedImmediateCount'],
        3,
      );

      expect(
        cases['20260623_tokachi_southeast_offshore_m34_hinet']!['frameCount'],
        0,
      );
      expect(cases['20260624_fukushima_aizu_m32_jma_eq5']!['frameCount'], 0);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
