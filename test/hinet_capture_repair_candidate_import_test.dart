import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tools/import_hinet_capture_repair_candidate.dart';

void main() {
  test('capture repair importer validates and dry-run does not mutate', () {
    final sandbox = _RepairSandbox.create();
    addTearDown(sandbox.dispose);

    final beforeManifest = sandbox.manifestFile.readAsStringSync();
    final beforeCaptureManifest = sandbox.captureManifestFile
        .readAsStringSync();
    final beforeDecisions = sandbox.decisionFile.readAsStringSync();

    final result = importHinetCaptureRepairCandidate(
      decisionFile: sandbox.decisionFile,
      inputFile: sandbox.inputFile,
      dryRun: true,
    );

    expect(result['status'], 'pass');
    expect(result['errors'], isEmpty);
    expect(result['dryRun'], isTrue);
    expect(sandbox.manifestFile.readAsStringSync(), beforeManifest);
    expect(
      sandbox.captureManifestFile.readAsStringSync(),
      beforeCaptureManifest,
    );
    expect(sandbox.decisionFile.readAsStringSync(), beforeDecisions);
    expect(
      File(
        '${sandbox.captureDirectory.path}/20260620212727.jma_b.gif',
      ).existsSync(),
      isFalse,
    );
  });

  test('capture repair importer copies GIF and updates manifests', () {
    final sandbox = _RepairSandbox.create();
    addTearDown(sandbox.dispose);

    final result = importHinetCaptureRepairCandidate(
      decisionFile: sandbox.decisionFile,
      inputFile: sandbox.inputFile,
    );

    expect(result['status'], 'pass');
    expect(result['dryRun'], isFalse);
    final repairedGif = File(
      '${sandbox.captureDirectory.path}/20260620212727.jma_b.gif',
    );
    expect(repairedGif.existsSync(), isTrue);
    expect(repairedGif.readAsBytesSync(), sandbox.gifBytes);

    final manifest =
        jsonDecode(sandbox.manifestFile.readAsStringSync())
            as Map<String, Object?>;
    expect(manifest['missingFrames'], isEmpty);
    expect(manifest['repairs'], isNotEmpty);

    final captureManifest =
        jsonDecode(sandbox.captureManifestFile.readAsStringSync())
            as Map<String, Object?>;
    expect(captureManifest['downloadedGifCount'], 302);
    expect(captureManifest['failedGifCount'], 0);
    final records = (captureManifest['records'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final repairedRecord = records.singleWhere(
      (entry) => entry['file'] == '20260620212727.jma_b.gif',
    );
    expect(repairedRecord['ok'], isTrue);
    expect(repairedRecord['sha256'], sandbox.gifSha256);
    expect(repairedRecord['cacheStatus'], 'repaired_from_local_candidate');
    expect(repairedRecord.containsKey('error'), isFalse);

    final decisions =
        jsonDecode(sandbox.decisionFile.readAsStringSync())
            as Map<String, Object?>;
    final decision = ((decisions['cases'] as List).single as Map)
        .cast<String, Object?>();
    expect(decision['decisionStatus'], 'capture_frame_repaired');
    expect(decision['reviewer'], 'unit-test');
    expect(decision['exclusionApproved'], isFalse);
    expect(decision['repairedFiles'], isNotEmpty);
  });

  test('capture repair importer rejects placeholders and auth material', () {
    final sandbox = _RepairSandbox.create();
    addTearDown(sandbox.dispose);

    final payload =
        jsonDecode(sandbox.inputFile.readAsStringSync())
            as Map<String, Object?>;
    payload['reviewer'] = '<fill-reviewer>';
    payload['cookie'] = 'secret';

    final decisions =
        jsonDecode(sandbox.decisionFile.readAsStringSync())
            as Map<String, Object?>;
    final errors = validateHinetCaptureRepairCandidateInput(
      decisionsJson: decisions,
      inputJson: payload,
    );

    expect(errors, contains('input_contains_sensitive_auth_material'));
    expect(errors, contains('unresolved_placeholder:reviewer'));
  });
}

class _RepairSandbox {
  final Directory root;
  final Directory captureDirectory;
  final File candidateFile;
  final File inputFile;
  final File decisionFile;
  final File manifestFile;
  final File captureManifestFile;
  final List<int> gifBytes;
  final String gifSha256;

  const _RepairSandbox({
    required this.root,
    required this.captureDirectory,
    required this.candidateFile,
    required this.inputFile,
    required this.decisionFile,
    required this.manifestFile,
    required this.captureManifestFile,
    required this.gifBytes,
    required this.gifSha256,
  });

  static _RepairSandbox create() {
    final root = Directory.systemTemp.createTempSync(
      'hinet_capture_repair_import_',
    );
    final captureDirectory = Directory('${root.path}/capture')..createSync();
    final candidateDirectory = Directory('${root.path}/candidate')
      ..createSync();
    final gifBytes = [...'GIF89a'.codeUnits, 1, 0, 1, 0, 0, 0, 0, 59];
    final gifSha256 = sha256.convert(gifBytes).toString();
    final candidateFile = File(
      '${candidateDirectory.path}/20260620212727.jma_b.gif',
    )..writeAsBytesSync(gifBytes);
    final manifestFile = File('${captureDirectory.path}/manifest.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'packageId': '20260620_iwate_offshore_m34_ref',
          'missingFrames': [
            {'observedAt': '2026-06-20T21:27:27+09:00', 'layer': 'jma_b', 'reason': 'Downloaded content is not a GIF.'},
          ],
        })}\n',
      );
    final captureManifestFile =
        File('${captureDirectory.path}/capture_manifest.json')
          ..writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert({
              'schemaVersion': 2,
              'expectedGifCount': 302,
              'downloadedGifCount': 301,
              'failedGifCount': 1,
              'records': [
                {
                  'timeJst': '2026-06-20T21:27:27',
                  'observedAt': '2026-06-20T21:27:27+09:00',
                  'cacheStatus': 'failed',
                  'layer': 'jma_b',
                  'file': '20260620212727.jma_b.gif',
                  'bytes': 0,
                  'ok': false,
                  'qualityFlags': ['missing', 'retrieval_failed'],
                  'error': 'Downloaded content is not a GIF.',
                },
              ],
            })}\n',
          );
    final decisionFile = File('${root.path}/decisions.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 'hinet_capture_provenance_review_decisions_v1',
          'cases': [
            {
              'caseId': '20260620_iwate_offshore_m34_ref',
              'decisionStatus': 'pending_capture_repair_or_exclusion',
              'reviewedAtUtc': null,
              'reviewer': null,
              'exclusionApproved': false,
              'excludedFiles': [],
              'exclusionReason': null,
              'requiredActions': ['repair_missing_gif_from_alternate_source'],
              'notes': 'unit test',
            },
          ],
        })}\n',
      );
    final inputFile = File('${root.path}/repair.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'caseId': '20260620_iwate_offshore_m34_ref', 'decisionStatus': 'capture_frame_repaired', 'reviewedAtUtc': '2026-06-26T12:00:00Z', 'reviewer': 'unit-test', 'captureDirectory': captureDirectory.path, 'candidatePath': candidateFile.path, 'expectedFileName': '20260620212727.jma_b.gif', 'expectedSha256': gifSha256, 'sourceDescription': 'unit-test local archive copy'})}\n',
      );

    return _RepairSandbox(
      root: root,
      captureDirectory: captureDirectory,
      candidateFile: candidateFile,
      inputFile: inputFile,
      decisionFile: decisionFile,
      manifestFile: manifestFile,
      captureManifestFile: captureManifestFile,
      gifBytes: gifBytes,
      gifSha256: gifSha256,
    );
  }

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
