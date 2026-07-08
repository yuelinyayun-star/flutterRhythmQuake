import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/replay_dataset.dart';
import 'package:flutterrhythmquake/core/replay/replay_metrics.dart';

void main() {
  test('dataset split manifest freezes event-level splits', () {
    final fixtureDirectory = Directory('test/fixtures/source_estimation');
    final splitManifest = ReplayDatasetSplitManifest.fromFile(
      File('${fixtureDirectory.path}/dataset_splits.json'),
    );
    final allowedCases = fixtureDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .where((file) => !file.path.endsWith('dataset_splits.json'))
        .where((file) => !file.path.endsWith('baseline_suite.json'))
        .where((file) => !file.path.endsWith('detection_suite.json'))
        .toList(growable: false);

    expect(
      splitManifest.validate(
        allowedCaseManifests: allowedCases,
        benchmarkSuiteManifests: [
          File('${fixtureDirectory.path}/baseline_suite.json'),
        ],
      ),
      isEmpty,
    );
    expect(splitManifest.caseIdsFor('train'), {
      '20260610_nara_m36',
      '20260614_quiet_175544',
    });
    expect(splitManifest.caseIdsFor('validation'), {
      '20260620_satsuma_m26_d179',
      '20260620_kyoto_s_m18_d12',
    });
    expect(splitManifest.caseIdsFor('test'), {
      '20260620_ibaraki_offshore_m19_ref',
    });
    expect(
      splitManifest.isInSplit('20260620_ibaraki_offshore_m19_ref', 'test'),
      isTrue,
    );
  });

  test('dataset split validation rejects leakage into benchmark suite', () {
    final fixtureDirectory = Directory('test/fixtures/source_estimation');
    final splitManifest = ReplayDatasetSplitManifest.fromFile(
      File('${fixtureDirectory.path}/dataset_splits.json'),
    );
    final suite = File('${fixtureDirectory.path}/_leaky_suite.tmp.json');
    addTearDown(() {
      if (suite.existsSync()) suite.deleteSync();
    });
    suite.writeAsStringSync('''
{
  "schemaVersion": 1,
  "suiteId": "leaky",
  "cases": ["ibaraki_offshore_m19_ref.json"]
}
''');

    expect(
      splitManifest.validate(benchmarkSuiteManifests: [suite]),
      contains(
        'test_case_used_by_suite:20260620_ibaraki_offshore_m19_ref:leaky',
      ),
    );
  });

  test('replay metric calculator provides shared percentile semantics', () {
    expect(ReplayMetricCalculator.percentile([1, 3, 5], 0.5), 3);
    expect(ReplayMetricCalculator.percentile([1, 3, 5], 0.9), 4.6);
    expect(ReplayMetricCalculator.ratio(1, 4), 0.25);
    expect(ReplayMetricCalculator.ratio(1, 0), isNull);

    final distribution = ReplayMetricCalculator.distribution([10, 20, 30]);
    expect(distribution.count, 3);
    expect(distribution.median, 20);
    expect(distribution.p95, 29);
  });
}
