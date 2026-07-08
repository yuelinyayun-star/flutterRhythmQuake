// 1:1 Dart port of the Scratch/TurboWarp runtime shim that backs the
// kotoho7 receiver-core JS at:
//   d:\flutterApp\flutterrhythmquake\tools\kotoho7_receiver_compiled_core.js
// lines 66924-66962.
//
// This file is NON-PRODUCTION reference port. It lives under
// tools/reference_dart_port/ and is NOT compiled into the Flutter app.
// It mirrors the JS runtime helpers (scratchNumber / toBoolean /
// compareLessThan / mod / listGet / listReplace / letterOf / daysSince2000
// / startHats / etc.) and the Thread/Target/Runtime/Variable structures
// used by kotoho7_path_procedures.dart.
//
// Cloud variable input note: the JS bridge does NOT fetch cloud variables
// from a server. Cloud strings (☁ c2h / ☁ c2b0..c2b7) must be supplied
// externally as a parameter to the ported Wクラウド変数更新したら
// procedure. For real-time WebSocket acquisition, mirror the handshake in
// tools/probe_kotoho7_cloud_eew.py:215-266
// (wss://clouddata-srev.kothn.net / .turbowarp.org / .turbowarp.xyz,
// project_id kotoho7.github.io/srev).

import 'dart:math' as math;

/// Mirror of JS `cloneVariable` (line 66951). Lists are shallow-copied so
/// mutations during a procedure call do not leak back into the const
/// SNAPSHOT template.
class Variable {
  final String id;
  final String name;
  final String type; // "" scalar, "list" list, "broadcast_msg" broadcast
  Object? value;

  Variable(this.id, this.name, this.type, this.value);

  Variable clone() {
    final v = value;
    return Variable(id, name, type, v is List ? List<Object?>.of(v) : v);
  }
}

class Target {
  final String name;
  final Map<String, Variable> variables;
  late final Runtime runtime;

  Target(this.name, this.variables);

  String getName() => name;
}

class _KeyboardStub {
  bool getKeyIsDown(/* num | String */ dynamic key) => false;
}

class _ClockStub {
  num projectTimer() => 0;
  void resetProjectTimer() {}
}

class _MouseStub {
  num getScratchX() => 0;
  num getScratchY() => 0;
}

class _CloudStub {
  void requestUpdateVariable(String name, Object? value) {}
}

class _ExtScratch3Operators {
  /// Mirror of runtime.ext_scratch3_operators._random in JS makeRuntime
  /// (line 66953). JS delegates to randomInt(low, high) which floors.
  num random(num low, num high) => scratchRandomInt(low, high).toDouble();
}

class Runtime {
  late final Target stage;
  late final Target receiver;
  final Map<String, dynamic> ioDevices = {
    'keyboard': _KeyboardStub(),
    'clock': _ClockStub(),
    'mouse': _MouseStub(),
    'cloud': _CloudStub(),
  };
  final _ExtScratch3Operators ext_scratch3_operators = _ExtScratch3Operators();
  num currentMSecs = 0;

  Target getTargetForStage() => stage;
  dynamic getSpriteTargetByName(String _) => null;
  void requestRedraw() {}
  List startHats(String event, [Map<String, dynamic>? args]) => const [];
  void stopAll() {}
}

class _Timer {
  final num _startMs;
  _Timer() : _startMs = _currentMs();
  num timeElapsed() => _currentMs() - _startMs;
}

num _currentMs() => _overrideNowMs ?? DateTime.now().millisecondsSinceEpoch;

num? _overrideNowMs;

/// Mirror of JS `setNowMs` (line 66945). Pass null to clear override.
void setNowMs(Object? value) {
  _overrideNowMs = value == null ? null : scratchNumber(value);
}

/// Mirror of JS `scratchNumber` (line 66924): `Number(value)` with NaN -> 0.
num scratchNumber(Object? value) {
  if (value == null) return 0;
  if (value is num) return value;
  if (value is bool) return value ? 1 : 0;
  final s = value.toString();
  final n = num.tryParse(s);
  if (n != null) return n;
  // JS Number("  12  ") -> 12, Number("0x10") -> 16, Number("1e3") -> 1000.
  // Dart num.tryParse handles 1e3 but is stricter on whitespace/signs.
  final trimmed = s.trim();
  if (trimmed.isEmpty) return 0;
  final n2 = num.tryParse(trimmed);
  return n2 ?? 0;
}

