import 'dart:convert';
import 'json_wire_envelope.dart';
import 'palert_wire_values.dart';

class StationJsonDecoder {
  static bool get nativeSupported => false;
  StationJsonDecoder({
    bool preferNative = true,
    bool prepareStationNumbers = true,
  });
  List<String> _palertIds = const [];
  void setPAlertStations(Iterable<String> ids) {
    final next = List<String>.unmodifiable(ids);
    if (next.toSet().length != next.length) {
      throw ArgumentError('Duplicate P-Alert station IDs');
    }
    _palertIds = next;
  }

  PAlertWireResponse decodePAlertUtf8(
    List<int> input, {
    bool Function(dynamic)? shouldExtract,
  }) {
    final raw = jsonDecode(utf8.decode(input));
    return PAlertWireResponse(
      raw,
      shouldExtract == null || shouldExtract(raw)
          ? PAlertWireValues.fromJson(raw, _palertIds)
          : null,
    );
  }

  dynamic decode(String input) => jsonDecode(input);
  dynamic decodeUtf8(List<int> input) => jsonDecode(utf8.decode(input));
  dynamic decodeIngressUtf8(
    List<int> input, {
    bool allowMalformed = false,
    JsonWireEnvelope? envelope,
    String name = '',
  }) {
    final text = utf8.decode(input, allowMalformed: allowMalformed);
    return envelope == null
        ? jsonDecode(text)
        : decodeJsonWireEnvelope(text, envelope, name);
  }

  Iterable<dynamic> feedSseUtf8(List<int> input, {bool finish = false}) =>
      throw StateError('Native SSE requires native station core');
  dynamic decodeEnvelope(String input, JsonWireEnvelope kind, String name) =>
      decodeJsonWireEnvelope(input, kind, name);
  dynamic decodeEnvelopeUtf8(
    List<int> input,
    JsonWireEnvelope kind,
    String name,
  ) => decodeJsonWireEnvelope(utf8.decode(input), kind, name);
  void dispose() {
    _palertIds = const [];
  }

  static Map<String, int> get diagnostics => const {'sessions': 0, 'calls': 0};
  static Map<String, int> get palertDiagnostics => const {'calls': 0};
}
