import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main() {
  const model = Matsuzaki2006AttenuationModel();

  group('Matsuzaki 2006 forward model', () {
    test('retains published equation 12 coefficients', () {
      expect(Matsuzaki2006AttenuationModel.magnitudeCoefficient, 1.36);
      expect(Matsuzaki2006AttenuationModel.logDistanceCoefficient, 4.03);
      expect(Matsuzaki2006AttenuationModel.saturationCoefficient, 0.00675);
      expect(Matsuzaki2006AttenuationModel.saturationMagnitudeExponent, 0.5);
      expect(Matsuzaki2006AttenuationModel.depthCoefficient, 0.0155);
      expect(Matsuzaki2006AttenuationModel.intercept, 2.05);

      expect(
        model.predictIntensity(
          magnitude: 7,
          sourceDistanceKm: 100,
          depthKm: 40,
        ),
        closeTo(3.7913864020788353, 1e-12),
      );
    });

    test('caps only the formula depth term at 100 km', () {
      final at100 = model.predictIntensity(
        magnitude: 7,
        sourceDistanceKm: 100,
        depthKm: 100,
      );
      final at183 = model.predictIntensity(
        magnitude: 7,
        sourceDistanceKm: 100,
        depthKm: 183,
      );

      expect(at183, closeTo(at100, 1e-12));
    });

    test('rejects extrapolation outside the published data domain', () {
      expect(
        () => model.predictIntensity(
          magnitude: 4.9,
          sourceDistanceKm: 100,
          depthKm: 40,
        ),
        throwsRangeError,
      );
      expect(
        () => model.predictIntensity(
          magnitude: 7,
          sourceDistanceKm: 0.9,
          depthKm: 40,
        ),
        throwsRangeError,
      );
      expect(
        () => model.predictIntensity(
          magnitude: 7,
          sourceDistanceKm: 100,
          depthKm: 184,
        ),
        throwsRangeError,
      );
    });
  });

  group('Matsuzaki 2006 point-source geometry', () {
    test('combines epicentral distance and depth without a distance floor', () {
      expect(
        Matsuzaki2006PointSourceGeometry.hypocentralDistanceFromEpicentral(
          epicentralDistanceKm: 30,
          depthKm: 40,
        ),
        closeTo(50, 1e-12),
      );
      expect(
        Matsuzaki2006PointSourceGeometry.hypocentralDistanceFromEpicentral(
          epicentralDistanceKm: 0,
          depthKm: 0,
        ),
        0,
      );
    });

    test('uses the existing great-circle calculation for station geometry', () {
      const sourceLatitude = 35.7;
      const sourceLongitude = 141.1;
      const stationLatitude = 35.6;
      const stationLongitude = 140.9;
      const depthKm = 40.0;
      final epicentralDistanceKm = QuakeCalculator.haversineDistance(
        sourceLatitude,
        sourceLongitude,
        stationLatitude,
        stationLongitude,
      );

      final distance =
          Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
            sourceLatitude: sourceLatitude,
            sourceLongitude: sourceLongitude,
            stationLatitude: stationLatitude,
            stationLongitude: stationLongitude,
            depthKm: depthKm,
          );

      expect(
        distance * distance,
        closeTo(
          epicentralDistanceKm * epicentralDistanceKm + depthKm * depthKm,
          1e-9,
        ),
      );
    });
  });

  group('Matsuzaki 2006 finite-fault geometry', () {
    const verticalPlane = Matsuzaki2006RectangularFaultPlane(
      id: 'vertical-test-plane',
      upperEdgeStartLatitude: 0,
      upperEdgeStartLongitude: 0,
      upperEdgeDepthKm: 5,
      lengthKm: 10,
      widthKm: 10,
      upperEdgeAzimuthDegrees: 90,
      downDipAzimuthDegrees: 180,
      dipDegrees: 90,
    );

    test('projects onto the finite rectangle and clamps beyond its edge', () {
      const fiveKilometresInDegrees = 5 / 111.19492664455873;

      expect(
        verticalPlane.shortestDistanceToSurfacePoint(latitude: 0, longitude: 0),
        closeTo(5, 1e-9),
      );
      expect(
        verticalPlane.shortestDistanceToSurfacePoint(
          latitude: 0,
          longitude: fiveKilometresInDegrees,
        ),
        closeTo(5, 1e-6),
      );
      expect(
        verticalPlane.shortestDistanceToSurfacePoint(
          latitude: fiveKilometresInDegrees,
          longitude: 0,
        ),
        closeTo(7.0710678118654755, 1e-6),
      );
    });

    test('uses the nearest rectangle in a multi-fault union', () {
      const shallowPlane = Matsuzaki2006RectangularFaultPlane(
        id: 'shallow-test-plane',
        upperEdgeStartLatitude: 0,
        upperEdgeStartLongitude: 0,
        upperEdgeDepthKm: 2,
        lengthKm: 1,
        widthKm: 1,
        upperEdgeAzimuthDegrees: 90,
        downDipAzimuthDegrees: 180,
        dipDegrees: 90,
      );

      expect(
        Matsuzaki2006FiniteFaultGeometry.shortestDistanceToFaultUnion(
          faultPlanes: const [verticalPlane, shallowPlane],
          stationLatitude: 0,
          stationLongitude: 0,
        ),
        closeTo(2, 1e-9),
      );
    });

    test(
      'accepts a sourced interior point without inventing an edge origin',
      () {
        const fiveKilometresInDegrees = 5 / 111.19492664455873;
        const anchoredPlane =
            Matsuzaki2006RectangularFaultPlane.fromPointOnPlane(
              id: 'anchored-test-plane',
              referencePointRole: 'rupture_start',
              referenceLatitude: 0,
              referenceLongitude: fiveKilometresInDegrees,
              referenceDepthKm: 10,
              referenceAlongLengthKm: 5,
              referenceDownDipKm: 5,
              lengthKm: 10,
              widthKm: 10,
              upperEdgeAzimuthDegrees: 90,
              downDipAzimuthDegrees: 180,
              dipDegrees: 90,
            );

        expect(
          anchoredPlane.shortestDistanceToSurfacePoint(
            latitude: 0,
            longitude: fiveKilometresInDegrees,
          ),
          closeTo(5, 1e-9),
        );
        for (final longitude in [0.0, fiveKilometresInDegrees, 0.1]) {
          expect(
            anchoredPlane.shortestDistanceToSurfacePoint(
              latitude: 0,
              longitude: longitude,
            ),
            closeTo(
              verticalPlane.shortestDistanceToSurfacePoint(
                latitude: 0,
                longitude: longitude,
              ),
              1e-9,
            ),
          );
        }
        expect(
          anchoredPlane.toJson()['inferredUpperEdgeDepthKm'],
          closeTo(5, 1e-9),
        );
        expect(
          (anchoredPlane.toJson()['referencePoint']!
              as Map<String, Object>)['role'],
          'rupture_start',
        );
      },
    );
  });

  group('Matsuzaki 2006 magnitude inversion', () {
    test('round-trips a unique root on a monotonic branch', () {
      final intensity = model.predictIntensity(
        magnitude: 6.5,
        sourceDistanceKm: 100,
        depthKm: 40,
      );

      final result = model.inferMagnitudes(
        observedIntensity: intensity,
        sourceDistanceKm: 100,
        depthKm: 40,
      );

      expect(result.status, MatsuzakiMagnitudeInferenceStatus.solvedUnique);
      expect(result.turningMagnitude, isNull);
      expect(result.uniqueMagnitude, closeTo(6.5, 1e-9));
    });

    test('round-trips the decreasing near-source branch', () {
      final intensity = model.predictIntensity(
        magnitude: 7,
        sourceDistanceKm: 1,
        depthKm: 40,
      );

      final result = model.inferMagnitudes(
        observedIntensity: intensity,
        sourceDistanceKm: 1,
        depthKm: 40,
      );

      expect(result.status, MatsuzakiMagnitudeInferenceStatus.solvedUnique);
      expect(result.turningMagnitude, isNull);
      expect(result.uniqueMagnitude, closeTo(7, 1e-9));
    });

    test('exposes both roots instead of choosing a near-source branch', () {
      final result = model.inferMagnitudes(
        observedIntensity: 5.8,
        sourceDistanceKm: 15,
        depthKm: 40,
      );

      expect(result.status, MatsuzakiMagnitudeInferenceStatus.solvedAmbiguous);
      expect(result.roots, hasLength(2));
      expect(result.roots.first, lessThan(result.turningMagnitude!));
      expect(result.roots.last, greaterThan(result.turningMagnitude!));
      for (final magnitude in result.roots) {
        expect(
          model.predictIntensity(
            magnitude: magnitude,
            sourceDistanceKm: 15,
            depthKm: 40,
          ),
          closeTo(5.8, 1e-9),
        );
      }
    });

    test('the analytic turning magnitude has zero local slope', () {
      final turningMagnitude = model.turningMagnitudeForSourceDistance(15)!;

      expect(turningMagnitude, closeTo(7.3281701892061815, 1e-12));
      expect(
        model.intensityDerivativeByMagnitude(
          magnitude: turningMagnitude,
          sourceDistanceKm: 15,
        ),
        closeTo(0, 1e-12),
      );
    });

    test('returns explicit statuses when no calibrated magnitude can fit', () {
      final reference = model.inferMagnitudes(
        observedIntensity: 5.8,
        sourceDistanceKm: 15,
        depthKm: 40,
      );

      final below = model.inferMagnitudes(
        observedIntensity: reference.minimumPredictedIntensity - 0.1,
        sourceDistanceKm: 15,
        depthKm: 40,
      );
      final above = model.inferMagnitudes(
        observedIntensity: reference.maximumPredictedIntensity + 0.1,
        sourceDistanceKm: 15,
        depthKm: 40,
      );

      expect(
        below.status,
        MatsuzakiMagnitudeInferenceStatus.observedBelowModelOutputRange,
      );
      expect(below.roots, isEmpty);
      expect(
        above.status,
        MatsuzakiMagnitudeInferenceStatus.observedAboveModelOutputRange,
      );
      expect(above.roots, isEmpty);
    });

    test('a target at the stationary point produces one shared root', () {
      final turningMagnitude = model.turningMagnitudeForSourceDistance(15)!;
      final maximumIntensity = model.predictIntensity(
        magnitude: turningMagnitude,
        sourceDistanceKm: 15,
        depthKm: 40,
      );

      final result = model.inferMagnitudes(
        observedIntensity: maximumIntensity,
        sourceDistanceKm: 15,
        depthKm: 40,
      );

      expect(result.status, MatsuzakiMagnitudeInferenceStatus.solvedUnique);
      expect(result.uniqueMagnitude, closeTo(turningMagnitude, 1e-10));
    });
  });
}
