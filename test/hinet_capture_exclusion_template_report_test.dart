import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_hinet_capture_exclusion_template_report.dart';

void main() {
  test(
    'capture exclusion template report has no templates after exclusion approved',
    () {
      final report = buildHinetCaptureExclusionTemplateJson();

      expect(report['schemaVersion'], 'hinet_capture_exclusion_templates_v1');
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);
      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect(summary['exclusionTemplateCount'], 0);
      expect(summary['manualReviewRequiredCount'], 0);
      expect(summary['automaticClearanceCount'], 0);
      expect(summary['ledgerMutationCount'], 0);
      expect(summary['affectedFileCount'], 0);

      final templates = (report['templates'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(templates, isEmpty);
    },
  );

  test('capture exclusion template report does not mutate decisions', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'hinet_capture_exclusion_templates_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final report = buildHinetCaptureExclusionTemplateJson(
      templateDirectory: tempDir.path,
    );
    final templates = (report['templates'] as List);
    expect(templates, isEmpty);

    final decisionFile = File(
      'docs/data/hinet_capture_provenance_review_decisions.json',
    );
    final before = jsonDecode(decisionFile.readAsStringSync());
    final after = jsonDecode(decisionFile.readAsStringSync());
    expect(after, before);
  });
}
