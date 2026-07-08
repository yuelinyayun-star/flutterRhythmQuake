import 'kotoho7_js_receiver_bridge_models.dart';

Kotoho7ReceiverBridgeResult kotoho7JsReceiverBridge(
  Kotoho7ReceiverBridgeInput input,
) {
  return Kotoho7ReceiverBridgeResult.unavailable(
    'kotoho7_receiver_bridge_not_supported_on_this_platform',
  );
}

Kotoho7ReceiverBridgeResult? kotoho7JsReceiverBridgeLatest(String sessionKey) {
  return null;
}

Kotoho7ReceiverBridgeQueueStatus kotoho7JsReceiverBridgeQueueStatus() {
  return const Kotoho7ReceiverBridgeQueueStatus(
    pendingFrameCount: 0,
    inFlightSessionCount: 0,
    sessionCount: 0,
  );
}
