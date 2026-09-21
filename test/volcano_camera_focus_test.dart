import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/volcano_event_data.dart';
import 'package:flutterrhythmquake/widgets/map/desktop_event_camera_focus.dart';
import 'package:flutterrhythmquake/widgets/map/volcano_info_focus.dart';
import 'package:latlong2/latlong.dart';

// Reuse the Sakurajima coordinates in the WHEWS adapter regression case.
final volcano = VolcanoEventData.fromMap(const {
  'kindCode': 'VFVO52',
  'volcanoCode': '506',
  'volcanoName': '桜島',
  'latitude': 31.5925,
  'longitude': 130.6567,
});

void main() {
  final event = UnifiedQuakeData.empty.copyWith(
    source: 'whews_va',
    eventId: 'VFVO52-camera',
    volcanoEvent: volcano,
  );

  test('volcano with nested coordinates is a camera candidate', () {
    final candidate = DesktopCameraCandidate.fromEvent(event, index: 1)!;
    expect(candidate.location, const LatLng(31.5925, 130.6567));
    expect(candidate.isVolcano, isTrue);
    expect(candidate.stationPoints, isEmpty);
    expect(volcanoInfoFocusPoints(volcano), [candidate.location]);
  });

  test('nearby earthquake retention does not swallow the volcano turn', () {
    final eruption = DesktopCameraCandidate.fromEvent(event, index: 1)!;
    final earthquake = DesktopCameraCandidate(
      key: 'earthquake',
      index: 0,
      location: eruption.location,
    );
    final selector = DesktopEventCameraFocus();
    for (final index in [0, 1, 0, 1]) {
      expect(
        selector
            .select(
              candidates: [earthquake, eruption],
              requestedIndex: index,
              isVisible: (_) => true,
            )!
            .index,
        index,
      );
    }
  });

  test('station report does not take over a volcano within its extent', () {
    final eruption = DesktopCameraCandidate.fromEvent(event, index: 1)!;
    final selector = DesktopEventCameraFocus();
    final area = DesktopCameraCandidate(
      key: 'station-report',
      index: 0,
      location: eruption.location,
      stationPoints: const [LatLng(31, 130), LatLng(32, 131)],
    );
    expect(
      selector.select(
        candidates: [area, eruption],
        requestedIndex: 1,
        isVisible: (_) => true,
      ),
      same(eruption),
    );
  });

  test('missing coordinates do not create a made-up volcano location', () {
    final noLocation = UnifiedQuakeData.empty.copyWith(
      volcanoEvent: VolcanoEventData.fromMap(const {'kindCode': 'VFVO52'}),
    );
    expect(DesktopCameraCandidate.fromEvent(noLocation, index: 0), isNull);
    expect(volcanoInfoFocusPoints(noLocation.volcanoEvent!), isEmpty);
  });

  test('camera fits only the current ashfall window, not expired polygons', () {
    final now = DateTime.utc(2026, 8, 7, 12);
    VolcanoAshfallWindow window(DateTime start, DateTime end) =>
        VolcanoAshfallWindow(
          label: 'camera geometry test',
          startTime: start,
          endTime: end,
          items: const [
            VolcanoAshfallItem(
              phenomenon: '',
              phenomenonCode: '',
              areaNames: [],
              areaCodes: [],
              plumeDirection: '',
              polygons: [
                [
                  VolcanoAshfallCoordinate(latitude: 31.6, longitude: 130.7),
                  VolcanoAshfallCoordinate(latitude: 31.7, longitude: 130.8),
                ],
              ],
            ),
          ],
        );
    final active = volcano.copyWith(
      ashfallWindows: [
        window(
          now.subtract(const Duration(hours: 1)),
          now.add(const Duration(hours: 1)),
        ),
      ],
    );
    expect(volcanoInfoFocusPoints(active, now: now), [
      const LatLng(31.5925, 130.6567),
      const LatLng(31.6, 130.7),
      const LatLng(31.7, 130.8),
    ]);
    expect(
      volcanoInfoFocusPoints(active, now: now.add(const Duration(hours: 2))),
      [const LatLng(31.5925, 130.6567)],
    );
  });
}
