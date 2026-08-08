import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/cenc_ir_data.dart';
import 'package:flutterrhythmquake/services/sources/nowquake_cenc_intensity_service.dart';
import 'package:flutterrhythmquake/widgets/map/cenc_ir_layer.dart';
import 'package:flutterrhythmquake/widgets/ui/unified_intensity_format.dart';

void main() {
  const sample = <String, dynamic>{
    'type': 'data',
    'eq_id': '20260711234053',
    'happen_time': '2026-07-11 23:40:53',
    'update_time': '2026-07-12 00:48:00',
    'hypocenter': '新疆阿克苏地区拜城县',
    'magnitude': 4.2,
    'depth': 10,
    'latitude': 41.740002,
    'longitude': 81.199997,
    'maxintensity': 3.8,
    'maxforecastintensity': 5.5,
    'info': '本次事件观测到仪器烈度。',
    'stations': [
      {
        'stationid': 'XJ_N0023',
        'name': 'N0023',
        'latitude': 41.72,
        'longitude': 81.31,
        'int': 3.8,
        'pga': 12.4,
        'pgv': 0.8,
      },
    ],
    'forecast': 'compressed-data-is-not-a-contour',
  };

  test('maps NowQuake detail into the existing CENC intensity model', () {
    final data = CencIrData.fromNowQuakeJson(sample);

    expect(data.reportId, '20260711234053');
    expect(data.uniEventId, '20260711234053');
    expect(data.oriTime, DateTime.utc(2026, 7, 11, 15, 40, 53));
    expect(data.gmtCreate, DateTime.utc(2026, 7, 11, 16, 48));
    expect(data.locName, '新疆阿克苏地区拜城县');
    expect(data.epiLat, closeTo(41.740002, 0.000001));
    expect(data.epiLon, closeTo(81.199997, 0.000001));
    expect(data.focDepth, 10);
    expect(data.contourGeojson, isNull);
    expect(data.instrumentIntensities, hasLength(1));
    expect(data.instrumentIntensities.single.stationName, 'N0023');
    expect(data.instrumentIntensities.single.intensity, 3.8);
    expect(data.instrumentIntensities.single.pga, 12.4);
    expect(data.instrumentIntensities.single.pgv, 0.8);
  });

  test('normalizes a NowQuake summary for the existing CENC IR list', () {
    final summary = NowQuakeCencIntensityService.summaryFromJson(sample);

    expect(summary['id'], '20260711234053');
    expect(summary['uniEventId'], '20260711234053');
    expect(summary['oriTime'], '2026-07-11 23:40:53');
    expect(summary['locName'], '新疆阿克苏地区拜城县');
    expect(summary['magnitude'], 4.2);
    expect(summary['maxIntensity'], 3.8);
    expect(summary['_source'], 'nowquake');
  });

  test('builds a realtime unified information event for the UI', () {
    final event = NowQuakeCencIntensityService.unifiedInfoFromJson(sample);

    expect(event, isNotNull);
    expect(event!.source, 'nowQuakeCencIr');
    expect(event.eventId, '20260711234053');
    expect(event.isEew, isFalse);
    expect(event.titleText, '中国地震台网烈度速报');
    expect(event.apiTypeLabel, 'NowQuake');
    expect(event.hypocenter, '新疆阿克苏地区拜城县');
    expect(event.originTime, DateTime(2026, 7, 11, 23, 40, 53));
    expect(event.reportTime, DateTime(2026, 7, 12, 0, 48));
    expect(event.magnitude, 4.2);
    expect(event.maxIntensity, '3.8');
  });

  test('falls back to station intensity for the realtime UI event', () {
    final withoutSummaryIntensity = Map<String, dynamic>.from(sample)
      ..remove('maxintensity');
    final event = NowQuakeCencIntensityService.unifiedInfoFromJson(
      withoutSummaryIntensity,
    );

    expect(event, isNotNull);
    expect(event!.maxIntensity, '3.8');
  });

  test('scales CENC station markers with the NIED overview curve', () {
    expect(cencIrStationRadiusForZoom(3.2), 8.0);
    expect(cencIrStationRadiusForZoom(5.1), 9.0);
    expect(cencIrStationRadiusForZoom(7.0), 10.0);
    expect(cencIrStationRadiusForZoom(10.0), 10.0);
  });

  test('keeps multi-character Roman labels readable', () {
    expect(cencIrRomanFontSize(8.0, 1), closeTo(10.72, 0.001));
    expect(cencIrRomanFontSize(8.0, 2), closeTo(8.64, 0.001));
    expect(cencIrRomanFontSize(8.0, 3), closeTo(7.2, 0.001));
    expect(cencIrRomanFontSize(8.0, 4), 6.4);
  });

  test('rounds unified UI intensity to the same CSIS level as the map', () {
    expect(unifiedRomanIntensityLabel('9.9'), 'X');
    expect(unifiedRomanIntensityLabel('9.4'), 'IX');
  });
}
