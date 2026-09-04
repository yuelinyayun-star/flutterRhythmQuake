// GENERATED: Strict 1:1 structural-mirror Dart port of procedure #5.
import 'kotoho7_scratch_runtime.dart';

num or0(Object? x) {
  final n = scratchNumber(x);
  return (n == 0 || n.isNaN) ? 0 : n;
}

// === W円検出の毎処理 %b ===
void _factory182(Thread thread) {
  final target = thread.target;
  final runtime = target.runtime;
  final stage = runtime.getTargetForStage();
  final b0 = stage.variables['|-\$]i?VXM:wz}RW[R0@W']!;
  final b1 = stage.variables['?3O+o;-ScK5B^xw[i2hW']!;
  final b2 = target.variables['e_g^rDIUuXE|]H|A^Z2g']!;
  final b3 = target.variables['?|!~XT,6R1%bazDyKR5;']!;
  final b4 = stage.variables['tgB[I#TDXGYW%MO6PtCs']!;
  final b5 = stage.variables['t7pn]wqZ:,L``t2Y(:y6']!;
  final b6 = target.variables['fXl.Y#hvGzT8_j7KisLy']!;
  final b7 = target.variables['Yc3.A8VWi~HC?uz3TzsF']!;
  thread.procedures['W円検出の毎処理 %b'] = (args) {
    // fun101_________ — JS: function fun101_________ (p0)
    final p0 = args[0];
    if (scratchToBoolean(indexGet(b0.value, 62))) {
      if (scratchToBoolean(indexGet(b0.value, 51))) {
        if ((0 < (b1.value as List).length)) {
          b2.value = 0;
          for (var a0 = or0((b1.value as List).length / 20); a0 >= 0.5; a0--) {
            if (scratchToBoolean(indexGet(b1.value, or0(or0(b2.value) + 2)))) {
              if (scratchToBoolean(p0)) {
                callProcedure(thread, 'Wepi最大距離(多目的1)or仮震央(カウント3id) %b %s', [
                  'false',
                  (1 + (or0(or0(b2.value) / 20)).floor()),
                ]);
                if (compareLessThan(b3.value, 20)) {
                  listReplace(b1, (or0(b2.value) + 10), 25);
                } else {
                  listReplace(b1, (or0(b2.value) + 10), (or0(b3.value) + 5));
                }
              }
              if ((scratchToBoolean(indexGet(b0.value, 52)) &&
                  scratchToBoolean(indexGet(b0.value, 57)))) {
                if ((compareLessThan(
                      2,
                      indexGet(b1.value, or0(or0(b2.value) + 4)),
                    ) &&
                    (or0(or0(daysSince2000() * 86400) + or0(b4.value)) -
                            or0(
                              indexGet(
                                b5.value,
                                or0(or0(or0(b2.value) / 2) + 5),
                              ),
                            ) <
                        300))) {
                  callProcedure(thread, 'WJMA2001距離近似: %s %s %b %b', [
                    or0(or0(daysSince2000() * 86400) + or0(b4.value)) -
                        or0(
                          indexGet(b5.value, or0(or0(or0(b2.value) / 2) + 5)),
                        ),
                    indexGet(b5.value, or0(or0(or0(b2.value) / 2) + 4)),
                    !false,
                    'false',
                  ]);
                  listReplace(b5, (or0(or0(b2.value) / 2) + 6), b6.value);
                  callProcedure(thread, 'WJMA2001距離近似: %s %s %b %b', [
                    or0(or0(daysSince2000() * 86400) + or0(b4.value)) -
                        or0(
                          indexGet(b5.value, or0(or0(or0(b2.value) / 2) + 5)),
                        ),
                    indexGet(b5.value, or0(or0(or0(b2.value) / 2) + 4)),
                    '',
                    'false',
                  ]);
                  listReplace(b5, (or0(or0(b2.value) / 2) + 7), b6.value);
                } else {
                  if (compareLessThan(
                    2,
                    indexGet(b1.value, or0(or0(b2.value) + 4)),
                  )) {
                    listReplace(b5, (or0(or0(b2.value) / 2) + 6), 999999);
                    listReplace(b5, (or0(or0(b2.value) / 2) + 7), 999999);
                  } else {
                    listReplace(b5, (or0(or0(b2.value) / 2) + 6), '');
                    listReplace(b5, (or0(or0(b2.value) / 2) + 7), '');
                  }
                }
                if ((or0(indexGet(b0.value, 21)) == 3)) {
                  b7.value = indexGet(b1.value, or0(or0(b2.value) + 10));
                  if (compareLessThan(
                    b7.value,
                    indexGet(b5.value, or0(or0(or0(b2.value) / 2) + 7)),
                  )) {
                    listReplace(b5, (or0(or0(b2.value) / 2) + 6), 0);
                    listReplace(b5, (or0(or0(b2.value) / 2) + 7), b7.value);
                  } else {
                    if (compareLessThan(
                      b7.value,
                      indexGet(b5.value, or0(or0(or0(b2.value) / 2) + 6)),
                    )) {
                      listReplace(b5, (or0(or0(b2.value) / 2) + 6), b7.value);
                    }
                  }
                }
              } else {
                listReplace(b5, (or0(or0(b2.value) / 2) + 6), 0);
                listReplace(
                  b5,
                  (or0(or0(b2.value) / 2) + 7),
                  indexGet(b1.value, or0(or0(b2.value) + 10)),
                );
              }
            }
            b2.value = (or0(b2.value) + 20);
          }
        }
      }
    }
    return '';
  };
}
