import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../models/quake_message.dart';
import '../../models/unified_quake_data.dart';
import 'wave_layer.dart';

String unifiedMapLayerKey({
  required QuakeSourceType source,
  required String? eventId,
  required bool isEew,
  required int index,
}) {
  final id = eventId == null || eventId.isEmpty ? 'noid_$index' : eventId;
  final eventType = isEew ? 'eew' : 'info';
  // Preserve state between reports, and keep EEW distinct from information.
  return '${source.name}_${eventType}_$id';
}

/// The existing automatic EEW/information rendering path. Manual selection
/// remains in HistoryMarkerLayer; grids, product data and cameras live elsewhere.
class UnifiedEventWaveLayers extends StatelessWidget {
  const UnifiedEventWaveLayers({
    super.key,
    required this.events,
    required this.mapEvents,
    required this.waveColor,
    required this.blinkOn,
    this.userPosition,
  });
  final List<UnifiedQuakeData> events;
  final List<QuakeMessage> mapEvents;
  final Color Function(String) waveColor;
  final bool blinkOn;
  final LatLng? userPosition;

  bool _product(UnifiedQuakeData event) =>
      event.source == 'usgsDyfi' || event.source == 'usgsShakeMap';

  bool _separateSymbol(UnifiedQuakeData event, QuakeMessage mapped) =>
      event.isVolcanoEvent ||
      mapped.source == QuakeSourceType.fssnCmt ||
      mapped.source == QuakeSourceType.cencCmt ||
      mapped.source == QuakeSourceType.usgsCmt ||
      mapped.source == QuakeSourceType.jmaCmt ||
      mapped.source == QuakeSourceType.fnetCmt ||
      mapped.source == QuakeSourceType.hinetAquaCmt;

  @override
  Widget build(BuildContext context) {
    final count = math.min(events.length, mapEvents.length);
    final layers = <Widget>[];
    // An ordinary report and its supplemental products share one epicenter.
    // Keep the existing ordinary report key/state; different event IDs remain.
    final ordinaryKeys = <String>{
      for (var i = 0; i < count; i++)
        if (!_product(events[i]) && !_separateSymbol(events[i], mapEvents[i]))
          unifiedMapLayerKey(
            source: mapEvents[i].source,
            eventId: events[i].eventId,
            isEew: events[i].isEew,
            index: i,
          ),
    };
    final productKeys = <String>{};
    for (var i = 0; i < count; i++) {
      final u = events[i];
      final qm = mapEvents[i];
      if (_separateSymbol(u, qm)) continue;
      final key = unifiedMapLayerKey(
        source: qm.source,
        eventId: u.eventId,
        isEew: u.isEew,
        index: i,
      );
      if (_product(u) &&
          (ordinaryKeys.contains(key) || !productKeys.add(key))) {
        continue;
      }
      layers.add(
        IgnorePointer(
          child: QuakeWaveLayer(
            key: ValueKey('unified_$key'),
            event: qm,
            showWaves: u.isEew,
            showEpicenterLabel: qm.source != QuakeSourceType.sasmex,
            userPosition: userPosition,
            colorMode: SWaveColorMode.intensity,
            blinkOn: u.isEew ? blinkOn : true,
            sWaveColor: waveColor(u.className),
          ),
        ),
      );
    }
    return Stack(children: layers);
  }
}
