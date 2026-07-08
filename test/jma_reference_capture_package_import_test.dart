import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/import_jma_reference_capture_package.dart';

void main() {
  test(
    'JMA reference capture importer validates and dry-run does not mutate',
    () {
      final workspace = Directory.systemTemp.createTempSync(
        'jma_reference_capture_import_',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));

      final manifestFile = _writeCandidateManifest(workspace);
      final captureDirectory = _writeCapturePackage(workspace);
      final inputFile = _writeInput(
        workspace,
        captureDirectory: captureDirectory,
      );

      final result = importJmaReferenceCapturePackage(
        manifestFile: manifestFile,
        inputFile: inputFile,
        dryRun: true,
      );

      expect(result['status'], 'pass');
      expect(result['errors'], isEmpty);
      expect(result['dryRun'], isTrue);

      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      final event = ((manifest['events'] as List).single as Map)
          .cast<String, Object?>();
      expect(event['status'], 'pending_capture_association');
      expect(event['captureDirectory'], isNull);
      expect(event['captureAssociation'], isNull);
    },
  );

  test('JMA reference capture importer writes association only', () {
    final workspace = Directory.systemTemp.createTempSync(
      'jma_reference_capture_import_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));

    final manifestFile = _writeCandidateManifest(workspace);
    final captureDirectory = _writeCapturePackage(workspace);
    final inputFile = _writeInput(
      workspace,
      captureDirectory: captureDirectory,
    );

    final result = importJmaReferenceCapturePackage(
      manifestFile: manifestFile,
      inputFile: inputFile,
    );

    expect(result['status'], 'pass');
    expect(result['finalCatalogTruth'], isFalse);
    expect(result['splitAssignmentAllowed'], isFalse);

    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    final event = ((manifest['events'] as List).single as Map)
        .cast<String, Object?>();
    expect(event['status'], 'capture_associated_pending_final_catalog');
    expect(
      event['captureDirectory'],
      captureDirectory.path.replaceAll('\\', '/'),
    );
    expect(
      event['truthQuality'],
      'jma_source_and_intensity_reference_pending_final_catalog',
    );
    expect(event['eventLabels'], contains('reference_only'));
    expect(event['eventLabels'], contains('pending_capture'));

    final association = (event['captureAssociation'] as Map)
        .cast<String, Object?>();
    expect(association['reviewer'], 'test-reviewer');
    expect(association['finalCatalogTruth'], isFalse);
    expect(association['splitAssignmentAllowed'], isFalse);
  });

  test('JMA reference capture importer rejects unsafe or stale inputs', () {
    final workspace = Directory.systemTemp.createTempSync(
      'jma_reference_capture_import_',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));

    final manifestFile = _writeCandidateManifest(workspace);
    final captureDirectory = _writeCapturePackage(workspace);
    final inputFile = _writeInput(
      workspace,
      captureDirectory: captureDirectory,
      overrides: {'reviewer': '<fill-reviewer>', 'cookie': 'do-not-store'},
    );

    final result = importJmaReferenceCapturePackage(
      manifestFile: manifestFile,
      inputFile: inputFile,
      dryRun: true,
    );

    expect(result['status'], 'fail');
    expect(
      result['errors'],
      containsAll([
        'input_contains_sensitive_auth_material',
        'unresolved_placeholder:reviewer',
      ]),
    );
  });
}

File _writeCandidateManifest(Directory workspace) {
  final file = File('${workspace.path}/jma_reference_event_candidates.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'datasetId': 'jma_reference_event_candidates_v1',
      'events': [
        {
          'eventId': 'sample_jma_reference_event',
          'originTimeJst': '2026-06-26T23:17:46+09:00',
          'source': 'jma_source_and_intensity_information',
          'truthQuality': 'jma_source_and_intensity_reference_pending_final_catalog',
          'status': 'pending_capture_association',
          'captureDirectory': null,
          'eventLabels': ['reference_only', 'pending_capture'],
        },
      ],
    })}\n',
  );
  return file;
}

Directory _writeCapturePackage(Directory workspace) {
  final directory = Directory('${workspace.path}/capture_package')
    ..createSync();
  Directory('${directory.path}/frames').createSync();
  File('${directory.path}/frames/index.json').writeAsStringSync('[]\n');
  File('${directory.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'packageId': 'sample_jma_reference_capture',
      'frameIndexPath': 'frames/index.json',
      'layers': ['jma_s', 'jma_b'],
    })}\n',
  );
  return directory;
}

File _writeInput(
  Directory workspace, {
  required Directory captureDirectory,
  Map<String, Object?> overrides = const {},
}) {
  final input = <String, Object?>{
    'eventId': 'sample_jma_reference_event',
    'status': 'capture_associated_pending_final_catalog',
    'reviewedAtUtc': '2026-06-26T15:00:00Z',
    'reviewer': 'test-reviewer',
    'captureDirectory': captureDirectory.path,
    'manifestPath': '${captureDirectory.path}/manifest.json',
    'packageSource': 'local reviewed replay package',
    'associationReason': 'event time and package manifest match',
    ...overrides,
  };
  final file = File('${workspace.path}/capture_association_input.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(input)}\n',
  );
  return file;
}
