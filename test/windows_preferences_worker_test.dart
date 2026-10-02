import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/windows_preferences_worker.dart';
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  late Directory directory;
  late WindowsPreferencesWorker worker;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rq-prefs-worker-');
    worker = await WindowsPreferencesWorker.start(directory.path);
  });
  tearDown(() async {
    await worker.close();
    await directory.delete(recursive: true);
  });

  test('existing UTF-8 preferences stay in the original file format', () async {
    final original = File(
      'test/fixtures/whews_nied/observations.json',
    ).readAsStringSync();
    final values = {'flutter.station_json': original, 'external': 'preserve'};
    final file = File('${directory.path}/shared_preferences.json');
    await file.writeAsString(jsonEncode(values));
    expect(await worker.getAll(), {'flutter.station_json': original});
    expect(
      await worker.setValue('Bool', 'flutter.show_estimated_epicenter', true),
      isTrue,
    );
    expect(jsonDecode(await file.readAsString()), {
      ...values,
      'flutter.show_estimated_epicenter': true,
    });
    await worker.close();
    worker = await WindowsPreferencesWorker.start(directory.path);
    expect(await worker.getAll(), {
      'flutter.station_json': original,
      'flutter.show_estimated_epicenter': true,
    });
  });

  test('queued writes retain ordering and preserve every value', () async {
    final writes = [
      worker.setValue('Bool', 'flutter.enabled', true),
      worker.setValue('Double', 'flutter.map_view_lat', 29.36),
      worker.setValue('Int', 'flutter.sensitivity', 2),
      worker.setValue('StringList', 'flutter.sources', <String>[
        'NIED',
        'LPGM',
      ]),
      worker.setValue('Int', 'flutter.sensitivity', 3),
    ];
    expect(await Future.wait(writes), everyElement(isTrue));
    expect(await worker.getAll(), {
      'flutter.enabled': true,
      'flutter.map_view_lat': 29.36,
      'flutter.sensitivity': 3,
      'flutter.sources': ['NIED', 'LPGM'],
    });
    expect(await worker.remove('flutter.enabled'), isTrue);
    expect((await worker.getAll()).containsKey('flutter.enabled'), isFalse);
  });

  test('prefix and allow-list filters match the Windows backend', () async {
    await worker.setValue('String', 'flutter.keep', '保留');
    await worker.setValue('String', 'flutter.remove', '削除');
    await worker.setValue('String', 'external.keep', 'preserve');
    expect(
      await worker.getAllWithParameters(
        GetAllParameters(
          filter: PreferencesFilter(
            prefix: 'flutter.',
            allowList: {'flutter.keep'},
          ),
        ),
      ),
      {'flutter.keep': '保留'},
    );
    await worker.clearWithParameters(
      ClearParameters(
        filter: PreferencesFilter(
          prefix: 'flutter.',
          allowList: {'flutter.remove'},
        ),
      ),
    );
    expect(await worker.getAll(), {'flutter.keep': '保留'});
    await worker.clear();
    expect(await worker.getAll(), isEmpty);
    expect(await worker.getAllWithPrefix('external.'), {
      'external.keep': 'preserve',
    });
  });

  test(
    'closed workers reject requests instead of pretending to save',
    () async {
      await worker.close();
      await expectLater(
        worker.setValue('Int', 'flutter.sensitivity', 2),
        throwsStateError,
      );
    },
  );

  test('invalid original JSON is reported and is not overwritten', () async {
    final file = File('${directory.path}/shared_preferences.json');
    await file.writeAsString('{bad json');
    await expectLater(worker.getAll(), throwsStateError);
    expect(await file.readAsString(), '{bad json');
  });
}
