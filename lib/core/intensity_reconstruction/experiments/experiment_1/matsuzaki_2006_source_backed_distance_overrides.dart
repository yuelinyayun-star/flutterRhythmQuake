import 'matsuzaki_2006_attenuation_model.dart';
import 'matsuzaki_2006_finite_fault_geometry.dart';
import 'matsuzaki_2006_jma_baseline.dart';

class Matsuzaki2006SourceBackedGeometryVariant {
  const Matsuzaki2006SourceBackedGeometryVariant({
    required this.id,
    required this.label,
    required this.faultPlanes,
  });

  final String id;
  final String label;
  final List<Matsuzaki2006RectangularFaultPlane> faultPlanes;
}

class Matsuzaki2006SourceBackedEventGeometry {
  const Matsuzaki2006SourceBackedEventGeometry({
    required this.eventId,
    required this.year,
    required this.regionName,
    required this.geometryRecord,
    required this.variants,
    this.preferredVariantId,
  });

  final String eventId;
  final int year;
  final String regionName;
  final String geometryRecord;
  final List<Matsuzaki2006SourceBackedGeometryVariant> variants;
  final String? preferredVariantId;

  Matsuzaki2006SourceBackedGeometryVariant get preferredVariant {
    if (variants.length == 1 && preferredVariantId == null) {
      return variants.single;
    }
    final preferredId = preferredVariantId;
    if (preferredId == null) {
      throw StateError('Event $eventId has no preferred geometry variant.');
    }
    final matches = variants
        .where((variant) => variant.id == preferredId)
        .toList();
    if (matches.length != 1) {
      throw StateError(
        'Event $eventId does not contain exactly one preferred variant '
        '$preferredId.',
      );
    }
    return matches.single;
  }

  Matsuzaki2006SourceBackedGeometryVariant get unambiguousVariant {
    if (variants.length != 1) {
      throw StateError(
        'Event $eventId has ${variants.length} source-backed geometry variants.',
      );
    }
    return variants.single;
  }
}

class Matsuzaki2006StationDistanceOverride {
  const Matsuzaki2006StationDistanceOverride({
    required this.originalStation,
    required this.finiteFaultDistanceKm,
  });

  final Matsuzaki2006StationResidual originalStation;
  final double finiteFaultDistanceKm;

  double get pointSourceDistanceKm => originalStation.sourceDistanceKm;

  bool get isInsidePublishedDistanceDomain =>
      finiteFaultDistanceKm >=
          Matsuzaki2006AttenuationModel.minimumSourceDistanceKm &&
      finiteFaultDistanceKm <=
          Matsuzaki2006AttenuationModel.maximumSourceDistanceKm;
}

class Matsuzaki2006EventDistanceOverride {
  Matsuzaki2006EventDistanceOverride({
    required this.originalEvent,
    required this.geometry,
    required this.variant,
    required List<Matsuzaki2006StationDistanceOverride> stations,
  }) : stations = List.unmodifiable(stations);

  final Matsuzaki2006EventBaseline originalEvent;
  final Matsuzaki2006SourceBackedEventGeometry geometry;
  final Matsuzaki2006SourceBackedGeometryVariant variant;
  final List<Matsuzaki2006StationDistanceOverride> stations;

  int get excludedOutsidePublishedDistanceDomainCount => stations
      .where((station) => !station.isInsidePublishedDistanceDomain)
      .length;

  Matsuzaki2006EventBaseline toPublishedDomainEvent({
    Matsuzaki2006AttenuationModel model = const Matsuzaki2006AttenuationModel(),
  }) {
    return Matsuzaki2006EventBaseline(
      eventId: originalEvent.eventId,
      year: originalEvent.year,
      originTime: originalEvent.originTime,
      latitude: originalEvent.latitude,
      longitude: originalEvent.longitude,
      depthKm: originalEvent.depthKm,
      magnitude: originalEvent.magnitude,
      magnitudeType: originalEvent.magnitudeType,
      maximumIntensityClass: originalEvent.maximumIntensityClass,
      determinationFlag: originalEvent.determinationFlag,
      stationResiduals: [
        for (final override in stations)
          if (override.isInsidePublishedDistanceDomain)
            Matsuzaki2006StationResidual(
              stationId: override.originalStation.stationId,
              latitude: override.originalStation.latitude,
              longitude: override.originalStation.longitude,
              sourceDistanceKm: override.finiteFaultDistanceKm,
              observedIntensity: override.originalStation.observedIntensity,
              predictedIntensity: model.predictIntensity(
                magnitude: originalEvent.magnitude,
                sourceDistanceKm: override.finiteFaultDistanceKm,
                depthKm: originalEvent.depthKm,
              ),
            ),
      ],
    );
  }
}

