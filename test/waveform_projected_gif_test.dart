import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/waveform_projected_gif.dart';

void main() {
  test('maps shindo to GIF-equivalent color position and projected level', () {
    expect(gifEquivalentColorPosition(-3), 0);
    expect(gifEquivalentColorPosition(2), 0.5);
    expect(gifEquivalentColorPosition(9), 1);
    expect(projectedShindoLevel(-4), -1);
    expect(projectedShindoLevel(-3), 0);
    expect(projectedShindoLevel(0.5), 9);
    expect(projectedShindoLevel(6.5), 29);
  });

  test('converts waveform feature package into projected GIF observations', () {
    const converter = WaveformProjectedGifConverter();
    final package = converter.convertFeaturePackage(
      {
        'channels': [
          {
            'eventOriginTimeUtc': '2026-06-21T00:00:00Z',
            'eventLatitude': 35.0,
            'eventLongitude': 140.0,
            'eventDepthKm': 10.0,
            'eventMagnitude': 4.0,
          },
        ],
        'features': [
          {
            'stationCode': 'TST001',
            'network': 'knet',
            'sensorRole': 'surface',
            'stationLatitude': 35.1,
            'stationLongitude': 140.1,
            'qualityFlags': ['jma_intensity_unfiltered_duration_proxy'],
            'seconds': [
              {
                'startTimeUtc': '2026-06-21T00:00:00Z',
                'jmaIntensityApprox': 2.0,
                'pgaGal': 12.5,
                'pgvCms': 1.2,
                'energyRatioToPreviousBaseline': null,
              },
              {
                'startTimeUtc': '2026-06-21T00:00:01Z',
                'jmaIntensityApprox': null,
                'pgaGal': 0.1,
                'pgvCms': 0.01,
                'energyRatioToPreviousBaseline': null,
              },
            ],
          },
        ],
      },
      eventId: 'event-a',
      sourceFeaturePackagePath: 'tmp/features.json',
      sourceFeatureFormat: 'csv',
      niedDirectoryId: '20260621000000',
    );

    expect(package.eventId, 'event-a');
    expect(package.stationCount, 1);
    expect(package.stationSecondCount, 1);
    expect(package.event?.latitude, 35.0);
    expect(package.stations.single.latitude, 35.1);
    expect(package.qualityFlags, contains('not_real_nied_gif'));
    final observation = package.observations.single;
    expect(observation.stationCode, 'TST001');
    expect(observation.gifEquivalentShindo, 2.0);
    expect(observation.colorPosition, 0.5);
    expect(observation.projectedLevel, 13);
    expect(observation.pgaGal, 12.5);
    expect(
      observation.qualityFlags,
      contains('projected_from_official_waveform'),
    );
    expect(observation.qualityFlags, contains('not_real_nied_gif'));
  });
}
