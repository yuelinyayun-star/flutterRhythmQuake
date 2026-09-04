import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../providers/map_state_provider.dart';

/// Read current map zoom for marker/dot sizing without depending on
/// [MapCamera] InheritedWidget (which rebuilds on every continuous follow tick).
double mapStyleZoomOf(BuildContext context, {double fallback = 4.0}) {
  try {
    return context.read<MapStateProvider>().mapController?.camera.zoom ??
        fallback;
  } catch (_) {
    return fallback;
  }
}

/// Emit grid centers only when the set actually changes.
mixin GridCentersEmitMixin<T extends StatefulWidget> on State<T> {
  String? _lastGridCentersSignature;

  void emitGridCentersIfChanged(
    List<LatLng> centers,
    void Function(List<LatLng> centers)? callback,
  ) {
    if (callback == null) return;
    final signature = centers
        .map(
          (c) =>
              '${c.latitude.toStringAsFixed(3)},${c.longitude.toStringAsFixed(3)}',
        )
        .join('|');
    if (signature == _lastGridCentersSignature) return;
    _lastGridCentersSignature = signature;
    final snapshot = List<LatLng>.unmodifiable(centers);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(snapshot);
    });
  }
}
