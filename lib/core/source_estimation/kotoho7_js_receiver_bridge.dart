import 'kotoho7_js_receiver_bridge_models.dart';
import 'kotoho7_js_receiver_bridge_stub.dart'
    if (dart.library.io) 'kotoho7_js_receiver_bridge_io.dart';

export 'kotoho7_js_receiver_bridge_models.dart';

abstract class Kotoho7JsReceiverBridge {
  static Kotoho7ReceiverBridgeResult run(Kotoho7ReceiverBridgeInput input) {
    return kotoho7JsReceiverBridge(input);
  }

  static Kotoho7ReceiverBridgeResult? latest(String sessionKey) {
    return kotoho7JsReceiverBridgeLatest(sessionKey);
  }

  static Kotoho7ReceiverBridgeQueueStatus queueStatus() {
    return kotoho7JsReceiverBridgeQueueStatus();
  }

  static void clearSessions() {
    kotoho7JsReceiverBridgeClearSessions();
  }

  /// Tear down persistent WebView2 used by the JS receiver (native heap).
  static Future<void> disposePersistentRuntime() {
    return kotoho7JsReceiverBridgeDisposePersistent();
  }
}
