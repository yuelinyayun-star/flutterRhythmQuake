import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/replay_dataset.dart';

import 'support/split_aware_replay_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'split-aware evaluator writes source and detection reports per split',
    () async {
      final dataset = ReplayDatasetSplitManifest.fromFile(
        File('test/fixtures/source_estimation/dataset_splits.json'),
      );
      final outputDirectory = Directory(
        '.dart_tool/split_aware_replay_benchmark',
      );
      if (outputDirectory.existsSync()) {
        outputDirectory.deleteSync(recursive: true);
      }

      final report = await SplitAwareBenchmarkRunner(
        dataset: dataset,
        workspaceRoot: Directory.current,
      ).run(outputDirectory: outputDirectory);

      expect(report.datasetId, 'source_estimation_p1');
      expect(report.splits.map((split) => split.splitName), [
        'train',
        'validation',
        'test',
      ]);

      final splitReports = {
        for (final split in report.splits) split.splitName: split,
      };
      expect(splitReports['train']!.caseCount, 2);
      expect(splitReports['validation']!.caseCount, 2);
      expect(splitReports['test']!.caseCount, 1);
      expect(
        splitReports['test']!.sourceReport.cases.single.replayCase.caseId,
        '20260620_ibaraki_offshore_m19_ref',
      );

      for (final splitName in ['train', 'validation', 'test']) {
        expect(
          File('${outputDirectory.path}/$splitName/source.json').existsSync(),
          isTrue,
        );
        expect(
          File('${outputDirectory.path}/$splitName/source.md').existsSync(),
          isTrue,
        );
        expect(
          File(
            '${outputDirectory.path}/$splitName/detection.json',
          ).existsSync(),
          isTrue,
        );
        expect(
          File('${outputDirectory.path}/$splitName/detection.md').existsSync(),
          isTrue,
        );
      }

      final summary =
          jsonDecode(
                File('${outputDirectory.path}/summary.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(summary['datasetId'], 'source_estimation_p1');
      expect((summary['splits']! as Map<String, Object?>).keys, {
        'train',
        'validation',
        'test',
      });
      expect(
        File('${outputDirectory.path}/summary.md').readAsStringSync(),
        contains('too small for algorithm superiority claims'),
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
