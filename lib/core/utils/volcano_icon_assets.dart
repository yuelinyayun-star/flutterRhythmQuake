import '../../models/jma_volcano_site.dart';
import '../../models/volcano_event_data.dart';

/// Shared volcano marker / card-badge artwork from `assets/images/volcano/`.
class VolcanoIconAssets {
  VolcanoIconAssets._();

  static const generic = 'assets/images/volcano/vol.png';
  static const provisional = 'assets/images/volcano/Temp.png';

  static String forLevel(int alertLevel) {
    if (alertLevel < 1 || alertLevel > 5) return generic;
    return 'assets/images/volcano/Lv$alertLevel.png';
  }

  static String forVolcanoEvent(
    VolcanoEventData volcano, {
    int alertLevel = 0,
  }) {
    if (volcano.isProvisionalCommentary) return provisional;
    return forLevel(volcano.parsedAlertLevel ?? alertLevel);
  }

  static String forSite(JmaVolcanoSite site) {
    if (site.hasProvisionalInfo) return provisional;
    return forLevel(site.alertLevel);
  }
}
