import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/fdsn_intensity.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_channel_sensitivity.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';

void main() {
  test(
    'all codec samples match independent ObsPy/libmseed, both byte orders',
    () {
      final records =
          jsonDecode(
                File(
                  'test/fixtures/fdsn_codec/expected.json',
                ).readAsStringSync(),
              )
              as List;
      for (final record in records) {
        final bytes = File(
          'test/fixtures/fdsn_codec/${record['file']}',
        ).readAsBytesSync();
        final offset = record['offset'] as int;
        expect(
          decodeFdsnRecordForTest(
            Uint8List.sublistView(bytes, offset, offset + 512),
          ),
          record['samples'],
          reason: '${record['file']} @ $offset',
        );
      }
    },
  );

  test('metric allocation optimization retains input and amplitude units', () {
    final samples = [-200, -100, 0, 100, 200];
    final metrics = fdsnMetricsForTest(samples, 100, 1000, 'M/S**2');
    expect(samples, [-200, -100, 0, 100, 200]);
    expect(metrics['pga'], closeTo(20, 1e-10));
    expect(metrics['pgv'], closeTo(0.3, 1e-10));
    expect(metrics['mmi'], isNotNull);
  });

  test('MMI remains separate; CSIS uses SI PGA and PGV, never MMI as CSIS', () {
    expect(FdsnIntensity.parseScale(null), FdsnIntensityScale.mmi);
    expect(FdsnIntensity.parseScale('csis'), FdsnIntensityScale.csis);
    expect(
      FdsnIntensity.estimateCsis(pgaGal: 10, pgvCms: 1),
      closeTo(3.595, 1e-9),
    );
    expect(
      FdsnIntensity.estimateCsis(pgaGal: 100, pgvCms: 10),
      closeTo(6.77, 1e-9),
    );
    expect(
      FdsnIntensity.displayLevel(FdsnIntensityScale.csis, mmi: 10),
      isNull,
    );
    expect(FdsnIntensity.displayLevel(FdsnIntensityScale.mmi, mmi: 5.9), 6);
    expect(FdsnIntensity.estimateCsis(pgaGal: double.nan, pgvCms: 10), isNull);
    expect(FdsnIntensity.estimateCsis(pgaGal: 0, pgvCms: 10), isNull);
    expect(FdsnIntensity.estimateCsis(pgaGal: 1e20, pgvCms: 1e20), 12);
  });

  test(
    'MMI display rounds to nearest without changing the continuous value',
    () {
      final cases = <double, int>{
        1: 1,
        1.49: 1,
        1.5: 2,
        1.8: 2,
        2.49: 2,
        2.5: 3,
        2.58: 3,
        2.99: 3,
        3.09: 3,
        9.5: 10,
        10: 10,
        11: 10,
      };
      for (final entry in cases.entries) {
        expect(
          FdsnIntensity.displayLevel(FdsnIntensityScale.mmi, mmi: entry.key),
          entry.value,
          reason: 'MMI ${entry.key}',
        );
      }
      for (final value in <double?>[null, double.nan, double.infinity, -1, 0]) {
        expect(
          FdsnIntensity.displayLevel(FdsnIntensityScale.mmi, mmi: value),
          isNull,
        );
      }
      final metrics = fdsnMetricsForTest(
        [-200, -100, 0, 100, 200],
        100,
        1000,
        'M/S**2',
      );
      final before = Map<String, double?>.of(metrics);
      FdsnIntensity.displayLevel(FdsnIntensityScale.mmi, mmi: metrics['mmi']);
      expect(metrics, before);
    },
  );

  test('channel text matches exact NSLC and epoch, not first historical gain', () {
    const text =
        '#Network|Station|Location|Channel|Latitude|Longitude|Elevation|Depth|Azimuth|Dip|SensorDescription|Scale|ScaleFreq|ScaleUnits|SampleRate|StartTime|EndTime\n'
        'GE|WLF||BHZ|49.6646|6.1526|295|80|0|-90|STS-2|603178500|0.02|M/S|20|1999-12-21T00:00:00|2012-12-07T18:00:00\n'
        'GE|WLF||BHZ|49.6646|6.1526|295|80|0|-90|STS-2|2516580000|0.02|M/S|20|2012-12-07T18:00:00|\n';
    final current = FdsnChannelSensitivity.parse(
      text,
      network: 'GE',
      station: 'WLF',
      location: '',
      channel: 'BHZ',
      time: DateTime.utc(2026, 9, 9),
    );
    expect(current!.sensitivity, 2516580000);
    expect(
      FdsnChannelSensitivity.parse(
        text,
        network: 'GE',
        station: 'WLF',
        location: '00',
        channel: 'BHZ',
        time: DateTime.utc(2026),
      ),
      isNull,
    );
    expect(
      FdsnChannelSensitivity.parse(
        text,
        network: 'GE',
        station: 'WLF',
        location: '',
        channel: 'BHZ',
        time: DateTime.utc(2012, 12, 7, 18),
      )!.sensitivity,
      2516580000,
    );
  });
}
