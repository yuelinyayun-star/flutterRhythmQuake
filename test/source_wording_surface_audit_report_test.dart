import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_wording_surface_audit_report.dart';

void main() {
  test('wording surface audit validator runs boundary prerequisite', () {
    final script = File(
      'tools/validate_source_wording_surface_audit.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('validate_source_confidence_wording_boundary.ps1'));
    expect(script, contains('build_source_wording_surface_audit_report.dart'));
    expect(script, contains('source_wording_surface_audit_report_test.dart'));
  });

  test(
    'wording surface audit keeps candidate-region out of official paths',
    () {
      final report = buildSourceWordingSurfaceAuditReportJson();

      expect(report['schemaVersion'], 'source_wording_surface_audit_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['productionCoordinateSwitchAllowed'], isFalse);
      expect(policy['officialAlertWordingAllowed'], isFalse);

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['checkCount'], 7);
      expect(summary['passedCheckCount'], 7);
      expect(summary['failedCheckCount'], 0);
      expect(summary['sourceCardCheckCount'], 3);
      expect(summary['voicePathCheckCount'], 1);
      expect(summary['officialAdapterCheckCount'], 1);

      final validation = (report['validation'] as Map).cast<String, Object?>();
      expect(validation['status'], 'pass');
      expect(validation['violations'], isEmpty);

      final checks = {
        for (final rawCheck in report['checks'] as List)
          (rawCheck as Map)['id'] as String: rawCheck.cast<String, Object?>(),
      };
      expect(
        checks.keys,
        containsAll({
          'source_card_candidate_copy',
          'candidate_region_expired_hidden',
          'source_trigger_line_no_candidate_region',
          'source_event_not_inserted_into_official_unified_queue',
          'voice_path_excludes_candidate_region',
          'official_adapter_excludes_candidate_region',
          'debug_surface_keeps_full_candidate_region_metadata',
        }),
      );
      expect(checks.values.every((entry) => entry['status'] == 'pass'), isTrue);
      expect(
        checks['candidate_region_expired_hidden']!['surface'],
        'source_estimation_unified_card',
      );
      expect(
        checks['voice_path_excludes_candidate_region']!['surface'],
        'voice_tts',
      );
      expect(
        checks['official_adapter_excludes_candidate_region']!['surface'],
        'official_alert_adapter',
      );

      final reportFile = File(
        '.dart_tool/source_wording_surface_audit/report.json',
      );
      if (reportFile.existsSync()) {
        final generated =
            jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
        expect(generated['schemaVersion'], report['schemaVersion']);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
