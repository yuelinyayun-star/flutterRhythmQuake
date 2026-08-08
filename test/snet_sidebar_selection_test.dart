import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/snet_station.dart';
import 'package:flutterrhythmquake/widgets/ui/station_dashboard.dart';
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

  test('TREM dashboard preserves weak and strong JMA classes', () {
    expect(tremDashboardShindoLabel(4.6), '5-');
    expect(tremDashboardShindoLabel(5.1), '5+');
    expect(tremDashboardShindoLabel(5.6), '6-');
    expect(tremDashboardShindoLabel(6.1), '6+');
  });
}
