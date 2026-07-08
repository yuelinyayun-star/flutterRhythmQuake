import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';

void main() {
  test('builds chronological event-level splits and quality counts', () {
    final datasets = [
      _dataset(2020, [_event('train-ok', usableStations: 4)]),
      _dataset(2021, [_event('validation-rejected', usableStations: 3)]),
      _dataset(2022, [_event('test-ok', usableStations: 5)]),
    ];

    final result = const JmaIntensityDatasetBuilder().build(
      datasets,
      generatedAt: DateTime.utc(2026, 6, 20),
    );
    final splits = result.splits['splits']! as Map<String, List<String>>;
    final totals = result.qualityReport['totals']! as Map<String, Object?>;

    expect(splits['train'], ['train-ok']);
    expect(splits['validation'], isEmpty);
    expect(splits['test'], ['test-ok']);
    expect(totals['events'], 3);
    expect(totals['eligibleEvents'], 2);
    expect(result.qualityReport['rejectionReasons'], {
      'fewer_than_4_usable_stations': 1,
    });
    expect(result.qualityReportMarkdown(), contains('| test | 1 |'));
  });

  test('rejects duplicate event ids across annual archives', () {
    final datasets = [
      _dataset(2020, [_event('duplicate', usableStations: 4)]),
      _dataset(2021, [_event('duplicate', usableStations: 4)]),
    ];

    expect(
      () => const JmaIntensityDatasetBuilder().build(datasets),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _dataset(int year, List<Map<String, Object?>> events) => {
  'datasetId': 'year-$year',
  'year': year,
  'processingVersion': 'test',
  'sourceUrl': 'https://example.invalid/$year',
  'events': events,
};

Map<String, Object?> _event(String id, {required int usableStations}) => {
  'eventId': id,
  'preferredHypocenter': {
    'originTime': '2020-01-01T00:00:00.000Z',
    'latitude': 35.0,
    'longitude': 140.0,
    'depthKm': 20.0,
    'magnitude': 4.0,
    'maximumIntensityClass': '3',
    'determinationFlag': 'K',
  },
  'observations': [
    for (var index = 0; index < usableStations; index++)
      {
        'stationId': 'station-$index',
        'latitude': 35.0 + index / 10,
        'longitude': 140.0 + index / 10,
        'instrumentalIntensity': 1.0,
      },
  ],
};