class Matsuzaki2006DistanceSemanticApplication {
  Matsuzaki2006DistanceSemanticApplication({
    required List<Matsuzaki2006EventBaseline> events,
    required List<Matsuzaki2006EventDistanceOverride> overrides,
  }) : events = List.unmodifiable(events),
       overrides = List.unmodifiable(overrides);

  final List<Matsuzaki2006EventBaseline> events;
  final List<Matsuzaki2006EventDistanceOverride> overrides;

  int get excludedOutsidePublishedDistanceDomainCount => overrides.fold(
    0,
    (sum, override) =>
        sum + override.excludedOutsidePublishedDistanceDomainCount,
  );
}

abstract final class Matsuzaki2006SourceBackedDistanceOverrides {
  static const osakaSingleFault = Matsuzaki2006RectangularFaultPlane(
    id: 'gnss-single-fault',
    upperEdgeStartLatitude: 34.837,
    upperEdgeStartLongitude: 135.603,
    upperEdgeDepthKm: 7.2,
    lengthKm: 4,
    widthKm: 4,
    upperEdgeAzimuthDegrees: 49,
    downDipAzimuthDegrees: 139,
    dipDegrees: 73,
  );

  static const osakaDoubleFaultStrikeSlip = Matsuzaki2006RectangularFaultPlane(
    id: 'double-fault-strike-slip',
    upperEdgeStartLatitude: 34.837,
    upperEdgeStartLongitude: 135.602,
    upperEdgeDepthKm: 6.1,
    lengthKm: 4,
    widthKm: 4,
    upperEdgeAzimuthDegrees: 52,
    downDipAzimuthDegrees: 142,
    dipDegrees: 77,
  );

  static const osakaDoubleFaultReverse = Matsuzaki2006RectangularFaultPlane(
    id: 'double-fault-reverse',
    upperEdgeStartLatitude: 34.837,
    upperEdgeStartLongitude: 135.600,
    upperEdgeDepthKm: 9.6,
    lengthKm: 4,
    widthKm: 4,
    upperEdgeAzimuthDegrees: 351,
    downDipAzimuthDegrees: 81,
    dipDegrees: 50,
  );

  static const kumamotoM65Fault =
      Matsuzaki2006RectangularFaultPlane.fromPointOnPlane(
        id: 'nied-kumamoto-20160414-m65-inversion-v2',
        referencePointRole: 'rupture_start',
        referenceLatitude: 32.7417,
        referenceLongitude: 130.7994,
        referenceDepthKm: 12.49,
        referenceAlongLengthKm: 13,
        referenceDownDipKm: 11,
        lengthKm: 22,
        widthKm: 14,
        upperEdgeAzimuthDegrees: 212,
        downDipAzimuthDegrees: 302,
        dipDegrees: 89,
      );

  static const tottoriM66Fault =
      Matsuzaki2006RectangularFaultPlane.fromPointOnPlane(
        id: 'nied-tottori-20161021-m66-inversion-revised-2020',
        referencePointRole: 'rupture_start',
        referenceLatitude: 35.3806,
        referenceLongitude: 133.8545,
        referenceDepthKm: 11.58,
        referenceAlongLengthKm: 11,
        referenceDownDipKm: 11,
        lengthKm: 16,
        widthKm: 16,
        upperEdgeAzimuthDegrees: 162,
        downDipAzimuthDegrees: 252,
        dipDegrees: 88,
      );

  static const ibarakiM63Fault =
      Matsuzaki2006RectangularFaultPlane.fromPointOnPlane(
        id: 'jma-ibaraki-20161228-m63-near-revised-2017',
        referencePointRole: 'rupture_start',
        referenceLatitude: 36.7223,
        referenceLongitude: 140.5686,
        referenceDepthKm: 10.93,
        referenceAlongLengthKm: 22.5,
        referenceDownDipKm: 13.5,
        lengthKm: 30,
        widthKm: 24,
        upperEdgeAzimuthDegrees: 156,
        downDipAzimuthDegrees: 246,
        dipDegrees: 50,
      );

