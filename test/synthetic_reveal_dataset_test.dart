import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/synthetic_reveal_dataset.dart';

void main() {
  test(
    'generates deterministic train and validation variants without test',
    () {
      final annual = [
        _annual([
          _event('train-event', 10),
          _event('validation-event', 10),
          _event('test-event', 10),
        ]),
      ];
      final splits = {
        'datasetId': 'source',
        'splits': {
          'train': ['train-event'],
          'validation': ['validation-event'],
          'test': ['test-event'],
        },
      };
      const builder = SyntheticRevealDatasetBuilder(seed: 7);

      final first = builder.build(
        annualDatasets: annual,
        splitManifest: splits,
        generatedAt: DateTime.utc(2026, 6, 21),
      );
      final second = builder.build(
        annualDatasets: annual,
        splitManifest: splits,
        generatedAt: DateTime.utc(2026, 6, 21),
      );

      expect(first.datasetsBySplit.keys, containsAll(['train', 'validation']));
      expect(first.datasetsBySplit.keys, isNot(contains('test')));
      expect(first.manifest['splitPolicy'], {
        'generatedSplits': ['train', 'validation'],
        'testDerivedSampleCount': 0,
        'frozenTestEventCount': 1,
        'derivedSamplesInheritSourceSplit': true,
      });
      expect(first.datasetsBySplit, second.datasetsBySplit);

      final trainEvents =
          first.datasetsBySplit['train']!['events']! as List<Object?>;
      final trainEvent = trainEvents.single as Map<String, Object?>;
      final variants = trainEvent['variants']! as List<Object?>;
      expect(variants, hasLength(3));
      expect(
        variants.map(
          (item) => (item! as Map<String, Object?>)['retainedStationIds'],
        ),
        everyElement(isNotEmpty),
      );
      final retained = [
        for (final raw in variants)
          ((raw! as Map<String, Object?>)['retainedStationIds']!
                  as List<Object?>)
              .cast<String>()
              .toSet(),
      ];
      expect(retained[0].containsAll(retained[1]), isTrue);
      expect(retained[1].containsAll(retained[2]), isTrue);
    },
  );

  test(
    'theoretical reveal times are ordered and retain final-value semantics',
    () {
      final result =
          const SyntheticRevealDatasetBuilder(maskRates: [0.5], seed: 1).build(
            annualDatasets: [
              _annual([_event('train-event', 8)]),
            ],
            splitManifest: {
              'datasetId': 'source',
              'splits': {
                'train': ['train-event'],
                'validation': <String>[],
                'test': <String>[],
              },
            },
            generatedAt: DateTime.utc(2026, 6, 21),
          );
      final events =
          result.datasetsBySplit['train']!['events']! as List<Object?>;
      final event = events.single as Map<String, Object?>;
      final stations = event['stations']! as List<Object?>;
      for (final raw in stations) {
        final station = raw! as Map<String, Object?>;
        expect(
          station['theoreticalPArrivalSeconds']! as double,
          lessThan(station['theoreticalSArrivalSeconds']! as double),
        );
        expect(station['qualityFlags'], contains('jma_final_peak_intensity'));
      }
      final variant =
          (event['variants']! as List<Object?>).single as Map<String, Object?>;
      final frames = variant['revealFrames']! as List<Object?>;
      final seconds = [
        for (final raw in frames)
          ((raw! as Map<String, Object?>)['elapsedSeconds']! as num).toInt(),
      ];
      expect(seconds, orderedEquals([...seconds]..sort()));
    },
  );

  test(
    'can explicitly generate frozen test variants once criteria are fixed',
    () {
      final result =
          const SyntheticRevealDatasetBuilder(
            generatedSplits: ['test'],
            maskRates: [0.5],
            seed: 7,
          ).build(
            annualDatasets: [
              _annual([_event('test-event', 8)]),
            ],
            splitManifest: {
              'datasetId': 'source',
              'splits': {
                'train': <String>[],
                'validation': <String>[],
                'test': ['test-event'],
              },
            },
            generatedAt: DateTime.utc(2026, 6, 28),
          );

      expect(result.datasetsBySplit.keys, ['test']);
      expect(result.manifest['splitPolicy'], {
        'generatedSplits': ['test'],
        'testDerivedSampleCount': 1,
        'frozenTestEventCount': 1,
        'derivedSamplesInheritSourceSplit': true,
      });
      expect(
        (result.datasetsBySplit['test']!['events']! as List<Object?>),
        hasLength(1),
      );
      expect(
        (result.qualityReport['totals']!
            as Map<String, Object?>)['testDerivedSamples'],
        1,
      );
    },
  );

  test('rejects event leakage across source splits', () {
    expect(
      () => const SyntheticRevealDatasetBuilder().build(
        annualDatasets: [
          _annual([_event('duplicate', 4)]),
        ],
        splitManifest: {
          'datasetId': 'source',
          'splits': {
            'train': ['duplicate'],
            'validation': ['duplicate'],
            'test': <String>[],
          },
        },
      ),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _annual(List<Map<String, Object?>> events) => {
  'events': events,
};

Map<String, Object?> _event(String eventId, int stationCount) => {
  'eventId': eventId,
  'preferredHypocenter': {
    'originTime': '2026-06-21T00:00:00.000Z',
    'latitude': 35.0,
    'longitude': 140.0,
    'depthKm': 20.0,
    'magnitude': 4.0,
  },
  'observations': [
    for (var index = 0; index < stationCount; index++)
      {
        'stationId': 'station-$index',
        'latitude': 35.0 + index / 20,
        'longitude': 140.0 + index / 20,
        'instrumentalIntensity': 1.0 + index / 10,
        'intensityClass': '1',
      },
  ],
};
