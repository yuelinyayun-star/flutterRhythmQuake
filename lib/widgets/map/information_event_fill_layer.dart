import 'package:flutter/material.dart';

import '../../core/utils/topojson_loader.dart';
import '../../models/unified_event_presentation.dart';
import '../../models/unified_quake_data.dart';
import 'intensity_fill_layer.dart';
import 'jma_lpgm_station_layer.dart';
import 'jma_lpgm_region_fill_layer.dart';
import 'jma_region_value_label.dart';

/// Reusable map rendering entry point for one selected information event.
/// The caller owns the map/camera. This layer has no provider, notifications,
/// clocks or camera side effects, so an offscreen renderer can reuse it later.
/// USGS products and CENC station reports retain their existing product layers.
class InformationEventFillLayer extends StatelessWidget {
  const InformationEventFillLayer({
    super.key,
    required this.event,
    this.showLongPeriodRegions = false,
    this.onInformationGeometry,
    this.onInformationFillSummary,
  });

  final UnifiedQuakeData event;
  final bool showLongPeriodRegions;
  final ValueChanged<List<TopoJsonRegion>>? onInformationGeometry;
  final ValueChanged<InformationFillSummary>? onInformationFillSummary;

  static bool supports(UnifiedQuakeData event) =>
      !event.isEew &&
      !event.isVolcanoEvent &&
      (event.isJmaLpgm ||
          (event.rawEvent == null || event.rawEvent!.isInfoEvent) &&
              const {
                'jmaEqlist',
                'p2pJmaEqlist',
                'cwaEqlist',
                'cencEqlist',
                'kmaEqlist',
              }.contains(event.source));

  @override
  Widget build(BuildContext context) {
    if (!supports(event)) return const SizedBox.shrink();
    final lpgm = event.jmaLpgmBulletin;
    // A manual historical selection must not expire against the live clock.
    if (lpgm != null && (event.isJmaLpgm || showLongPeriodRegions)) {
      return Stack(
        children: [
          JmaLpgmRegionFillLayer(
            bulletin: lpgm,
            informationGeometryKey: event,
            onInformationGeometry: onInformationGeometry,
            onInformationFillSummary: onInformationFillSummary,
          ),
          JmaLpgmStationLayer(bulletin: lpgm),
        ],
      );
    }
    final region = switch (event.source) {
      'jmaEqlist' || 'p2pJmaEqlist' => 'jp',
      'cwaEqlist' => 'tw',
      'cencEqlist' => 'cn',
      'kmaEqlist' => 'kr',
      _ => '',
    };
    if (region.isEmpty ||
        (region == 'jp'
            ? event.warnArea.isEmpty && event.magnitude <= 0
            : event.magnitude <= 0)) {
      return const SizedBox.shrink();
    }
    final normalFill = IntensityFillLayer(
      magnitude: event.magnitude,
      depth: event.depth,
      hypoLat: event.lat ?? double.nan,
      hypoLng: event.lng ?? double.nan,
      source: region,
      mode: region == 'tw'
          ? cwaObservedFillAvailable(event)
                ? IntensityFillMode.cwaObserved
                : IntensityFillMode.cwa
          : region == 'jp' || region == 'kr'
          ? IntensityFillMode.jma
          : IntensityFillMode.csis,
      cwaForecast: region == 'tw' ? cwaForecastForEvent(event) : null,
      minIntensity: 1.0,
      opacity: 0.55,
      warnAreaJson: event.warnArea,
      showRegionValues: region == 'jp' && showJmaInformationRegionValues(event),
      informationGeometryKey: event,
      onInformationGeometry: onInformationGeometry,
      onInformationFillSummary: onInformationFillSummary,
    );
    // After the temporary long-period view, restore the ordinary intensity
    // regions while keeping the existing station overlay.
    return lpgm == null
        ? normalFill
        : Stack(
            children: [
              normalFill,
              JmaLpgmStationLayer(bulletin: lpgm),
            ],
          );
  }
}
