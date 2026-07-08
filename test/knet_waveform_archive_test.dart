import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_archive.dart';

void main() {
  const parser = KnetWaveformArchiveParser();

  test(
    'parses K-NET ASCII raw digits with scale factor and pre-trigger time',
    () {
      final channel = parser.parseAscii(
        _ascii(
          extension: 'NS',
          stationCode: 'IBR011',
          direction: 'N-S',
          sampleLines: const [
            '       -971     -951     -948     -970',
            '       -982     -976     -965     -957',
          ],
        ),
        sourcePath: 'IBR0111103111446.NS',
      );

      expect(channel.format, KnetWaveformFormat.ascii);
      expect(channel.network, KnetNetwork.knet);
      expect(channel.sensorRole, KnetSensorRole.surface);
      expect(channel.component, 'NS');
      expect(channel.stationCode, 'IBR011');
      expect(channel.samplingHz, 100);
      expect(channel.recordTimeUtc, DateTime.utc(2011, 3, 11, 5, 47, 21));
      expect(channel.sampleStartTimeUtc, DateTime.utc(2011, 3, 11, 5, 47, 6));
      expect(channel.digitValues, const [
        -971,
        -951,
        -948,
        -970,
        -982,
        -976,
        -965,
        -957,
      ]);
      expect(channel.scaleFactor, closeTo(3920 / 6182761, 1e-12));
      expect(
        channel.accelerationGal.first,
        closeTo(-971 * 3920 / 6182761, 1e-9),
      );
      expect(channel.dataPrecision, 'raw_digit_scale_factor');
      expect(channel.processingVersion, knetWaveformParserVersion);
    },
  );

  test('separates KiK-net ASCII borehole and surface roles by extension', () {
    final borehole = parser.parseAscii(
      _ascii(
        extension: 'NS1',
        stationCode: 'FKSH10',
        direction: 'N-S',
        sampleLines: const ['          1        2        3        4'],
      ),
      sourcePath: 'FKSH101103111446.NS1',
    );
    final surface = parser.parseAscii(
      _ascii(
        extension: 'EW2',
        stationCode: 'FKSH10',
        direction: 'E-W',
        sampleLines: const ['          1        2        3        4'],
      ),
      sourcePath: 'FKSH101103111446.EW2',
    );

    expect(borehole.network, KnetNetwork.kikNet);
    expect(borehole.sensorRole, KnetSensorRole.borehole);
    expect(borehole.component, 'NS');
    expect(surface.network, KnetNetwork.kikNet);
    expect(surface.sensorRole, KnetSensorRole.surface);
    expect(surface.component, 'EW');
  });

  test('parses K-NET CSV as three surface physical-gal channels', () {
    final channels = parser.parseCsv(_knetCsv, sourcePath: 'FKS005.csv');

    expect(channels, hasLength(3));
    expect(channels.map((c) => c.component), ['NS', 'EW', 'UD']);
    expect(channels.every((c) => c.network == KnetNetwork.knet), isTrue);
    expect(
      channels.every((c) => c.sensorRole == KnetSensorRole.surface),
      isTrue,
    );
    expect(channels.first.stationCode, 'FKS005');
    expect(
      channels.first.sampleStartTimeUtc,
      DateTime.utc(2019, 1, 2, 8, 47, 27),
    );
    expect(channels.first.accelerationGal, const [-18.56, -18.73]);
    expect(channels.first.offsetGal, -18.60);
    expect(channels.first.dataPrecision, 'csv_physical_gal_0.01');
  });

  test('parses KiK-net CSV as borehole then surface channels', () {
    final channels = parser.parseCsv(_kikCsv, sourcePath: 'FKSH09.csv');

    expect(channels, hasLength(6));
    expect(
      channels.take(3).every((c) => c.sensorRole == KnetSensorRole.borehole),
      isTrue,
    );
    expect(
      channels.skip(3).every((c) => c.sensorRole == KnetSensorRole.surface),
      isTrue,
    );
    expect(channels.map((c) => c.component), [
      'NS',
      'EW',
      'UD',
      'NS',
      'EW',
      'UD',
    ]);
    expect(channels.first.stationHeightMeters, 60);
    expect(channels.last.stationHeightMeters, 260);
  });

  test('parses zip entries without mixing source paths', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'knet/IBR0111103111446.NS',
          _ascii(
            extension: 'NS',
            stationCode: 'IBR011',
            direction: 'N-S',
            sampleLines: const ['          1        2        3        4'],
          ),
        ),
      )
      ..addFile(ArchiveFile.string('csv/FKS005.csv', _knetCsv));
    final bytes = ZipEncoder().encode(archive);

    final channels = parser.parseZipBytes(bytes, sourcePath: 'fixture.zip');

    expect(channels, hasLength(4));
    expect(channels.first.sourcePath, 'fixture.zip:knet/IBR0111103111446.NS');
    expect(
      channels
          .skip(1)
          .every((c) => c.sourcePath == 'fixture.zip:csv/FKS005.csv'),
      isTrue,
    );
  });
}

String _ascii({
  required String extension,
  required String stationCode,
  required String direction,
  required List<String> sampleLines,
}) {
  return [
    'Origin Time       2011/03/11 14:46:00',
    'Lat.              38.103',
    'Long.             142.860',
    'Depth. (km)       24',
    'Mag.              9.0',
    'Station Code      $stationCode',
    'Station Lat.      36.1256',
    'Station Long.     140.0901',
    'Station Height(m) 27',
    'Record Time       2011/03/11 14:47:21',
    'Sampling Freq(Hz) 100Hz',
    'Duration Time(s)  300',
    'Dir.              $direction',
    'Scale Factor      3920(gal)/6182761',
    'Max. Acc. (gal)   328.844',
    'Last Correction   2011/03/11 14:47:06',
    'Memo.             test $extension',
    ...sampleLines,
    '',
  ].join('\n');
}

const _knetCsv = '''
#K-NET CSV
#Event
#OriginTime,Latitude,Longitude,Depth(km),Magnitude
#2019/01/02 17:47:00,36.708,140.952,32,3.8
#Station
#Code,Latitude,Longitude,Height(m)
#FKS005,37.6389,140.9853,17
#Record
#SamplingFrequency(Hz)
#100
#DurationTime(s)
#60
#Offset
#N-S(gal),E-W(gal),U-D(gal)
#-18.60,-1.40,26.10
#Time,RelativeTime(s),N-S(gal),E-W(gal),U-D(gal)
2019/01/02 17:47:27.00,0.00,-18.56,-1.43,26.00
2019/01/02 17:47:27.01,0.01,-18.73,-1.38,26.03
''';

const _kikCsv = '''
#K-NET CSV
#Event
#OriginTime,Latitude,Longitude,Depth(km),Magnitude
#2019/01/02 17:47:00,36.708,140.952,32,3.8
#Station
#Code,Latitude,Longitude,Height1(m),Height2(m)
#FKSH09,37.3530,140.4264,60,260
#Record
#SamplingFrequency(Hz)
#100
#DurationTime(s)
#120
#Offset
#1(gal),2(gal),3(gal),4(gal),5(gal),6(gal)
#49.20,2.10,-25.50,-11.10,13.60,-20.00
#Time,RelativeTime(s),1(gal),2(gal),3(gal),4(gal),5(gal),6(gal)
2019/01/02 17:47:13.00,0.00,49.25,2.19,-25.58,-11.16,13.70,-20.07
2019/01/02 17:47:13.01,0.01,49.25,2.19,-25.58,-11.16,13.70,-20.07
''';
