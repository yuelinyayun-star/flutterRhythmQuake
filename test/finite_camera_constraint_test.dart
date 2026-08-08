import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/map/finite_camera_constraint.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const constraint = FiniteCameraConstraint();

  MapCamera camera({
    required LatLng center,
    double zoom = 5,
    double rotation = 0,
  }) {
    return MapCamera(
      crs: const Epsg3857(),
      center: center,
      zoom: zoom,
      rotation: rotation,
      nonRotatedSize: const Size(360, 720),
    );
  }

  test('keeps a valid camera update', () {
    final valid = camera(center: const LatLng(35.6812, 139.7671));

    expect(identical(constraint.constrain(valid), valid), isTrue);
  });

  test('rejects a non-finite center from a multi-touch update', () {
    final invalid = camera(center: LatLng(double.nan, double.nan));

    expect(constraint.constrain(invalid), isNull);
  });

  test('rejects a non-finite rotation update', () {
    final invalidRotation = camera(
      center: const LatLng(35.6812, 139.7671),
      rotation: double.nan,
    );

    expect(constraint.constrain(invalidRotation), isNull);
  });

  testWidgets('prevents an invalid move from replacing the live map camera', (
    tester,
  ) async {
    final controller = MapController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 360,
          height: 720,
          child: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              initialCenter: LatLng(35.6812, 139.7671),
              initialZoom: 5,
              cameraConstraint: FiniteCameraConstraint(),
            ),
            children: const [],
          ),
        ),
      ),
    );
    await tester.pump();

    final originalCenter = controller.camera.center;
    final moved = controller.move(LatLng(double.nan, double.nan), 6);

    expect(moved, isFalse);
    expect(controller.camera.center, originalCenter);
  });
}
