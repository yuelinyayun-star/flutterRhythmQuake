import '../intensity_class.dart';
import '../../models/unified_event_presentation.dart';
import '../../models/unified_quake_data.dart';
import 'quake_time.dart';

bool _isJianCea(UnifiedQuakeData event) =>
    event.isEew &&
    event.source == 'ceaEew' &&
    event.apiTypeLabel == 'Jian Project';

/// Derived effects only; never write estimates into the report or its payload.
int? jianCeaEstimatedIntensity(UnifiedQuakeData event) =>
    _isJianCea(event) ? estimatedNewApiEewBadgeIntensity(event) : null;

String effectiveEewIntensityText(UnifiedQuakeData event) =>
    unifiedEewIntensityValue(event);

String effectiveEewClassName(UnifiedQuakeData event) {
  final estimate = jianCeaEstimatedIntensity(event);
  return estimate == null
      ? event.className
      : intensityClassName(estimate.toDouble());
}

bool effectiveEewWarn(UnifiedQuakeData event) {
  if (!_isJianCea(event) || event.isWarn) return event.isWarn;
  if (event.isCanceled ||
      event.isAssumption ||
      event.isHistory ||
      event.sourcePayload?['isTraining'] == true ||
      event.sourcePayload?['isWarn'] is bool) {
    return false;
  }
  final value = double.tryParse(effectiveEewIntensityText(event));
  return value != null && value.isFinite && value >= 6.5 && value <= 12;
}

/// Same report numbers alone cannot order revisions from different APIs.
/// Accept a newer publication, or a missing-to-known intensity enrichment with
/// identical source parameters. A reconnect or a late empty report cannot undo it.
bool isJianCeaSameReportRevision(
  UnifiedQuakeData oldEvent,
  UnifiedQuakeData event,
) {
  if (!_isJianCea(oldEvent) ||
      !_isJianCea(event) ||
      oldEvent.origin != event.origin ||
      event.isSnapshot ||
      event.isHistory ||
      oldEvent.isCanceled ||
      event.isCanceled ||
      event.sourcePayload?['isTraining'] == true) {
    return false;
  }
  if (oldEvent.reportTime != null && event.reportTime != null) {
    return QuakeTime.unifiedInstantUtc(event, value: event.reportTime).isAfter(
      QuakeTime.unifiedInstantUtc(oldEvent, value: oldEvent.reportTime),
    );
  }
  final before = double.tryParse(oldEvent.maxIntensity);
  final after = double.tryParse(event.maxIntensity);
  return before == null &&
      after != null &&
      after.isFinite &&
      after >= 0 &&
      after <= 12 &&
      oldEvent.originTime != null &&
      event.originTime != null &&
      QuakeTime.unifiedInstantUtc(oldEvent) ==
          QuakeTime.unifiedInstantUtc(event) &&
      oldEvent.magnitude == event.magnitude &&
      oldEvent.depth == event.depth &&
      oldEvent.lat == event.lat &&
      oldEvent.lng == event.lng;
}
