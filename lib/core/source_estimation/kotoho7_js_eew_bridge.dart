import 'kotoho7_js_eew_bridge_models.dart';
import 'kotoho7_js_eew_bridge_stub.dart'
    if (dart.library.io) 'kotoho7_js_eew_bridge_io.dart';

export 'kotoho7_js_eew_bridge_models.dart';

abstract class Kotoho7JsEewBridge {
  static Kotoho7JsBridgeResult circleTrigger(
    Kotoho7JsCircleTriggerInput input,
  ) {
    return kotoho7JsCircleTrigger(input);
  }
}
