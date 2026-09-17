import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_stream_catalog.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9, 14, 30);
  String row(String id, [String end = '2026-09-09T14:29:02.170000Z']) =>
      '$id 2026-09-09T12:48:04.060000Z $end';

  test(
    'Ringserver identifiers retain NSLC and select existing live family',
    () {
      final result = parseFdsnStreamCatalog((
        [
          row('FDSN:1E_MONT1__H_H_Z/MSEED'),
          row('FDSN:1E_MONT1__H_N_E/MSEED'),
          row('FDSN:1E_MONT1__H_N_N/MSEED'),
          row('FDSN:1E_MONT1__H_N_Z/MSEED'),
          row('FDSN:IU_ANMO_00_B_H_Z/MSEED'),
          row('FDSN:IU_ANMO_10_B_H_Z/MSEED', '2026-09-09T14:29:50Z'),
        ].join('\n'),
        now,
        5000,
      ));
      expect(result, [
        (network: '1E', station: 'MONT1', selector: 'HN?.D'),
        (network: 'IU', station: 'ANMO', selector: '10BH?.D'),
      ]);
    },
  );

  test(
    'Unsupported formats and stale, future, ambiguous times stay excluded',
    () {
      final result = parseFdsnStreamCatalog((
        [
          row('FDSN:IU_ANMO_00_B_H_Z/MSEED3'),
          row('FDSN:IU_ANMO_00_B_H_Z/MSEED/extra'),
          row('FDSN:IU_ANMO_00_B_H_Z/MSEED', '2026-09-09T14:26:59Z'),
          row('FDSN:IU_ANMO_00_B_H_Z/MSEED', '2026-09-09T14:30:01Z'),
          row('FDSN:IU_ANMO_00_B_H_Z/MSEED', '2026-09-09T14:29:50'),
          row('FDSN:IU_ANMO_00_L_H_Z/MSEED'),
          row('FDSN:_ANMO_00_B_H_Z/MSEED'),
          row('FDSN:IU__00_B_H_Z/MSEED'),
        ].join('\n'),
        now,
        5000,
      ));
      expect(result, isEmpty);
    },
  );

  test('Full catalog processes beyond the old partial-catalog range', () {
    final raw = [
      for (var n = 0; n < 5100; n++) row('FDSN:XX_S${n}__B_H_Z/MSEED'),
    ].join('\n');
    final result = parseFdsnStreamCatalog((raw, now, 5000));
    expect(result.length, 5000);
    expect(result.last.station, 'S4999');
    expect(parseFdsnStreamCatalog((raw, now, 0)), isEmpty);
  });
}
