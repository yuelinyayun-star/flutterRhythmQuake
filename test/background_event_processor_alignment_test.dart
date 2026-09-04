import 'package:flutter_test/flutter_test.dart';

import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/background_event_processor.dart';

void main() {
  group('BackgroundEventProcessor UI alignment', () {
    test('uses source.name preference keys and the UI location whitelist', () {
      final allowed = BackgroundEventProcessor(
        sourceInfoMagFilters: const {'source_mag_filter_usgs': 5.0},
        infoActionWhitelist: '测试地区|伊豆群岛',
      );
      expect(
        allowed
            .process(
              _infoEvent(
                source: 'usgsEqlist',
                eventId: 'usgs-low-whitelist',
                magnitude: 3.0,
                hypocenter: '测试地区附近',
              ),
            )
            .type,
        BackgroundEventResultType.newEvent,
      );

      final disabled = BackgroundEventProcessor(
        sourceInfoMagFilters: const {'source_mag_filter_usgs': -1.0},
        infoActionWhitelist: '测试地区',
      );
      expect(
        disabled
            .process(
              _infoEvent(
                source: 'usgsEqlist',
                eventId: 'usgs-disabled',
                magnitude: 7.0,
                hypocenter: '测试地区附近',
              ),
            )
            .type,
        BackgroundEventResultType.dropped,
      );
    });

    test('maps jmaEqlist origin 2 to the P2P filter', () {
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {'source_mag_filter_p2p': -1.0},
      );
      final result = processor.process(
        _infoEvent(
          source: 'jmaEqlist',
          origin: 2,
          eventId: '2026-07-29 12:34:56',
          timeZone: 9,
          useShindo: true,
        ),
      );
      expect(result.type, BackgroundEventResultType.dropped);
    });

    test('compares different event ids in the same source slot', () {
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );
      final now = _sourceLocalNow(8);

      expect(
        processor
            .process(
              _infoEvent(
                eventId: 'current',
                originTime: now.subtract(const Duration(minutes: 1)),
                reportTime: now,
              ),
            )
            .type,
        BackgroundEventResultType.newEvent,
      );
      expect(
        processor
            .process(
              _infoEvent(
                eventId: 'late-old',
                originTime: now.subtract(const Duration(minutes: 5)),
                reportTime: now.subtract(const Duration(minutes: 2)),
              ),
            )
            .type,
        BackgroundEventResultType.dropped,
      );
      expect(
        processor
            .process(
              _infoEvent(
                eventId: 'newer',
                originTime: now,
                reportTime: now.add(const Duration(seconds: 1)),
              ),
            )
            .type,
        BackgroundEventResultType.newEvent,
      );
    });

    test('drops CENC information after the same five minute UI window', () {
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );
      final oldTime = _sourceLocalNow(8).subtract(const Duration(minutes: 6));
      final result = processor.process(
        _infoEvent(
          source: 'cencEqlist',
          eventId: 'old-cenc',
          originTime: oldTime,
          reportTime: oldTime,
          magnitude: 4.0,
        ),
      );
      expect(result.type, BackgroundEventResultType.dropped);
    });

    test('accepts changed no-update body and drops its exact duplicate', () {
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );
      final reportTime = _sourceLocalNow(8);
      final first = _infoEvent(
        source: 'emsc',
        eventId: 'emsc-correction',
        reportTime: reportTime,
        magnitude: 5.0,
      );
      final corrected = _infoEvent(
        source: 'emsc',
        eventId: 'emsc-correction',
        reportTime: reportTime,
        magnitude: 5.2,
      );

      expect(processor.process(first).type, BackgroundEventResultType.newEvent);
      final correctionResult = processor.process(corrected);
      expect(correctionResult.type, BackgroundEventResultType.update);
      expect(correctionResult.event?.magnitude, 5.2);
      expect(
        processor.process(corrected).type,
        BackgroundEventResultType.dropped,
      );
    });

    test('uses persisted CWA body keys across background restarts', () {
      final firstProcessor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );
      final event = _infoEvent(
        source: 'cwaEqlist',
        eventId: 'cwa-persisted',
        useShindo: true,
      );
      expect(
        firstProcessor.process(event).type,
        BackgroundEventResultType.newEvent,
      );

      final restarted = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
        seenCwaInfoBodyKeys: firstProcessor.seenCwaInfoBodyKeys,
      );
      expect(restarted.process(event).type, BackgroundEventResultType.dropped);
    });

    test('drops an information event already accepted by the main UI', () {
      final event = _infoEvent(source: 'fssnEqlist', eventId: 'main-ui-seen');
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
        seenUnifiedInfoEvents: {
          'fssnEqlist|main-ui-seen': DateTime.now().toUtc(),
        },
      );

      expect(processor.process(event).type, BackgroundEventResultType.dropped);
    });

    test('keeps the most complete JMA fields on a lower-stage update', () {
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );
      final now = _sourceLocalNow(9);
      final detailed = _infoEvent(
        source: 'jmaEqlist',
        origin: 2,
        eventId: '2026-07-29 12:34:56',
        timeZone: 9,
        titleText: '各地の震度に関する情報',
        useShindo: true,
        maxIntensity: '5+',
        hypocenter: '伊豆諸島近海',
        originTime: now.subtract(const Duration(minutes: 1)),
        reportTime: now,
        magnitude: 5.8,
        depth: 20,
        depthText: '深さ: 20km',
        lat: 34.0,
        lng: 139.0,
        warnArea: '[{"name":"東京都","intensity":"5+"}]',
      );
      final lowerStage = _infoEvent(
        source: 'jmaEqlist',
        origin: 2,
        eventId: '2026/07/29 12:34:56',
        timeZone: 9,
        titleText: '震源に関する情報',
        useShindo: true,
        maxIntensity: '不明',
        hypocenter: '',
        originTime: detailed.originTime,
        reportTime: now.add(const Duration(seconds: 1)),
        magnitude: -1,
        depth: -1,
        depthText: '',
        lat: null,
        lng: null,
        warnArea: '',
      );

      expect(
        processor.process(detailed).type,
        BackgroundEventResultType.newEvent,
      );
      final result = processor.process(lowerStage);
      expect(result.type, BackgroundEventResultType.update);
      expect(result.event?.titleText, detailed.titleText);
      expect(result.event?.maxIntensity, '5+');
      expect(result.event?.hypocenter, detailed.hypocenter);
      expect(result.event?.magnitude, detailed.magnitude);
      expect(result.event?.depth, detailed.depth);
      expect(result.event?.warnArea, detailed.warnArea);
    });

    test('drops a lower EEW report number after a newer report', () {
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );
      final report5 = _eewEvent(reportNumText: '第5报');
      final report4 = _eewEvent(reportNumText: '第4报');
      final report6 = _eewEvent(reportNumText: '第6报');

      expect(
        processor.process(report5).type,
        BackgroundEventResultType.newEvent,
      );
      expect(
        processor.process(report4).type,
        BackgroundEventResultType.dropped,
      );
      expect(processor.process(report6).type, BackgroundEventResultType.update);
    });

    test('continues the EEW report number accepted by the main UI', () {
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
        acceptedEewReportNums: const {'jmaEew|eew-test': 5},
      );

      expect(
        processor.process(_eewEvent(reportNumText: '第4报')).type,
        BackgroundEventResultType.dropped,
      );
      expect(
        processor.process(_eewEvent(reportNumText: '第5报')).type,
        BackgroundEventResultType.dropped,
      );
      final report6 = processor.process(_eewEvent(reportNumText: '第6报'));
      expect(report6.type, BackgroundEventResultType.update);
      expect(report6.isUpdate, isTrue);
      expect(processor.acceptedEewReportNums['jmaEew|eew-test'], 6);
    });

    test('follows standard multi-source EEW report ordering for CWA EEW', () {
      final processor = BackgroundEventProcessor(
        sourceInfoMagFilters: const {},
      );
      final originTime = _sourceLocalNow(
        8,
      ).subtract(const Duration(seconds: 5));
      final fan = _eewEvent(
        source: 'cwaEew',
        origin: 1,
        eventId: 'fan-cwa',
        reportNumText: '第4报',
        timeZone: 8,
        originTime: originTime,
      );
      final wolfx = _eewEvent(
        source: 'cwaEew',
        origin: 0,
        eventId: 'wolfx-cwa',
        reportNumText: '第4报',
        timeZone: 8,
        originTime: originTime,
      );
      final laterFan = _eewEvent(
        source: 'cwaEew',
        origin: 1,
        eventId: 'fan-cwa',
        reportNumText: '第5报',
        timeZone: 8,
        originTime: originTime,
      );

      expect(processor.process(fan).type, BackgroundEventResultType.newEvent);
      // Same report number from secondary source is dropped as a duplicate
      expect(processor.process(wolfx).type, BackgroundEventResultType.dropped);
      // Newer report number (Report 5) from any source successfully updates the slot
      expect(
        processor.process(laterFan).type,
        BackgroundEventResultType.update,
      );
    });
  });
}

