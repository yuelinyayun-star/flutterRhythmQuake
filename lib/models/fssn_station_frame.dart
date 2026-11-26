class FssnStationReading {
  const FssnStationReading({
    required this.latitude,
    required this.longitude,
    required this.pga,
    required this.status,
    required this.argb,
  });

  final double latitude;
  final double longitude;
  final double? pga;
  final int status;
  final int argb;
}

class FssnStationFrame {
  const FssnStationFrame(this.unixSeconds, this.stations);
  final int unixSeconds;
  final List<FssnStationReading> stations;
}
