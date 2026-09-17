import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DesktopCameraCandidate {
  final String key;
  final int index;
  final LatLng location;
  final List<LatLng> stationPoints;

  const DesktopCameraCandidate({
    required this.key,
    required this.index,
    required this.location,
    this.stationPoints = const [],
  });
}

/// Chooses a camera owner, without merging or removing any source events.
class DesktopEventCameraFocus {
  String? _ownerKey;

  void reset() => _ownerKey = null;

  DesktopCameraCandidate? select({
    required List<DesktopCameraCandidate> candidates,
    required int requestedIndex,
    required bool Function(LatLng) isVisible,
  }) {
    if (candidates.isEmpty) {
      reset();
      return null;
    }
    DesktopCameraCandidate? owner;
    DesktopCameraCandidate? requested;
    for (final candidate in candidates) {
      if (candidate.key == _ownerKey) owner = candidate;
      if (candidate.index == requestedIndex) requested = candidate;
    }
    var selected = requested ?? owner ?? candidates.first;
    // Use the animation destination, not a transient camera frame.
    if (owner != null &&
        !(selected.stationPoints.length > 1 &&
            owner.stationPoints.length < 2) &&
        isVisible(owner.location) &&
        isVisible(selected.location)) {
      selected = owner;
    }
    if (selected.stationPoints.length < 2) {
      // Prefer an active station report covering this epicenter, even when the
      // corresponding bulletin arrives before the first camera fit ends.
      for (final candidate in candidates) {
        if (candidate.stationPoints.length > 1 &&
            LatLngBounds.fromPoints(
              candidate.stationPoints,
            ).contains(selected.location)) {
          selected = candidate;
          break;
        }
      }
    }
    _ownerKey = selected.key;
    return selected;
  }
}
