class AppEdition {
  static const String name = String.fromEnvironment(
    'RQ_EDITION',
    defaultValue: 'personal',
  );

  static const bool isPublic = name == 'public';
  static const bool hasPAlertStations = !isPublic;
  static const bool hasGlobalQuake = !isPublic;
  static const bool hasIcl = !isPublic;

  static bool allowsUnifiedSource(String source) {
    if (!hasGlobalQuake && source == 'globalQuakeEew') return false;
    if (!hasIcl && source == 'iclEew') return false;
    return true;
  }
}
