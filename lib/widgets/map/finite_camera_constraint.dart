import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

/// Rejects camera updates that contain invalid numeric values.
///
/// `flutter_map` applies [CameraConstraint] before committing a camera update.
/// Returning `null` here leaves the last valid camera in place, which prevents
/// an invalid multi-touch frame from reaching tile projection.
@immutable
class FiniteCameraConstraint extends CameraConstraint {
  const FiniteCameraConstraint();

  @override
  MapCamera? constrain(MapCamera camera) {
    final center = camera.center;
    if (!center.latitude.isFinite ||
        !center.longitude.isFinite ||
        !camera.zoom.isFinite ||
        !camera.rotation.isFinite) {
      return null;
    }
    return camera;
  }
}
