import 'package:latlong2/latlong.dart';

/// A single camera target for all currently detected networks. Inputs are
/// confirmed grid centers (or the network's existing confirmed focus points),
/// never the full station inventory.
class StationDetectionFocus {
  StationDetectionFocus(Map<String, List<LatLng>> networks) {
    sources = networks.keys.where((key) => networks[key]!.isNotEmpty).toList()
      ..sort();
    points = sources.expand((key) => networks[key]!).toSet().toList()
      ..sort((a, b) {
        final latitude = a.latitude.compareTo(b.latitude);
        return latitude != 0 ? latitude : a.longitude.compareTo(b.longitude);
      });
  }

  late final List<String> sources;
  late final List<LatLng> points;

  bool get isCombined => sources.length > 1;
  double get minZoom => isCombined ? 1.0 : 4.5;
  String get sourceTag => 'policy-${sources.join('-')}-station';
  String get signature =>
      '$sourceTag:${points.map((point) => '${point.latitude},${point.longitude}').join('|')}';
}
