import 'dart:js_interop';

@JS('rqStartup.stage')
external void _setStage(JSString stage);

void setWebStartupStage(String stage) => _setStage(stage.toJS);
