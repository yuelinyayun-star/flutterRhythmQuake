/// Numbered information follows the same precedence as EEW reports:
/// report sequence first, then the source's absolute publication time.
int? informationReportNumber(String? text) {
  final match = RegExp(r'^第\s*(\d+)\s*[報报]').firstMatch(text?.trim() ?? '');
  final number = int.tryParse(match?.group(1) ?? '');
  return number != null && number > 0 ? number : null;
}

int? compareInformationReportOrder({
  required int? currentNumber,
  required int? incomingNumber,
  DateTime? currentTime,
  DateTime? incomingTime,
}) {
  if (currentNumber != null && incomingNumber != null) {
    final sequence = incomingNumber.compareTo(currentNumber);
    if (sequence != 0) return sequence;
  } else if (currentNumber != null) {
    return -1;
  }
  if (currentTime != null && incomingTime != null) {
    return incomingTime.compareTo(currentTime);
  }
  if (currentTime != null && incomingTime == null) return -1;
  return null;
}