  static const naganoM67Fault =
      Matsuzaki2006RectangularFaultPlane.fromPointOnPlane(
        id: 'jma-nagano-20141122-m67-near-revised-2017-active-subfaults',
        referencePointRole: 'rupture_start',
        referenceLatitude: 36.6928,
        referenceLongitude: 137.8910,
        referenceDepthKm: 4.59,
        referenceAlongLengthKm: 7.5,
        referenceDownDipKm: 4.5,
        lengthKm: 21,
        widthKm: 12,
        upperEdgeAzimuthDegrees: 25,
        downDipAzimuthDegrees: 115,
        dipDegrees: 61,
      );

  static const fukushimaNakadoriM64Fault =
      Matsuzaki2006RectangularFaultPlane.fromPointOnPlane(
        id: 'jma-fukushima-nakadori-20110412-m64-near-revised-2017',
        referencePointRole: 'rupture_start',
        referenceLatitude: 37.0525,
        referenceLongitude: 140.6438,
        referenceDepthKm: 15.51,
        referenceAlongLengthKm: 5,
        referenceDownDipKm: 9,
        lengthKm: 14,
        widthKm: 12,
        upperEdgeAzimuthDegrees: 170,
        downDipAzimuthDegrees: 260,
        dipDegrees: 40,
      );

  static const eventGeometries = <Matsuzaki2006SourceBackedEventGeometry>[
    Matsuzaki2006SourceBackedEventGeometry(
      eventId: '2011041214074228-37.0525-140.6435',
      year: 2011,
      regionName: '福島県中通り',
      geometryRecord:
          'lib/core/intensity_reconstruction/experiments/experiment_1/'
          'matsuzaki_2006_fukushima_nakadori_m64_finite_fault_diagnostic.md',
      variants: [
        Matsuzaki2006SourceBackedGeometryVariant(
          id: 'jma_revised_rectangle',
          label: 'JMA revised rectangle',
          faultPlanes: [fukushimaNakadoriM64Fault],
        ),
      ],
    ),
    Matsuzaki2006SourceBackedEventGeometry(
      eventId: '2014112222081790-36.6928-137.8910',
      year: 2014,
      regionName: '長野県北部',
      geometryRecord:
          'lib/core/intensity_reconstruction/experiments/experiment_1/'
          'matsuzaki_2006_nagano_2014_m67_finite_fault_diagnostic.md',
      variants: [
        Matsuzaki2006SourceBackedGeometryVariant(
          id: 'jma_active_subfault_rectangle',
          label: 'JMA active-subfault rectangle',
          faultPlanes: [naganoM67Fault],
        ),
      ],
    ),
    Matsuzaki2006SourceBackedEventGeometry(
      eventId: '2016041421263443-32.7417-130.8087',
      year: 2016,
      regionName: '熊本県熊本地方',
      geometryRecord:
          'lib/core/intensity_reconstruction/experiments/experiment_1/'
          'matsuzaki_2006_kumamoto_m65_finite_fault_diagnostic.md',
      variants: [
        Matsuzaki2006SourceBackedGeometryVariant(
          id: 'nied_revised_rectangle',
          label: 'NIED revised rectangle',
          faultPlanes: [kumamotoM65Fault],
        ),
      ],
    ),
    Matsuzaki2006SourceBackedEventGeometry(
      eventId: '2016102114072257-35.3805-133.8562',
      year: 2016,
      regionName: '鳥取県中部',
      geometryRecord:
          'lib/core/intensity_reconstruction/experiments/experiment_1/'
          'matsuzaki_2006_tottori_m66_finite_fault_diagnostic.md',
      variants: [
        Matsuzaki2006SourceBackedGeometryVariant(
          id: 'nied_revised_rectangle',
          label: 'NIED revised rectangle',
          faultPlanes: [tottoriM66Fault],
        ),
      ],
    ),
    Matsuzaki2006SourceBackedEventGeometry(
      eventId: '2016122821384904-36.7202-140.5742',
      year: 2016,
      regionName: '茨城県北部',
      geometryRecord:
          'lib/core/intensity_reconstruction/experiments/experiment_1/'
          'matsuzaki_2006_ibaraki_m63_finite_fault_diagnostic.md',
      variants: [
        Matsuzaki2006SourceBackedGeometryVariant(
          id: 'jma_revised_rectangle',
          label: 'JMA revised rectangle',
          faultPlanes: [ibarakiM63Fault],
        ),
      ],
    ),
    Matsuzaki2006SourceBackedEventGeometry(
      eventId: '2018061807583414-34.8443-135.6217',
      year: 2018,
      regionName: '大阪府北部',
      preferredVariantId: 'gnss_double_rectangle_union',
      geometryRecord:
          'lib/core/intensity_reconstruction/experiments/experiment_1/'
          'matsuzaki_2006_osaka_finite_fault_diagnostic.md',
      variants: [
        Matsuzaki2006SourceBackedGeometryVariant(
          id: 'gnss_single_rectangle',
          label: 'GNSS single rectangle',
          faultPlanes: [osakaSingleFault],
        ),
        Matsuzaki2006SourceBackedGeometryVariant(
          id: 'gnss_double_rectangle_union',
          label: 'GNSS double rectangle union',
          faultPlanes: [osakaDoubleFaultStrikeSlip, osakaDoubleFaultReverse],
        ),
      ],
    ),
  ];

