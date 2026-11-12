import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../models/obs_automation_preset.dart';
import 'native_obs_automation_policy_types.dart';
import 'native_obs_automation_policy_portable.dart' as portable;
import 'sources/native_station_core_library_io.dart';
export 'native_obs_automation_policy_types.dart';

abstract final class NativeObsAutomationPolicy {
  static bool get supported => StationCoreLibrary.supported;
  static final _api = _Bindings();
  static int get outputs => supported ? _api.outputs() : 0;
  static int get calls => supported ? _api.calls() : 0;

  static List<int> missingShakeAlertRules(List<ObsAutomationPreset> presets) {
    if (!supported) {
      return portable.NativeObsAutomationPolicy.missingShakeAlertRules(presets);
    }
    return (_request({
              'op': 'missingShakeAlertRules',
              'presets': presets.map((preset) => preset.toJson()).toList(),
            })
            as List)
        .cast<int>();
  }

  static List<ObsEnabledRules> select(List<ObsAutomationPreset> presets) {
    if (!supported) return portable.NativeObsAutomationPolicy.select(presets);
    final decoded = _request({
      'presets': presets.map((preset) => preset.toJson()).toList(),
    });
    return [
      for (final row in decoded as List)
        (
          presetIndex: row['presetIndex'] as int,
          stackIndices: (row['stackIndices'] as List).cast<int>(),
        ),
    ];
  }

  static bool sourceMatches(
    String? source,
    String expected,
    String operator, {
    bool isJmaLpgm = false,
  }) {
    if (!supported) {
      return portable.NativeObsAutomationPolicy.sourceMatches(
        source,
        expected,
        operator,
        isJmaLpgm: isJmaLpgm,
      );
    }
    return (_request({
              'op': 'sourceMatch',
              'source': source,
              'expected': expected,
              'operator': operator,
              'isJmaLpgm': isJmaLpgm,
            })
            as Map)['matches']
        as bool;
  }

  static Map<String, dynamic> tsunamiProjection(Map<String, dynamic> message) {
    if (!supported) {
      return portable.NativeObsAutomationPolicy.tsunamiProjection(message);
    }
    return Map<String, dynamic>.from(
      _request({'op': 'tsunamiProjection', 'message': message}) as Map,
    );
  }

  static dynamic _request(Map<String, dynamic> request) {
    final bytes = JsonUtf8Encoder().convert(request);
    return using((arena) {
      final input = arena<Uint8>(bytes.length);
      final length = arena<Size>();
      input.asTypedList(bytes.length).setAll(0, bytes);
      final output = _api.select(input, bytes.length, length);
      if (output == nullptr) throw StateError('Rust OBS rule selection failed');
      try {
        final decoded = jsonDecode(
          utf8.decode(output.asTypedList(length.value)),
        );
        if (decoded is Map && decoded['error'] != null) {
          throw StateError('Rust OBS policy: ${decoded['error']}');
        }
        return decoded;
      } finally {
        _api.free(output, length.value);
      }
    });
  }
}

class _Bindings {
  final library = StationCoreLibrary.library;
  late final select = library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Size, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Size>)
      >('rq_obs_automation_select');
  late final free = library
      .lookupFunction<
        Void Function(Pointer<Uint8>, Size),
        void Function(Pointer<Uint8>, int)
      >('rq_obs_automation_free');
  late final outputs = library
      .lookupFunction<Uint64 Function(), int Function()>(
        'rq_obs_automation_outputs',
      );
  late final calls = library.lookupFunction<Uint64 Function(), int Function()>(
    'rq_obs_automation_calls',
  );
}
