/// No-op implementation for platforms without dart:io (web).
class FieldDiagnostics {
  FieldDiagnostics._();

  static const bool enabled = false;

  static Future<void> start() async {}

  static void event(String name, [Map<String, Object?>? fields]) {}
}