/// Mirror of JS `toBoolean` (line 66925).
bool scratchToBoolean(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    return value != '' && value != '0' && value.toLowerCase() != 'false';
  }
  return value != null;
}

/// Mirror of JS `isNotActuallyZero` (line 66926). Detects string values
/// that Number() coerces to 0 but should compare as strings (empty, or
/// non-numeric like "0.0.0").
final RegExp _actuallyZeroRe = RegExp(r'^[-+]?0*(?:\.0*)?$');
bool isNotActuallyZero(Object? value) {
  if (value is! String) return false;
  return value.isEmpty || !_actuallyZeroRe.hasMatch(value);
}

bool _numericCompareOk(Object? a, Object? b) {
  final na = scratchNumber(a);
  final nb = scratchNumber(b);
  if (na.isNaN || nb.isNaN) return false;
  // JS: !(na === 0 && isNotActuallyZero(a)) && !(nb === 0 && isNotActuallyZero(b))
  if (na == 0 && isNotActuallyZero(a)) return false;
  if (nb == 0 && isNotActuallyZero(b)) return false;
  return true;
}

/// Mirror of JS `compareLessThan` (line 66927).
bool compareLessThan(Object? a, Object? b) {
  if (_numericCompareOk(a, b)) {
    return scratchNumber(a) < scratchNumber(b);
  }
  return a.toString().toLowerCase().compareTo(b.toString().toLowerCase()) < 0;
}

/// Mirror of JS `compareGreaterThan` (line 66928).
bool compareGreaterThan(Object? a, Object? b) {
  if (_numericCompareOk(a, b)) {
    return scratchNumber(a) > scratchNumber(b);
  }
  return a.toString().toLowerCase().compareTo(b.toString().toLowerCase()) > 0;
}

/// Mirror of JS `compareEqual` (line 66929).
bool compareEqual(Object? a, Object? b) {
  if (_numericCompareOk(a, b)) {
    return scratchNumber(a) == scratchNumber(b);
  }
  return a.toString().toLowerCase() == b.toString().toLowerCase();
}

/// Mirror of JS `mod` (line 66930).
num scratchMod(Object? a, Object? b) {
  final nb = scratchNumber(b);
  if (nb == 0) return double.nan;
  final na = scratchNumber(a);
  return ((na % nb) + nb) % nb;
}

/// Mirror of JS `listIndex` (line 66931). Returns 1-based index or 0 if
/// out of range. 'last' -> length; 'random'/'any' -> 1+floor(rand*length).
int listIndex(Object? index, int length) {
  if (index == 'last') return length;
  if (index == 'random' || index == 'any') {
    return length > 0 ? 1 + math.Random().nextInt(length) : 0;
  }
  return scratchNumber(index).truncate();
}

/// Mirror of JS `listGet` (line 66932) for List inputs.
Object? listGetList(List<Object?> list, Object? index) {
  final i = listIndex(index, list.length);
  return (i < 1 || i > list.length) ? '' : (list[i - 1] ?? '');
}

/// Mirror of JS `listGet` for String inputs (Scratch also allows indexing
/// characters of a string variable as if it were a list of letters).
Object? listGetString(String s, Object? index) {
  final i = listIndex(index, s.length);
  return (i < 1 || i > s.length) ? '' : s[i - 1];
}

/// Mirror of JS `listReplace` (line 66933).
void listReplace(Variable variable, Object? index, Object? value) {
  final list = variable.value as List<Object?>;
  final i = listIndex(index, list.length);
  if (i >= 1 && i <= list.length) list[i - 1] = value;
}

/// Mirror of JS `listAdd` (line 66934).
void listAdd(Variable variable, Object? value) {
  (variable.value as List<Object?>).add(value);
}

/// Mirror of JS `listInsert` (line 66935).
void listInsert(Variable variable, Object? index, Object? value) {
  final list = variable.value as List<Object?>;
  int i = listIndex(index, list.length);
  if (i < 1) i = 1;
  if (i > list.length + 1) i = list.length + 1;
  list.insert(i - 1, value);
}

/// Mirror of JS `listDelete` (line 66936).
void listDelete(Variable variable, Object? index) {
  final list = variable.value as List<Object?>;
  if (index == 'all') {
    list.clear();
    return;
  }
  final i = listIndex(index, list.length);
  if (i >= 1 && i <= list.length) list.removeAt(i - 1);
}

