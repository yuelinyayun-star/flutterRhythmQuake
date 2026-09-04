import 'kotoho7_js_receiver_bridge_models.dart';

Kotoho7ReceiverBridgeResult kotoho7JsReceiverBridge(
  Kotoho7ReceiverBridgeInput input,
) {
  return const Kotoho7ReceiverBridgeResult(
    ok: false,
    available: false,
    error: 'kotoho7_receiver_bridge_disabled',
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

void kotoho7JsReceiverBridgeClearSessions() {}

Future<void> kotoho7JsReceiverBridgeDisposePersistent() async {}
