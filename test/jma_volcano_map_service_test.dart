import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/jma_volcano_map_service.dart';

void main() {
  test(
    'keeps the volcano layer available when a state endpoint fails',
    () async {
      final service = JmaVolcanoMapService.forTesting((url) async {
        if (url.contains('volcano_list')) {
          return [
            {
              'code': '506',
              'latlon': ['31.5925', '130.6567'],
              'name_jp': '桜島',
              'name_en': 'Sakurajima',
              'levelOperation': true,
            },
          ];
        }
        if (url.contains('warning')) {
          throw Exception('temporary warning endpoint failure');
        }
        return const [];
      });
      var latestCount = 0;
      service.onSitesUpdated = (sites) => latestCount = sites.length;

      await service.fetchNow();

      expect(latestCount, 1);
      expect(service.sites, hasLength(1));
      expect(service.sites.single.code, '506');
      expect(service.sites.single.alertLevel, 0);
    },
  );
}
