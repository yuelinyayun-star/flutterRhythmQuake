import 'dart:convert';
import 'dart:io';

import 'kotoho7_js_eew_bridge_models.dart';

Kotoho7JsBridgeResult kotoho7JsCircleTrigger(
  Kotoho7JsCircleTriggerInput input,
) {
  final scriptPath = input.scriptPath ?? 'tools/kotoho7_cloud_eew_bridge.js';
  final script = File(scriptPath);
  if (!script.existsSync()) {
    return Kotoho7JsBridgeResult.unavailable(
      'kotoho7_js_bridge_script_not_found:$scriptPath',
    );
  }

  ProcessResult result;
  try {
    result = Process.runSync(
      'node',
      [scriptPath, jsonEncode(input.toJson())],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on Object catch (error) {
    return Kotoho7JsBridgeResult.unavailable(
      'kotoho7_js_bridge_process_error:$error',
    );
  }

  final stdoutText = result.stdout?.toString() ?? '';
  if (result.exitCode != 0) {
    return Kotoho7JsBridgeResult(
      ok: false,
      available: true,
      error:
          'kotoho7_js_bridge_exit_${result.exitCode}:'
          '${result.stderr?.toString() ?? stdoutText}',
    );
  }

  try {
    final decoded = jsonDecode(stdoutText);
    if (decoded is! Map) {
      return const Kotoho7JsBridgeResult(
        ok: false,
        available: true,
        error: 'kotoho7_js_bridge_stdout_not_object',
      );
    }
    return Kotoho7JsBridgeResult.fromJson(objectMap(decoded));
  } on Object catch (error) {
    return Kotoho7JsBridgeResult(
      ok: false,
      available: true,
      error: 'kotoho7_js_bridge_json_error:$error',
    );
  }
}
