import 'package:latlong2/latlong.dart';
import '../../core/calculator.dart';
import '../../models/quake_message.dart';
import '../../models/unified_quake_data.dart';
import '../../services/native_camera_focus.dart';

/// UI codec only. The source/type contract is evaluated by the Rust backend.
LatLng? informationFocusAnchor(
  UnifiedQuakeData? event,
  QuakeMessage mapEvent, {
  bool hasInformationFill = false,
}) {
  if (event == null) return null;
  final issue = event.sourcePayload?['issue'];
  final anchor =
      NativeCameraFocus.prepare({
            'op': 'informationAnchor',
            'source': event.source,
            'origin': event.origin,
            'issueType': issue is Map ? issue['type'] : '',
            'title': event.titleText,
            'isEew': event.isEew,
            'hasInformationFill': hasInformationFill,
            'locatable': QuakeCalculator.isUsableMapCoordinate(
              mapEvent.latitude,
              mapEvent.longitude,
            ),
          })
          as bool;
  return anchor ? LatLng(mapEvent.latitude, mapEvent.longitude) : null;
}
