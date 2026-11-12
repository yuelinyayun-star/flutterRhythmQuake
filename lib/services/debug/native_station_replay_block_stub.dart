import '../../models/station_history_frame.dart';

class NativeStationReplayBlock {
  static bool get supported => false;
  static (List<StationHistoryFrame>, int) decode(Map block) =>
      throw UnsupportedError('Native replay archive');
  static Future<(List<StationHistoryFrame>, int)> decodeAsync(Map block) =>
      throw UnsupportedError('Native replay archive');
}