  static Matsuzaki2006EventDistanceOverride evaluateVariant({
    required Matsuzaki2006EventBaseline event,
    required Matsuzaki2006SourceBackedEventGeometry geometry,
    required Matsuzaki2006SourceBackedGeometryVariant variant,
  }) {
    if (event.eventId != geometry.eventId || event.year != geometry.year) {
      throw ArgumentError(
        'Event ${event.eventId}/${event.year} does not match geometry '
        '${geometry.eventId}/${geometry.year}.',
      );
    }
    if (!geometry.variants.any((candidate) => candidate.id == variant.id)) {
      throw ArgumentError.value(
        variant.id,
        'variant',
        'The variant does not belong to event ${geometry.eventId}.',
      );
    }
    return Matsuzaki2006EventDistanceOverride(
      originalEvent: event,
      geometry: geometry,
      variant: variant,
      stations: [
        for (final station in event.stationResiduals)
          Matsuzaki2006StationDistanceOverride(
            originalStation: station,
            finiteFaultDistanceKm:
                Matsuzaki2006FiniteFaultGeometry.shortestDistanceToFaultUnion(
                  faultPlanes: variant.faultPlanes,
                  stationLatitude: station.latitude,
                  stationLongitude: station.longitude,
                ),
          ),
      ],
    );
  }

  static Matsuzaki2006DistanceSemanticApplication
  applyUnambiguousCalibrationOverrides(
    List<Matsuzaki2006EventBaseline> events, {
    Set<int> calibrationYears = const {
      2010,
      2011,
      2012,
      2013,
      2014,
      2015,
      2016,
    },
    Matsuzaki2006AttenuationModel model = const Matsuzaki2006AttenuationModel(),
    bool requireEveryConfiguredEvent = true,
  }) {
    final applicableGeometries = eventGeometries
        .where(
          (geometry) =>
              calibrationYears.contains(geometry.year) &&
              geometry.variants.length == 1,
        )
        .toList();
    final geometriesByEventId = {
      for (final geometry in applicableGeometries) geometry.eventId: geometry,
    };
    final seenGeometryEventIds = <String>{};
    final overrides = <Matsuzaki2006EventDistanceOverride>[];
    final transformedEvents = <Matsuzaki2006EventBaseline>[];
    for (final event in events) {
      final geometry = geometriesByEventId[event.eventId];
      if (geometry == null) {
        transformedEvents.add(event);
        continue;
      }
      if (!seenGeometryEventIds.add(event.eventId)) {
        throw StateError('Duplicate accepted event ${event.eventId}.');
      }
      final override = evaluateVariant(
        event: event,
        geometry: geometry,
        variant: geometry.unambiguousVariant,
      );
      overrides.add(override);
      transformedEvents.add(override.toPublishedDomainEvent(model: model));
    }
    if (requireEveryConfiguredEvent) {
      final missing = geometriesByEventId.keys.toSet().difference(
        seenGeometryEventIds,
      );
      if (missing.isNotEmpty) {
        throw StateError(
          'Missing accepted events required by finite-fault semantics: '
          '${missing.toList()..sort()}.',
        );
      }
    }
    return Matsuzaki2006DistanceSemanticApplication(
      events: transformedEvents,
      overrides: overrides,
    );
  }
}