/// Mirror of JS `listContains` (line 66937).
bool listContains(/* Variable | List */ dynamic variableOrList, Object? value) {
  final list = variableOrList is Variable
      ? variableOrList.value as List<Object?>
      : variableOrList as List<Object?>;
  return list.any((item) => compareEqual(item, value));
}

/// Mirror of JS `listIndexOf` (line 66938).
int listIndexOf(/* Variable | List */ dynamic variableOrList, Object? value) {
  final list = variableOrList is Variable
      ? variableOrList.value as List<Object?>
      : variableOrList as List<Object?>;
  for (int idx = 0; idx < list.length; idx++) {
    if (compareEqual(list[idx], value)) return idx + 1;
  }
  return 0;
}

/// Mirror of JS `letterOf` (line 66939). 1-based.
String letterOf(Object? value, Object? index) {
  final s = value.toString();
  final i = scratchNumber(index).truncate();
  return (i < 1 || i > s.length) ? '' : s[i - 1];
}

/// Mirror of JS `stringIncludes` (line 66940).
bool stringIncludes(Object? haystack, Object? needle) {
  return haystack.toString().contains(needle.toString());
}

/// Mirror of JS `timer` (line 66941).
_Timer timer() => _Timer();

/// Mirror of JS `randomInt` (line 66942).
int scratchRandomInt(Object? low, Object? high) {
  final lo = scratchNumber(low).ceil();
  final hi = scratchNumber(high).floor();
  return lo + math.Random().nextInt((hi - lo + 1).clamp(0, 1 << 31));
}

/// Mirror of JS `randomFloat` (line 66943).
double scratchRandomFloat(Object? low, Object? high) {
  final lo = scratchNumber(low).toDouble();
  final hi = scratchNumber(high).toDouble();
  return lo + math.Random().nextDouble() * (hi - lo);
}

/// Mirror of JS `daysSince2000` (line 66946). Honors setNowMs override.
double daysSince2000() {
  final now = _overrideNowMs ?? DateTime.now().millisecondsSinceEpoch;
  final epoch = DateTime.utc(2000, 1, 1).millisecondsSinceEpoch;
  return (now - epoch) / 86400000.0;
}

/// Mirror of JS `startHats` (line 66947): always returns empty list.
List startHats(String event, [Map<String, dynamic>? args]) => const [];

/// Mirror of JS `isStuck` (line 66948).
bool isStuck() => false;

/// Mirror of JS `executeInCompatibilityLayer` (line 66949). JS is a
/// generator returning '' synchronously; here we return '' directly.
String executeInCompatibilityLayer() => '';

/// Index-get helper that mirrors JS `value[i-1]` for both String and List
/// values, returning '' (Scratch's empty sentinel) on out-of-range.
/// Used pervasively in path procedures as `b0.value[i-1] ?? ""`.
Object? indexGet(Object? value, Object? index) {
  final i = scratchNumber(index).truncate();
  if (value is String) {
    return (i < 1 || i > value.length) ? '' : value[i - 1];
  }
  if (value is List) {
    return (i < 1 || i > value.length) ? '' : (value[i - 1] ?? '');
  }
  return '';
}

/// Index-set helper that mirrors JS `value[i-1] = x` for List values.
/// String values are immutable in Dart; in Scratch they are too (the JS
/// path never assigns into a string), so we only support List assignment.
void indexSet(Variable variable, Object? index, Object? value) {
  final list = variable.value as List<Object?>;
  final i = scratchNumber(index).truncate();
  if (i >= 1 && i <= list.length) list[i - 1] = value;
}

/// Mirror of JS `cloneVariable` (line 66951).
Variable cloneVariable(Variable v) => v.clone();

/// Mirror of JS `makeTarget` (line 66952).
Target makeTarget(
  Map<String, dynamic> snapshot,
  Runtime runtime,
) {
  final variables = <String, Variable>{};
  final vars = snapshot['variables'] as Map<String, dynamic>;
  for (final entry in vars.entries) {
    final v = entry.value as Map<String, dynamic>;
    final value = v['value'];
    variables[entry.key] = Variable(
      v['id'] as String,
      v['name'] as String,
      (v['type'] ?? '') as String,
      value is List
          ? List<Object?>.of(value)
          : value is num
              ? value
              : value?.toString(),
    );
  }
  final target = Target(snapshot['name'] as String, variables);
  target.runtime = runtime;
  return target;
}

