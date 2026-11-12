import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/epicenter_region_service.dart';
import 'package:flutterrhythmquake/services/native_japan_sea_regions.dart';
import 'package:flutterrhythmquake/utils/fe_regions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest =
      jsonDecode(
            File(
              'assets/regions/diaoyu_official_regions.provenance.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  test(
    'official names, original baseline groups and statutory width are recorded',
    () {
      expect(manifest['officialIslandCoordinates']['count'], 71);
      expect(manifest['officialBaselines']['closedGroups'], 2);
      expect(manifest['officialBaselines']['uniqueBasepoints'], 17);
      expect(manifest['territorialRule']['metres'], 22224);
      expect(
        ascii.decode(
          File(
            'assets/regions/diaoyu_baseline_regions.bin',
          ).readAsBytesSync().take(4).toList(),
        ),
        'CWR2',
      );
    },
  );
  group(
    'actual native Diaoyu lookup',
    () {
      setUpAll(() async => EpicenterRegionService.instance.load());
      test('Diaoyu detailed overrides yield to unchanged base names', () async {
        final points = [
          for (final r in manifest['regions'] as List)
            (
              (r['labelPoint'][1] as num).toDouble(),
              (r['labelPoint'][0] as num).toDouble(),
            ),
        ];
        EpicenterRegionService.instance.setResolverForTesting(null);
        final names = [for (final p in points) getFEName(p.$1, p.$2)];
        await EpicenterRegionService.instance.load();
        for (var i = 0; i < points.length; i++) {
          final p = points[i];
          expect(
            NativeJapanSeaRegions.lookup(p.$1, p.$2, domestic: true),
            isNull,
          );
          expect(EpicenterRegionService.instance.lookup(p.$1, p.$2), isNull);
          expect(getFEName(p.$1, p.$2), names[i]);
        }
      });
      test(
        'twelve-mile boundary no longer selects the detailed override',
        () async {
          final points = [
            (25.923163609888086, 124.78347141460677),
            (25.923163518220168, 124.78353130506828),
          ];
          EpicenterRegionService.instance.setResolverForTesting(null);
          final names = [for (final p in points) getFEName(p.$1, p.$2)];
          await EpicenterRegionService.instance.load();
          for (var i = 0; i < points.length; i++) {
            final p = points[i];
            expect(
              NativeJapanSeaRegions.lookup(p.$1, p.$2, domestic: true),
              isNull,
            );
            expect(getFEName(p.$1, p.$2), names[i]);
          }
        },
      );
    },
    skip: NativeJapanSeaRegions.supported
        ? false
        : 'Requires Windows station-core DLL.',
  );
}