UnifiedQuakeData _infoEvent({
  String source = 'fssnEqlist',
  int origin = 1,
  required String eventId,
  int timeZone = 8,
  String titleText = '地震信息',
  bool useShindo = false,
  String maxIntensity = '4',
  String hypocenter = '测试区域',
  DateTime? originTime,
  DateTime? reportTime,
  double magnitude = 5.0,
  double depth = 10,
  String depthText = '深度: 10km',
  double? lat = 30,
  double? lng = 120,
  String warnArea = '',
}) {
  final sourceNow = _sourceLocalNow(timeZone);
  return UnifiedQuakeData(
    source: source,
    origin: origin,
    eventId: eventId,
    isEew: false,
    timeZone: timeZone,
    titleText: titleText,
    reportNumText: '',
    useShindo: useShindo,
    maxIntensity: maxIntensity,
    className: 'green',
    hypocenter: hypocenter,
    originTime: originTime ?? sourceNow.subtract(const Duration(minutes: 1)),
    reportTime: reportTime ?? sourceNow,
    magnitude: magnitude,
    depth: depth,
    depthText: depthText,
    lat: lat,
    lng: lng,
    warnArea: warnArea,
  );
}

UnifiedQuakeData _eewEvent({
  String source = 'jmaEew',
  int origin = 1,
  String eventId = 'eew-test',
  required String reportNumText,
  int timeZone = 9,
  DateTime? originTime,
}) {
  final sourceNow = _sourceLocalNow(timeZone);
  return UnifiedQuakeData(
    source: source,
    origin: origin,
    eventId: eventId,
    isEew: true,
    timeZone: timeZone,
    titleText: '地震预警',
    reportNumText: reportNumText,
    useShindo: true,
    maxIntensity: '4',
    className: 'green',
    hypocenter: '测试区域',
    originTime: originTime ?? sourceNow.subtract(const Duration(seconds: 5)),
    reportTime: sourceNow,
    magnitude: 5.0,
    depth: 10,
    depthText: '深度: 10km',
    lat: 24,
    lng: 122,
  );
}

DateTime _sourceLocalNow(int timeZone) {
  final utc = DateTime.now().toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
    utc.microsecond,
  ).add(Duration(hours: timeZone));
}
