import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

// The original worker snapshot, retained as the regression reference.
NiedStation referenceStationSnapshot(NiedStation station) =>
    NiedStation(
        id: station.id,
        code: station.code,
        name: station.name,
        coordinate: station.coordinate,
        network: station.network,
        prefecture: station.prefecture,
        expireSeconds: station.expireSeconds,
        pixelX: station.pixelX,
        pixelY: station.pixelY,
        scanReliable: station.scanReliable,
        pixelClusterId: station.pixelClusterId,
        level: station.level,
      )
      ..defaultExpireSeconds = station.defaultExpireSeconds
      ..calibrationFactor = station.calibrationFactor
      ..thresholdCode = station.thresholdCode
      ..ascend = station.ascend
      ..triggerStamp = station.triggerStamp
      ..activity = station.activity
      ..isActive = station.isActive
      ..abnormalUpdateCount = station.abnormalUpdateCount
      ..detectState = station.detectState
      ..detectReason = station.detectReason
      ..recentLevel = List.of(station.recentLevel)
      ..lastUpdate = station.lastUpdate
      ..lastDataTime = station.lastDataTime
      ..lastReceivedAt = station.lastReceivedAt
      ..gifObservations.addAll(station.gifObservations)
      ..gifLayerQualityFlags.addAll({
        for (final entry in station.gifLayerQualityFlags.entries)
          entry.key: Set.of(entry.value),
      });

List<Object?> stationSnapshotValues(NiedStation station) => [
  station.id,
  station.code,
  station.name,
  station.coordinate.latitude,
  station.coordinate.longitude,
  station.network,
  station.prefecture,
  station.expireSeconds,
  station.defaultExpireSeconds,
  station.pixelX,
  station.pixelY,
  station.scanReliable,
  station.pixelClusterId,
  station.level,
  station.calibrationFactor,
  station.thresholdCode,
  station.ascend,
  station.triggerStamp,
  station.activity,
  station.isActive,
  station.abnormalUpdateCount,
  station.detectState,
  station.detectReason,
  List.of(station.recentLevel),
  for (final time in [
    station.lastUpdate,
    station.lastDataTime,
    station.lastReceivedAt,
  ])
    [time?.microsecondsSinceEpoch, time?.isUtc],
  {
    for (final entry in station.gifObservations.entries)
      entry.key: [
        entry.value.layer,
        entry.value.colorPosition,
        entry.value.shindo,
        entry.value.pga,
        entry.value.pgv,
        entry.value.pgd,
        entry.value.velocityResponse,
      ],
  },
  {
    for (final entry in station.gifLayerQualityFlags.entries)
      entry.key: Set.of(entry.value),
  },
  station.activeTimer,
];
