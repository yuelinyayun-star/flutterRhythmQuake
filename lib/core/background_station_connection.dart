/// Station feeds that can be paused independently on Android.
enum BackgroundStationConnection {
  nied('NIED 強震モニタ'),
  kma('KMA 实时测站'),
  snet('S-net'),
  trem('TREM RTS'),
  seisjs('Wolfx SeisJS'),
  palert('P-Alert'),
  lpgm('NIED 長周期地震動モニタ'),
  fdsn('FDSN / SeedLink'),
  fssn('FSSN 实时测站');

  const BackgroundStationConnection(this.label);

  final String label;

  bool get hostedByForegroundService => this != fssn;

  String get preferenceKey => 'background_station_${name}_enabled';

  bool readEnabled(bool? Function(String) read) => read(preferenceKey) ?? false;

  static Set<BackgroundStationConnection> paused({
    required bool uiVisible,
    required bool? Function(String) read,
  }) => {
    if (!uiVisible)
      for (final connection in values)
        if (!connection.readEnabled(read)) connection,
  };
}
