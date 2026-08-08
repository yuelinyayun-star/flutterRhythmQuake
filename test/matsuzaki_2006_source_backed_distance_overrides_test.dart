import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main() {
  group('Matsuzaki2006SourceBackedDistanceOverrides', () {
    test(
      'keeps five unambiguous calibration geometries and two Osaka branches',
      () {
        final calibration = Matsuzaki2006SourceBackedDistanceOverrides
            .eventGeometries
            .where((geometry) => geometry.year <= 2016)
            .toList();
        final osaka = Matsuzaki2006SourceBackedDistanceOverrides.eventGeometries
            .singleWhere((geometry) => geometry.year == 2018);

        expect(calibration, hasLength(5));
        expect(
          calibration.every((geometry) => geometry.variants.length == 1),
          isTrue,
        );
        expect(
          osaka.variants.map((variant) => variant.id),
          containsAll(<String>{
            'gnss_single_rectangle',
            'gnss_double_rectangle_union',
          }),
        );
        expect(osaka.preferredVariant.id, 'gnss_double_rectangle_union');
      },
    );

    test(
      'replaces only configured event distances without mutating observations',
      () {
        final sourceEvent = _event(
          eventId: '2011041214074228-37.0525-140.6435',
          year: 2011,
          stations: [
            _station('a', 37.1, 140.7, 123, 4.2),
            _station('b', 38.0, 141.0, 234, 2.7),
          ],
        );
        const model = Matsuzaki2006AttenuationModel(
          coefficients: Matsuzaki2006AttenuationCoefficients
              .finiteFaultSemanticFrozen2017,
        );

        final application =
            Matsuzaki2006SourceBackedDistanceOverrides.applyUnambiguousCalibrationOverrides(
              [sourceEvent],
              calibrationYears: const {2011},
              model: model,
            );

        expect(application.overrides, hasLength(1));
        expect(application.events, hasLength(1));
        expect(
          application.events.single.stationResiduals.map(
            (station) => station.observedIntensity,
          ),
          [4.2, 2.7],
        );
        expect(
          application.events.single.stationResiduals.map(
            (station) => station.sourceDistanceKm,
          ),
          isNot([123.0, 234.0]),
        );
        for (final station in application.events.single.stationResiduals) {
          expect(
            station.predictedIntensity,
            closeTo(
              model.predictIntensity(
                magnitude: sourceEvent.magnitude,
                sourceDistanceKm: station.sourceDistanceKm,
                depthKm: sourceEvent.depthKm,
              ),
              1e-12,
            ),
          );
        }
        expect(sourceEvent.stationResiduals.first.sourceDistanceKm, 123);
      },
    );

    test(
      'preserves a sub-1 km geometry value and excludes it from formula input',
      () {
        final geometry =
            Matsuzaki2006SourceBackedDistanceOverrides.eventGeometries.first;
        final sourceEvent = _event(
          eventId: geometry.eventId,
          year: geometry.year,
          stations: [_station('sub-one', 37, 140, 10, 5.0)],
        );
        final stationOverride = Matsuzaki2006StationDistanceOverride(
          originalStation: sourceEvent.stationResiduals.single,
          finiteFaultDistanceKm: 0.65,
        );
        final eventOverride = Matsuzaki2006EventDistanceOverride(
          originalEvent: sourceEvent,
          geometry: geometry,
          variant: geometry.unambiguousVariant,
          stations: [stationOverride],
        );

        expect(stationOverride.finiteFaultDistanceKm, 0.65);
        expect(stationOverride.isInsidePublishedDistanceDomain, isFalse);
        expect(eventOverride.excludedOutsidePublishedDistanceDomainCount, 1);
        expect(
          eventOverride.toPublishedDomainEvent().stationResiduals,
          isEmpty,
        );
      },
    );
  });
}

Matsuzaki2006EventBaseline _event({
  required String eventId,
  required int year,
  required List<Matsuzaki2006StationResidual> stations,
}) => Matsuzaki2006EventBaseline(
  eventId: eventId,
  year: year,
  originTime: '$year-01-01T00:00:00Z',
  latitude: 37,
  longitude: 140,
  depthKm: 10,
  magnitude: 6,
  magnitudeType: 'D',
  maximumIntensityClass: '5+',
  determinationFlag: 'C',
  stationResiduals: stations,
);

Matsuzaki2006StationResidual _station(
  String id,
  double latitude,
  double longitude,
  double distanceKm,
  double intensity,
) => Matsuzaki2006StationResidual(
  stationId: id,
  latitude: latitude,
  longitude: longitude,
  sourceDistanceKm: distanceKm,
  observedIntensity: intensity,
  predictedIntensity: 0,
);
