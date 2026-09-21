import '../../models/jma_volcano_site.dart';
import '../../models/volcano_event_data.dart';
import 'quake_time.dart';

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
    JmaVolcanoSite? officialSite,
  }) {
    if (volcano.isProvisionalCommentary) return provisional;
    return forLevel(
      levelForVolcanoEvent(
        volcano,
        alertLevel: alertLevel,
        officialSite: officialSite,
      ),
    );
  }

  static int levelForVolcanoEvent(
    VolcanoEventData volcano, {
    int alertLevel = 0,
    JmaVolcanoSite? officialSite,
  }) {
    final code = volcano.volcanoCode.trim();
    final site = code.isNotEmpty && officialSite?.code == code
        ? officialSite
        : null;
    final knownLevel = site?.alertLevel ?? alertLevel;
    final reportedLevel = volcano.isCanceled ? null : volcano.parsedAlertLevel;
    if (reportedLevel == null) return knownLevel;
    final warningTime = site?.warningReportTime;
    final reportTime = volcano.reportTime;
    // Adapters store JMA bulletin clocks as JST components, not UTC instants.
    if (warningTime != null &&
        reportTime != null &&
        warningTime.isAfter(
          QuakeTime.wallClockToUtc(reportTime, const Duration(hours: 9)),
        )) {
      return knownLevel;
    }
    return reportedLevel;
  }

  static String forSite(JmaVolcanoSite site) {
    if (site.hasProvisionalInfo) return provisional;
    return forLevel(site.alertLevel);
  }
}
