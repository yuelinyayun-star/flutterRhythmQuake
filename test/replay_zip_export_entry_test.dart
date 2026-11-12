import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/debug/history_replay.dart';
import 'package:flutterrhythmquake/services/debug/history_replay_directory_io.dart';
import 'package:flutterrhythmquake/widgets/ui/history_replay_controls.dart';

class _Picker extends FilePicker {
  _Picker(this.directory);
  final Directory directory;
  String? name, title;
  List<String>? extensions;
  bool cancel = false;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    name = fileName;
    title = dialogTitle;
    extensions = allowedExtensions;
    return cancel ? null : '${directory.path}/$fileName';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FilePicker.platform = _Picker(Directory.systemTemp);
  test(
    'actual export entry writes a readable ZIP and imports original reports unchanged',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rq-zip-entry-test-',
      );
      final previous = FilePicker.platform;
      final picker = _Picker(directory);
      FilePicker.platform = picker;
      final text = File(
        'test/fixtures/history_replay/cea_202609290220.rqreplay',
      ).readAsStringSync(encoding: utf8);
      final package = HistoryReplayPackage.decode(text);
      try {
        final before = jsonEncode(
          package.reports.map((r) => r.toMap()).toList(),
        );
        expect(await exportHistoryReplay(package), isTrue);
        expect(picker.name, endsWith('.zip'));
        expect(picker.extensions, ['zip']);
        expect(picker.title, '导出回放 ZIP 压缩包');
        final path = '${directory.path}/${picker.name}';
        final input = InputFileStream(path);
        final archive = ZipDecoder().decodeStream(input);
        expect(
          archive.files.where((f) => f.name.startsWith('reports/')).length,
          package.reports.length,
        );
        final manifest =
            jsonDecode(utf8.decode(archive.find('manifest.json')!.readBytes()!))
                as Map;
        expect(manifest['layout'], 'files-v1');
        expect(manifest, isNot(contains('stationArchive')));
        await input.close();
        final imported = await importReplayFile(path);
        try {
          final originals = [
            for (final r in imported.reports)
              await imported.storedReports!.payloads[r]!.load!(),
          ];
          expect(jsonEncode(originals.map((r) => r.toMap()).toList()), before);
        } finally {
          await imported.releaseFiles?.call();
        }
        expect(
          jsonEncode(package.reports.map((r) => r.toMap()).toList()),
          before,
        );
        picker.cancel = true;
        expect(await exportHistoryReplay(package), isFalse);
      } finally {
        FilePicker.platform = previous;
        await directory.delete(recursive: true);
      }
    },
  );
}
