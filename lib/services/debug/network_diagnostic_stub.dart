class NetworkDiagnostic {
  static bool get active => false;
  static void event(
    String transport,
    int id,
    String event,
    Map<String, dynamic> details, [
    List<int> bytes = const [],
  ]) {}
}
