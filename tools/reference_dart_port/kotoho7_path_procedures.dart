// 1:1 Dart strict-structural-mirror port of the 47 procedure factories along
// the kotoho7 cloud-RT -> HYP path, extracted from:
//   tools/kotoho7_receiver_compiled_core.js (PROCEDURE_FACTORY_SOURCES,
//   lines 7-165) and dumped readably to:
//   tools/_extracted_path_procedures.js (47 procedures, ~2569 lines).
//
// NON-PRODUCTION reference port. Lives under tools/reference_dart_port/ and
// is NOT compiled into the Flutter app. Mirrors the JS factory functions
// verbatim: b0..bN aliases, factory function names, generator names
// (preserved as comments), parameter names p0..pN, control flow, and
// expression nesting.
//
// Translation rules (see .trae/documents/kotoho7-js-path-to-dart-port-resume.md):
//   +x || 0            -> or0(x)  (JS Number(x) with falsy->0 fallback)
//   ("" + x)           -> x.toString()
//   (("" + x))[(i|0)-1] || ""  -> letterOf(x, i)  (1-based char access)
//   value[(i|0)-1] ?? ""      -> indexGet(value, i)  (1-based list access)
//   (i | 0)            -> scratchNumber(i).truncate()
//   listGet(b.value, idx)     -> listGetList(b.value as List<Object?>, idx)
//   listReplace/Add/Insert/Delete/Contains/IndexOf -> same name
//   mod(a, b)          -> scratchMod(a, b)
//   toBoolean(x)       -> scratchToBoolean(x)
//   compareLessThan/GreaterThan/Equal -> same name
//   randomInt/Float    -> scratchRandomInt/scratchRandomFloat
//   daysSince2000()    -> daysSince2000()
//   timer()             -> timer()
//   Math.PI/sin/cos/acos/exp/log/sqrt -> math.pi/sin/cos/acos/exp/log/sqrt
//   (scratchNumber(x)      -> (scratchNumber(x)).round()
//   Math.floor(x)      -> (scratchNumber(x)).floor()
//   Math.abs(x)        -> (scratchNumber(x)).abs()
//   Math.max/min(a,b)  -> math.max/min(scratchNumber(a), scratchNumber(b))
//   Math.random()      -> math.Random().nextDouble()
//   runtime.ioDevices.keyboard.getKeyIsDown(k)
//                       -> runtime.ioDevices['keyboard']!.getKeyIsDown(k)
//   runtime.ioDevices.cloud.requestUpdateVariable(n, v)
//                       -> runtime.ioDevices['cloud']!.requestUpdateVariable(n, v)
//   runtime.requestRedraw()  -> runtime.requestRedraw()
//   runtime.ext_scratch3_operators._random(a, b)
//                       -> runtime.ext_scratch3_operators.random(a, b)
//   startHats(event, args)   -> startHats(event, args)
//   yield;             -> // yield  (runMaybeGenerator drains synchronously)
//   yield* thread.procedures["K"](args)
//                       -> callProcedure(thread, "K", args)  // yield*
//   thread.procedures["K"](args)  (no yield*)
//                       -> callProcedure(thread, "K", args)
//   !false             -> !false  (preserved literally)
//   "false"            -> "false"  (string, not boolean)
//
// Variable ID strings frequently contain `$` which triggers Dart string
// interpolation; all such IDs are escaped as `\$` in the literals below.

import 'dart:math' as math;

import 'kotoho7_scratch_runtime.dart';

/// Mirror of JS `expr || 0` for numeric expressions. JS `|| 0` returns 0
/// when the LHS is falsy (0, NaN, "", null, undefined, false). For num
/// inputs this means: NaN -> 0, 0 -> 0, other -> other. For non-num
/// inputs, scratchNumber already coerces to 0 for NaN/empty/non-numeric.
num or0(Object? x) {
  final n = scratchNumber(x);
  return (n == 0 || n.isNaN) ? 0 : n;
}

// ============================================================================
// Procedure 32: W緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s (factory21)
// JS: function factory21(thread) { ... return function fun8________km____0__xy1_ (p0,p1,p2,p3) { ... }; }
// Source: tools/_extracted_path_procedures.js L1889-1897
// ============================================================================
void _factory21(Thread thread) {
  final target = thread.target;
  final runtime = target.runtime;
  final stage = runtime.getTargetForStage();
  final b0 = target.variables['Yc3.A8VWi~HC?uz3TzsF']!;
  thread.procedures['W緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s'] = (args) {
    // fun8________km____0__xy1_ — JS: function fun8________km____0__xy1_ (p0,p1,p2,p3)
    final p0 = args[0];
    final p1 = args[1];
    final p2 = args[2];
    final p3 = args[3];
    b0.value = or0(
      111.31949 *
          (((math.acos(
                    (((((((scratchNumber(
                                  math.sin(
                                        (math.pi * scratchNumber(p1)) / 180,
                                      ) *
                                      1e10,
                                )).round() /
                                1e10)) *
                            ((scratchNumber(
                                  math.sin(
                                        (math.pi * scratchNumber(p3)) / 180,
                                      ) *
                                      1e10,
                                )).round() /
                                1e10))) +
                        ((((scratchNumber(
                                      math.cos(
                                            (math.pi * scratchNumber(p1)) / 180,
                                          ) *
                                          1e10,
                                    )).round() /
                                    1e10)) *
                                ((scratchNumber(
                                      math.cos(
                                            (math.pi * scratchNumber(p3)) / 180,
                                          ) *
                                          1e10,
                                    )).round() /
                                    1e10)) *
                            ((scratchNumber(
                                  math.cos(
                                        (math.pi *
                                                (scratchNumber(p0) -
                                                    scratchNumber(p2))) /
                                            180,
                                      ) *
                                      1e10,
                                )).round() /
                                1e10))),
                  )) *
                  180) /
              math.pi),
    );
    return '';
  };
}

// __INSERT_REMAINING_PROCEDURES_HERE__

// ============================================================================
// compileFactories — Mirror of JS `compileFactories(thread)` (line 66954).
// Registers all 47 path procedures into thread.procedures by calling
// each _factoryN(thread) in dependency order.
// ============================================================================
void compileFactories(Thread thread) {
  _factory91(thread);
  _factory216(thread);
  _factory69(thread);
  _factory162(thread);
  _factory182(thread);
  _factory267(thread);
  _factory31(thread);
  _factory92(thread);
  _factory93(thread);
  _factory217(thread);
  _factory218(thread);
  _factory219(thread);
  _factory70(thread);
  _factory71(thread);
  _factory72(thread);
  _factory163(thread);
  _factory164(thread);
  _factory165(thread);
  _factory166(thread);
  _factory167(thread);
  _factory85(thread);
  _factory183(thread);
  _factory22(thread);
  _factory18(thread);
  _factory94(thread);
  _factory220(thread);
  _factory221(thread);
  _factory80(thread);
  _factory73(thread);
  _factory74(thread);
  _factory75(thread);
  _factory21(thread);
  _factory168(thread);
  _factory169(thread);
  _factory19(thread);
  _factory55(thread);
  _factory170(thread);
  _factory171(thread);
  _factory172(thread);
  _factory20(thread);
  _factory16(thread);
  _factory173(thread);
  _factory174(thread);
  _factory175(thread);
  _factory176(thread);
  _factory177(thread);
  _factory178(thread);
}