/// Mirror of JS `makeRuntime` (line 66953). Populates stage and receiver
/// from `snapshot`, which is shaped like `{stage: {...}, receiver: {...}}`.
Runtime makeRuntime(Map<String, Map<String, dynamic>> snapshot) {
  final runtime = Runtime();
  runtime.stage = makeTarget(snapshot['stage']!, runtime);
  runtime.receiver = makeTarget(snapshot['receiver']!, runtime);
  return runtime;
}

/// Mirror of JS `variableByName` (line 66956).
Variable? variableByName(Target target, String name) {
  for (final v in target.variables.values) {
    if (v.name == name) return v;
  }
  return null;
}

/// Mirror of JS `setVariable` (line 66957).
void setVariable(Target target, String name, Object? value) {
  final v = variableByName(target, name);
  if (v == null) throw Exception('variable not found: $name');
  v.value = value;
}

/// Mirror of JS `getVariable` (line 66958).
Object? getVariable(Target target, String name) =>
    variableByName(target, name)?.value;

/// A procedure is a closure bound at factory-compile time. It captures
/// references to the Variable objects it reads/writes (b0..bN) so that
/// state mutations persist across calls within the same Thread.
typedef Procedure = Object? Function(List<Object?> args);

class Thread {
  final Target target;
  final Map<String, Procedure> procedures = {};
  _Timer? timer;
  Thread(this.target);
}

/// Mirror of JS `runMaybeGenerator` (line 66959). Our procedures are all
/// plain synchronous functions (yields are preserved as `// yield`
/// comments), so this just returns the value directly.
Object? runMaybeGenerator(Object? value) => value;

/// Mirror of JS `callProcedure` (line 66960).
Object? callProcedure(Thread thread, String key,
    [List<Object?> args = const []]) {
  final fn = thread.procedures[key];
  if (fn == null) throw Exception('procedure not found: $key');
  return runMaybeGenerator(fn(args));
}

/// Mirror of JS `snapshotCore` (line 66961). Reads back the post-run
/// state of HYP-relevant variables and list lengths for diagnostic
/// inspection / differential testing against the JS bridge output.
Map<String, dynamic> snapshotCore(Thread thread) {
  final t = thread.target;
  final stage = thread.target.runtime.stage;
  Object? read(String name) => getVariable(t, name);
  return {
    'hyp': {
      'lon': read('@hyp:震源候補 経度X'),
      'lat': read('@hyp:震源候補 緯度Y'),
      'depth': read('@hyp:震源候補 深さ'),
      'origin': read('@hyp:震源候補 発生時刻'),
      'error': read('@hyp:誤差レベル'),
      'minError': read('@hyp:最小誤差レベル'),
      'phase': read('@hyp:計算フェーズ'),
      'calcCount': read('@hyp:計算回数'),
      'detectedCount': read('@hyp:検知点数'),
    },
    'vars': {
      'multipurpose0': read('多目的0'),
      'multipurpose1': read('多目的1'),
      'multipurpose2': read('多目的2'),
      'jma': read('tjma:波震源距離or波走時'),
      'jma3': read('tjma3:波震央距離'),
    },
    'listLengths': {
      'tenX': (variableByName(stage, 'd ten:x')?.value as List?)?.length,
      'tenY': (variableByName(stage, 'd ten:y')?.value as List?)?.length,
      'sourceElements':
          (variableByName(stage, '4-4 検出id震源要素')?.value as List?)?.length,
      'detectionInfo':
          (variableByName(stage, '4-3 検出id別情報')?.value as List?)?.length,
    },
  };
}

/// Mirror of JS `makeThread` (line 66955). The JS version calls
/// `compileFactories(thread)` to register all 47 path procedures.
/// In this Dart port, `compileFactories` is defined in
/// `kotoho7_path_procedures.dart` (which imports this file), so the
/// caller must invoke it separately:
///
///     final thread = makeThread(snapshot);
///     compileFactories(thread);
///
/// This split avoids a circular import: the procedures file imports
/// the runtime types, but the runtime file does not import the
/// procedures file.
Thread makeThread(Map<String, Map<String, dynamic>> snapshot) {
  final runtime = makeRuntime(snapshot);
  final thread = Thread(runtime.receiver);
  return thread;
}
