import 'package:latlong2/latlong.dart';

import 'palert_service.dart';

/// Retains only immutable station identity and original coordinates.
/// Observation updates do not require rebuilding the neighbour topology.
class PAlertStationLayout {
  List<({String id, LatLng coordinate})> _entries = const [];

  bool matches(List<PAlertStation> stations) {
    if (stations.length != _entries.length) return false;
    for (var i = 0; i < stations.length; i++) {
      final station = stations[i];
      final previous = _entries[i];
      if (station.id != previous.id ||
          station.coordinate.latitude != previous.coordinate.latitude ||
          station.coordinate.longitude != previous.coordinate.longitude) {
        return false;
      }
    }
    return true;
  }

  void replace(List<PAlertStation> stations) {
    _entries = [
      for (final station in stations)
        (id: station.id, coordinate: station.coordinate),
    ];
  }

  void clear() => _entries = const [];
}
