// GENERATED: Strict 1:1 structural-mirror Dart port of procedures #33-#47.
// Source: tools/_extracted_path_procedures.js lines 1898-2569
// See kotoho7_path_procedures.dart header for the full mapping table.

import 'dart:math' as math;

import 'kotoho7_scratch_runtime.dart';

num or0(Object? x) {
  final n = scratchNumber(x);
  return (n == 0 || n.isNaN) ? 0 : n;
}

// ============================================================================
// Procedure 33: W検出id3_点にIDを登録 %s %b (factory168)
// JS: function factory168(thread) { ... return function fun90___id3___ID_____ (p0,p1) { ... }; }
// Source: tools/_extracted_path_procedures.js L1898-L1935
// ============================================================================
void _factory168(Thread thread) {
  final target = thread.target;
  final runtime = target.runtime;
  final stage = runtime.getTargetForStage();
  final b0 = stage.variables['`eNpRtm9s@jEX@igP0L`']!;
  final b1 = stage.variables['?3O+o;-ScK5B^xw[i2hW']!;
  final b2 = target.variables['~bN)\$e(,5@XqMp|2IRDw']!;
  final b3 = stage.variables['rkKG{p^hgg)UI#A}J)_v']!;
  final b4 = stage.variables['BA~yAWP\$oF[gq,?.U[kG']!;
  final b5 = stage.variables['=JPx=2Bx`ODTh1-EguI2']!;
  final b6 = stage.variables['w(#nQ9k*#@6t_FYZ-Ku=']!;
  thread.procedures['W検出id3_点にIDを登録 %s %b'] = (args) {
    // fun90___id3___ID_____ — JS: function fun90___id3___ID_____ (p0,p1)
    final p0 = args[0];
    final p1 = args[1];
    if (!compareEqual(
      indexGet(b0.value, or0(or0(or0(or0(p0) - 1) * 10) + 3)),
      '',
    )) {
      callProcedure(thread, 'W検出id適用数カウント追加 %s %b %s', [p0, !false, -1]);
    }
    if (((runtime.ioDevices['clock']!.projectTimer() < 10) &&
        (0 < (b1.value as List).length))) {
      b2.value = ((b1.value as List).length / 20);
    } else {
      callProcedure(thread, 'W検出id4_点に適用するべきIDを検索 %s %b', [p0, p1]);
    }
    if (compareLessThan(0, b2.value)) {
      listReplace(b0, or0(or0(or0(or0(p0) - 1) * 10) + 3), b2.value);
    } else {
      if (!compareLessThan(b2.value, 0)) {
        if (runtime.ioDevices['keyboard']!.getKeyIsDown('l')) {}
        callProcedure(thread, 'W検出id_新規id追加 %s %b', [p0, p1]);
        listReplace(
          b0,
          or0(or0(or0(or0(p0) - 1) * 10) + 3),
          ((b1.value as List).length / 20),
        );
      } else {
        callProcedure(thread, 'W検出id_点の推定用をリセット %s', [p0]);
        return '';
      }
    }
    listReplace(
      b3,
      listGetList(b4.value as List<Object?>, p0),
      indexGet(b0.value, or0(or0(or0(or0(p0) - 1) * 10) + 3)),
    );
    listReplace(
      b5,
      listGetList(b4.value as List<Object?>, p0),
      indexGet(b6.value, 1),
    );
    callProcedure(thread, 'W検出id適用数カウント追加 %s %b %s', [p0, !false, 1]);
    return '';
  };
}

// ============================================================================
// Procedure 34: W検出id_点の推定用をリセット %s (factory169)
// JS: function factory169(thread) { ... return function fun91___id____________ (p0) { ... }; }
// Source: tools/_extracted_path_procedures.js L1936-L1951
// ============================================================================
void _factory169(Thread thread) {
  final target = thread.target;
  final runtime = target.runtime;
  final stage = runtime.getTargetForStage();
  final b0 = stage.variables['`eNpRtm9s@jEX@igP0L`']!;
  thread.procedures['W検出id_点の推定用をリセット %s'] = (args) {
    // fun91___id____________ — JS: function fun91___id____________ (p0)
    final p0 = args[0];
    listReplace(b0, or0(or0(or0(or0(p0) - 1) * 10) + 1), '');
    listReplace(b0, or0(or0(or0(or0(p0) - 1) * 10) + 2), '');
    callProcedure(thread, 'W検出id適用数カウント追加 %s %b %s', [p0, 'false', -1]);
    listReplace(b0, or0(or0(or0(or0(p0) - 1) * 10) + 3), '');
    listReplace(b0, or0(or0(or0(or0(p0) - 1) * 10) + 4), '');
    listReplace(b0, or0(or0(or0(or0(p0) - 1) * 10) + 6), '');
    listReplace(b0, or0(or0(or0(or0(p0) - 1) * 10) + 7), '');
    listReplace(b0, or0(or0(or0(or0(p0) - 1) * 10) + 8), '');
    return '';
  };
}
