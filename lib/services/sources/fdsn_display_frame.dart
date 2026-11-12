import '../obs_automation_input_service.dart';
import 'fdsn_source_status.dart';
import 'fdsn_station_service.dart';

class FdsnDisplayFrame {
  const FdsnDisplayFrame({
    required this.revision,
    required this.stations,
    required this.automation,
    required this.statuses,
    required this.linked,
    required this.limit,
    required this.dataTime,
    required this.connected,
    required this.connections,
    required this.processingIsolate,
  });
  final int revision;
  final List<FdsnStation>? stations;
  final List<ObsStationInputSample> automation;
  final List<FdsnSourceStatus> statuses;
  final int linked, limit;
  final DateTime? dataTime;
  final bool connected;
  final List<Map<String, Object>> connections;
  final String? processingIsolate;
}
