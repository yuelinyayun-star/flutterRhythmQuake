// Frozen storage algorithm from the pre-migration NiedReplayLogger backup.
// Retains every map and pretty-serializes the cumulative payload twice/save.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class DartReplayArchiveReference {
  DartReplayArchiveReference(
    this.outputDirectory,
    this.sessionStart,
    this.stamp,
  );
  final String outputDirectory, sessionStart, stamp;
  final List<Map<String, dynamic>> frames = [];
  final List<Map<String, dynamic>> capturedGifs = [];
  String? captureDir;
  String get logPath => '$outputDirectory/nied_replay_$stamp.json';
  void capture(Map<String, dynamic> metadata, Uint8List bytes) {
    captureDir = '$outputDirectory/nied_capture_$stamp';
    final file = File('$captureDir/${metadata['path']}');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, flush: false);
    capturedGifs.add(metadata);
  }

  void append(Map<String, dynamic> record) => frames.add(record);
  void save() {
    if (frames.isEmpty) return;
    final outDir = Directory(outputDirectory);
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final payload = {
      'session_start': sessionStart,
      'written_at': DateTime.now().toIso8601String(),
      'frame_count': frames.where((f) => f['type'] == 'frame').length,
      'detection_count': frames.where((f) => f['type'] == 'detection').length,
      'epicenter_count': frames.where((f) => f['type'] == 'epicenter').length,
      'gif_capture_count': capturedGifs.length,
      'capture_directory': captureDir,
      'captured_gifs': capturedGifs,
      'frames': frames,
    };
    File(
      logPath,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
    if (captureDir != null) {
      File(
        '$captureDir/nied_replay.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
      File('$captureDir/capture_manifest.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 'nied_capture_v1',
          'createdAt': DateTime.now().toIso8601String(),
          'sessionStart': sessionStart,
          'sourceReplayPath': logPath,
          'gifCount': capturedGifs.length,
          'frames': capturedGifs,
        }),
      );
    }
  }
}
