import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_surface_image_only_comparison.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'surface image only comparison runs jma_s for every station',
    () async {
      final report = await buildSourceSurfaceImageOnlyComparisonJson();

      expect(
        report['schemaVersion'],
        'source_surface_image_only_comparison_v1',
      );
      expect(report['status'], 'pass');
      expect(report['errors'], isEmpty);

      final policy = (report['policy'] as Map).cast<String, Object?>();
      expect(policy['diagnosticOnly'], isTrue);
      expect(policy['productionBehaviorChanged'], isTrue);
      expect(
        policy['surfaceImageOnlyMeaning'],
        contains('including KiK-net stations'),
      );
      expect(policy['currentDefaultInput'], contains('jma_s'));

      final summary = (report['summary'] as Map).cast<String, Object?>();
      expect((summary['caseCount'] as int), greaterThan(0));
      expect((summary['eventCaseCount'] as int), greaterThan(0));

      final cases = (report['cases'] as List)
          .map((entry) => (entry as Map).cast<String, Object?>())
          .toList(growable: false);
      expect(
        cases,
        contains(
          predicate<Map<String, Object?>>(
            (entry) =>
                entry['caseId'] ==
                '20260622_tomakomai_south_offshore_m35_hinet',
          ),
        ),
      );

      final output = File(
        '.dart_tool/source_surface_image_only_comparison/report.json',
      )..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdown = File(
        'docs/baselines/source_surface_image_only_comparison.generated.md',
      )..parent.createSync(recursive: true);
      markdown.writeAsStringSync(
        sourceSurfaceImageOnlyComparisonMarkdown(report),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
