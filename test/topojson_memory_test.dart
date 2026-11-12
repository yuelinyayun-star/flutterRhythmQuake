import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/topojson_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (source, path, load) in [
    ('cn', 'assets/maps/cn.eew.topo.json', TopoJsonLoader.loadCnEew),
    ('jp', 'assets/maps/jp.eew.topo.json', TopoJsonLoader.loadJpEew),
    ('kr', 'assets/maps/kr.eew.topo.json', TopoJsonLoader.loadKrEew),
    (
      'jp_tsunami',
      'assets/maps/jp.tsunami.topo.json',
      TopoJsonLoader.loadJpTsunami,
    ),
  ]) {
    testWidgets(
      '$source concurrent layers share original geometry without retaining raw text',
      (tester) async {
        await tester.runAsync(() async {
          final raw = File(path).readAsBytesSync();
          var reads = 0;
          TopoJsonLoader.clearCache();
          rootBundle.evict(path);
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMessageHandler('flutter/assets', (message) async {
            final requested = utf8.decode(
              message!.buffer.asUint8List(
                message.offsetInBytes,
                message.lengthInBytes,
              ),
            );
            if (requested != path) return null;
            reads++;
            return ByteData.sublistView(raw);
          });
          addTearDown(() {
            messenger.setMockMessageHandler('flutter/assets', null);
            rootBundle.evict(path);
            TopoJsonLoader.clearCache();
          });
          final futures = [for (var i = 0; i < 20; i++) load()];
          for (final future in futures) {
            expect(identical(future, futures.first), isTrue);
          }
          final loaded = await Future.wait(futures);
          expect(reads, 1);
          expect(loaded.first, isNotNull);
          for (final data in loaded) {
            expect(identical(data, loaded.first), isTrue);
          }
          expect(identical(await load(), loaded.first), isTrue);
          expect(reads, 1);
          final original = TopoJsonLoader.parse(
            utf8.decode(raw),
            source: source,
          )!;
          Object coordinates(TopoJsonData data) => [
            for (final r in data.regions)
              [
                r.name,
                r.code,
                r.center?.latitude,
                r.center?.longitude,
                [
                  for (final ring in r.polygons)
                    [
                      for (final p in ring) [p.latitude, p.longitude],
                    ],
                ],
                [
                  for (final line in r.lines)
                    [
                      for (final p in line) [p.latitude, p.longitude],
                    ],
                ],
              ],
          ];
          expect(coordinates(loaded.first!), coordinates(original));
          expect(await rootBundle.loadString(path), utf8.decode(raw));
          expect(
            reads,
            2,
            reason: 'Parsed geometry must not leave an AssetBundle text cache',
          );
          expect(File(path).readAsBytesSync(), raw);
        });
      },
    );
  }
}
