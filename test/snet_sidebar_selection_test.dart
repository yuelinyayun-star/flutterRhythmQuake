import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/snet_station.dart';
import 'package:flutterrhythmquake/widgets/ui/station_dashboard.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';
import 'package:latlong2/latlong.dart';

void main() {
  SnetStation station(String code, double shindo, {bool active = true}) {
    return SnetStation(
      code: code,
      name: code,
      coordinate: const LatLng(0, 0),
      depth: 1000,
      network: '0120A',
      type: 'acceleration',
      shindo: shindo,
      level: 0,
      isActive: active,
    );
  }

  test('does not open S-net page when maximum JMA intensity is zero', () {
    final selected = selectSnetSidebarTopStations([
      station('A', 0.49),
      station('B', 0.3),
      station('C', 0.0),
    ]);

    expect(selected, isEmpty);
  });

  test('fills top five with intensity-zero stations after triggering', () {
    final selected = selectSnetSidebarTopStations([
      station('F', 0.0),
      station('C', 0.3),
      station('A', 0.8),
      station('E', 0.1),
      station('B', 0.4),
      station('D', 0.2),
    ]);

    expect(selected.map((station) => station.code), ['A', 'B', 'C', 'D', 'E']);
    expect(selected.map((station) => station.jmaIndex), [1, 0, 0, 0, 0]);
  });

  test('ignores inactive stations when deciding whether to open', () {
    final selected = selectSnetSidebarTopStations([
      station('A', 2.0, active: false),
      station('B', 0.4),
      station('C', 0.3),
    ]);

    expect(selected, isEmpty);
  });

  test(
    'bounded selection preserves the full-sort ordering and source values',
    () {
      final input = [
        station('trigger', .5),
        station('zero', 0.0),
        station('negative-zero', -0.0),
        station('nan', double.nan),
        station('infinity', double.infinity),
        station('invalid-level', 7)..level = -1,
        station('inactive', 7, active: false),
        station('B', .5),
        station('A', .5),
        station('negative', -3),
      ];
      for (var offset = 0; offset < input.length; offset++) {
        final ordered = [...input.skip(offset), ...input.take(offset)];
        final expected =
            ordered
                .where((s) => s.isActive && s.level >= 0 && s.shindo.isFinite)
                .toList()
              ..sort((a, b) {
                final order = b.shindo.compareTo(a.shindo);
                return order != 0 ? order : a.code.compareTo(b.code);
              });
        var iterations = 0;
        Iterable<SnetStation> once() sync* {
          expect(++iterations, 1);
          yield* ordered;
        }

        final actual = selectSnetSidebarTopStations(once());
        expect(actual.map((s) => s.code), expected.take(5).map((s) => s.code));
        for (var i = 0; i < actual.length; i++) {
          expect(actual[i].shindo.compareTo(expected[i].shindo), 0);
          expect(
            actual[i].jmaIndex,
            JpShindoScale.jmaIndexFromShindo(expected[i].shindo),
          );
        }
        expect(
          ordered.map((s) => s.code),
          [...input.skip(offset), ...input.take(offset)].map((s) => s.code),
        );
      }
      expect(input[1].shindo.isNegative, isFalse);
      expect(input[2].shindo.isNegative, isTrue);
      expect(input[3].shindo.isNaN, isTrue);
    },
  );

  test(
    'empty input and fewer than five valid stations retain their meaning',
    () {
      expect(selectSnetSidebarTopStations(const []), isEmpty);
      final selected = selectSnetSidebarTopStations([
        station('B', 0),
        station('A', 1),
      ]);
      expect(selected.map((s) => s.code), ['A', 'B']);
    },
  );

  test('TREM dashboard preserves weak and strong JMA classes', () {
    expect(tremDashboardShindoLabel(4.6), '5-');
    expect(tremDashboardShindoLabel(5.1), '5+');
    expect(tremDashboardShindoLabel(5.6), '6-');
    expect(tremDashboardShindoLabel(6.1), '6+');
  });
}
