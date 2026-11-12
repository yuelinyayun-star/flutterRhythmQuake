import 'jma_lpgm_bulletin.dart';
import 'source_payload.dart';
import 'unified_quake_data.dart';

/// Compact presentation data retained with a catalogue row. This deliberately
/// excludes timers and alert state; selecting it is not a feed. CWA retains its
/// original parameters because its existing fill reads correction/cancel flags.
class InformationMapData {
  const InformationMapData({
    required this.source,
    required this.origin,
    required this.titleText,
    this.warnArea = '',
    this.lpgm,
    this.cwaSourcePayload,
  });

  final String source;
  final int origin;
  final String titleText;
  final String warnArea;
  final JmaLpgmBulletin? lpgm;
  final Map<String, dynamic>? cwaSourcePayload;

  factory InformationMapData.fromEvent(UnifiedQuakeData event) =>
      InformationMapData(
        source: event.source,
        origin: event.origin,
        titleText: event.titleText,
        warnArea: event.warnArea,
        lpgm: event.jmaLpgmBulletin,
        cwaSourcePayload: event.source == 'cwaEqlist'
            ? event.sourcePayload
            : null,
      );

  Map<String, dynamic> toMap() => {
    'source': source,
    'origin': origin,
    'titleText': titleText,
    'warnArea': warnArea,
    if (lpgm != null) 'lpgm': lpgm!.toMap(),
    if (cwaSourcePayload != null) 'cwaSourcePayload': cwaSourcePayload,
  };

  factory InformationMapData.fromMap(Map<dynamic, dynamic> map) =>
      InformationMapData(
        source: map['source'] as String,
        origin: map['origin'] as int,
        titleText: map['titleText'] as String,
        warnArea: map['warnArea'] as String? ?? '',
        lpgm: map['lpgm'] is Map
            ? JmaLpgmBulletin.fromMap(map['lpgm'] as Map)
            : null,
        cwaSourcePayload: map['cwaSourcePayload'] is Map
            ? snapshotSourcePayload(
                Map<String, dynamic>.from(map['cwaSourcePayload'] as Map),
              )
            : null,
      );
}
