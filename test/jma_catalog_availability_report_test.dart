import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_jma_catalog_availability_report.dart';

void main() {
  test('JMA catalog availability script regenerates readiness first', () {
    final script = File(
      'tools/validate_jma_catalog_availability.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains(r'[switch]$UseExistingReadiness'));
    expect(script, contains(r'if (-not $UseExistingReadiness)'));
    expect(
      script,
      contains('validate_source_estimation_split_assignment_readiness.ps1'),
    );
    expect(script, contains('build_jma_catalog_availability_report.dart'));
    expect(script, contains('build_jma_final_catalog_review_packet.dart'));
    expect(script, contains('jma_catalog_availability_report_test.dart'));
    expect(script, contains('jma_final_catalog_review_packet_test.dart'));
    expect(
      script.indexOf('validate_source_estimation_split_assignment_readiness'),
      lessThan(script.indexOf('build_jma_catalog_availability_report')),
    );
    expect(
      script.indexOf('build_jma_catalog_availability_report.dart'),
      lessThan(script.indexOf('build_jma_final_catalog_review_packet.dart')),
    );
    expect(
      script.indexOf('build_jma_final_catalog_review_packet.dart'),
      lessThan(script.indexOf('jma_catalog_availability_report_test.dart')),
    );
  });

  test(
    'recent JMA blockers remain blocked by external catalog availability',
    () {
      final reportFile = File(
        '.dart_tool/jma_catalog_availability_report/report.json',
      );
      if (!reportFile.existsSync()) {
        markTestSkipped(
          'Missing JMA catalog availability report. Run '
          '`dart run tools/build_jma_catalog_availability_report.dart`.',
        );
        return;
      }

      final report =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      expect(report['schemaVersion'], 'jma_catalog_availability_report_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);
      expect(report['warnings'], isEmpty);
      expect(report['readinessStatus'], 'pass');

      final availability = (report['availability'] as Map)
          .cast<String, Object?>();
      expect(availability['schemaVersion'], 'jma_catalog_availability_v1');
      expect(availability['asOf'], '2026-06-26');
      expect(availability['latestAvailableFinalCatalogYear'], 2023);
      final evidence =
          (availability['latestAvailableFinalCatalogEvidence'] as Map)
              .cast<String, Object?>();
      expect(evidence['checkedAtUtc'], '2026-06-26T06:20:00Z');
      expect(
        evidence['sourceUrl'],
        'https://www.data.jma.go.jp/eqev/data/bulletin/hypo.html',
      );
      expect(evidence['observedLatestYearLink'], 2023);
      expect(
        evidence['observedMissingYearLinks'],
        containsAll([2024, 2025, 2026]),
      );

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['jmaCatalogBlockerCount'], 9);
      expect(summary['externalCatalogNotYetAvailableCount'], 9);
      expect(summary['catalogAvailableLinkMissingCount'], 0);
      expect(summary['linkedToVersionedCatalogCount'], 0);

      final blockers = (report['blockers'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(
        blockers.map((entry) => entry['caseId']),
        containsAll([
          '20260622_kushiro_offshore_m30_jma',
          '20260624_fukushima_aizu_m32_jma_eq5',
          '20260625_iwate_offshore_m32_jma',
          '20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p',
          '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
          '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
          '20260627_fukushima_aizu_m36_jma_equake17',
          '20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p',
          '20260628_iwate_offshore_m41_jma',
        ]),
      );
      for (final blocker in blockers) {
        expect(blocker['truthSource'], 'jma_source_and_intensity_information');
        expect(blocker['eventYear'], 2026);
        expect(blocker['linkedToVersionedCatalog'], isFalse);
        expect(blocker['coveredByAvailableCatalog'], isFalse);
        expect(blocker['status'], 'external_catalog_not_yet_available');
        expect(
          blocker['evidence'],
          'event_year_2026_after_latest_available_final_catalog_2023',
        );
      }
    },
  );

  test(
    'availability evidence must match declared latest final catalog year',
    () {
      final tempDir = Directory.systemTemp.createTempSync(
        'jma_catalog_availability_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final availability =
          jsonDecode(
                File(
                  'docs/data/jma_catalog_availability.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final evidence =
          (availability['latestAvailableFinalCatalogEvidence'] as Map)
              .cast<String, Object?>();
      evidence['observedLatestYearLink'] = 2024;
      availability['latestAvailableFinalCatalogEvidence'] = evidence;

      final availabilityFile = File('${tempDir.path}/availability.json')
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(availability)}\n',
        );

      final report = buildJmaCatalogAvailabilityReportJson(
        availabilityPath: availabilityFile.path,
      );
      expect(report['status'], 'fail');
      expect(
        report['errors'],
        contains('jma_catalog_availability_evidence_year_mismatch:2024!=2023'),
      );
    },
  );
}
