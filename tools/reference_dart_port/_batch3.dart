// GENERATED: Strict 1:1 structural-mirror Dart port of procedure #6.
import 'dart:math' as math;
import 'kotoho7_scratch_runtime.dart';

num or0(Object? x) {
  final n = scratchNumber(x);
  return (n == 0 || n.isNaN) ? 0 : n;
}

// === ZHYP:震源検出 %s %s ===
void _factory267(Thread thread) {
  final target = thread.target;
  final runtime = target.runtime;
  final stage = runtime.getTargetForStage();
  final b0 = stage.variables['?3O+o;-ScK5B^xw[i2hW']!;
  final b1 = target.variables['ZM?sbwGCt6f8/M/sySub']!;
  final b2 = stage.variables['w(#nQ9k*#@6t_FYZ-Ku=']!;
  final b3 = target.variables['PWWC)I\$!N8;wLWbL24rD']!;
  final b4 = target.variables['E/6SBMA_tWdHUcr{^k9t']!;
  final b5 = target.variables['f%le!Gl+-3|.6S+p%{G?']!;
  final b6 = target.variables['T-XmxlUKDq|6vK%godm7']!;
  final b7 = stage.variables['t7pn]wqZ:,L``t2Y(:y6']!;
  final b8 = target.variables['k1m*+G#JNJIzT{!Xl\$/j']!;
  final b9 = stage.variables['K=dB~/Qs0QP8?S-nu[mN']!;
  final b10 = target.variables['Hq^CH1_5,,jrW_qVxd7i']!;
  final b11 = stage.variables['o}-u@H4`+v8X:~`A_r6%']!;
  final b12 = target.variables['SR0J\$lP0vs;z,(p^MzgX']!;
  final b13 = target.variables['iZ|NrCk%bkj[Coh06ft(']!;
  final b14 = target.variables['0M!7ebr+|;0IV|:*qHcl']!;
  final b15 = target.variables['(CEp}a4uCuGJoa^qwjIN']!;
  final b16 = target.variables['?|!~XT,6R1%bazDyKR5;']!;
  final b17 = target.variables['r-?LO={DRz/48KK|k)lp']!;
  final b18 = target.variables['Q6O,\$xU*XV=4TUprS!O}']!;
  final b19 = stage.variables['h3UE2P!9c=b4,*Hs,,=U']!;
  thread.procedures['ZHYP:震源検出 %s %s'] = (args) {
    // gen137_HYP_______ — JS: function* gen137_HYP_______ (p0,p1)
    final p0 = args[0];
    final p1 = args[1];
    if (scratchToBoolean(indexGet(b0.value, or0(or0(p1) + 2)))) {
      b1.value = indexGet(b0.value, or0(or0(p1) + 3));
      if ((or0(indexGet(b2.value, 1)) - or0(b1.value) < 120)) {
        b3.value = 'start';
        b4.value = indexGet(b0.value, or0(or0(p1) + 4));
        b5.value = (scratchNumber(or0(or0(or0(or0(indexGet(b0.value, or0(or0(p1) + 5))) * or0(or0(indexGet(b0.value, or0(or0(p1) + 5))) * indexGet(b0.value, or0(or0(p1) + 5))))) * or0(8 * math.pow(10, -5))) + 11))).round();
        b6.value = (scratchNumber(or0(or0(or0(0.3 * or0(or0(or0(indexGet(b0.value, or0(or0(p1) + 4))) * 10) + indexGet(b0.value, or0(or0(p1) + 5))))) + 50))).round();
        if ((compareEqual(indexGet(b7.value, or0(or0(or0(p1) / 2) + 2))), '') || (or0(indexGet(b2.value, 1)) - or0(b1.value) < 10))) {
          b8.value = ((scratchNumber(or0(or0(listGetList(b9.value as List<Object?>, indexGet(b0.value, or0(or0(p1) + 1)))) * 60))).round() / 60));
          b10.value = ((scratchNumber(or0(or0(listGetList(b11.value as List<Object?>, indexGet(b0.value, or0(or0(p1) + 1)))) * 60))).round() / 60));
          b12.value = 10;
          b13.value = (or0(b1.value) - 2);
        } else {
          b8.value = indexGet(b7.value, or0(or0(or0(p1) / 2) + 2));
          b10.value = indexGet(b7.value, or0(or0(or0(p1) / 2) + 3));
          b12.value = indexGet(b7.value, or0(or0(or0(p1) / 2) + 4));
          b13.value = indexGet(b7.value, or0(or0(or0(p1) / 2) + 5));
        }
        b14.value = (1 / 0);
        b15.value = 0;
        if (compareLessThan(10, indexGet(b0.value, or0(or0(p1) + 4)))) {
          b3.value = 'start-h2';
          // yield
          callProcedure(thread, 'ZHYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s', [p0, 0.5, '', !false, 'false', p1, (30 - or0(or0(or0(indexGet(b2.value, 1)) - or0(b1.value) < 5) * or0(15 + or0(14 * or0(compareLessThan(indexGet(b0.value, or0(or0(p1) + 4)), 10))))))]);
        }
        b3.value = 'start-h10';
        // yield
        callProcedure(thread, 'ZHYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s', [p0, 0.1, '', !false, 'false', p1, (80 - or0(or0(or0(indexGet(b2.value, 1)) - or0(b1.value) < 5) * or0(40 + or0(34 * or0(compareLessThan(indexGet(b0.value, or0(or0(p1) + 4)), 10))))))]);
        b3.value = 'start-h10-v50';
        // yield
        callProcedure(thread, 'ZHYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s', [p0, 0.1, 50, !false, !false, p1, 100]);
        b3.value = 'start-h10-v10';
        // yield
        callProcedure(thread, 'ZHYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s', [p0, 0.1, 10, !false, !false, p1, 100]);
        b3.value = 'start-h60';
        // yield
        callProcedure(thread, 'ZHYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s', [p0, (1 / 60), '', !false, 'false', p1, 10]);
        b3.value = 'end1';
        b16.value = (or0(or0(p0) - 1) * 10);
        b17.value = (or0(or0(p0) - 1) * 20);
        if ((compareLessThan(b14.value, (or0(indexGet(b0.value, or0(or0(b17.value) + 19))) * 1.7)) || (or0(indexGet(b2.value, 1)) - or0(b1.value) < 10))) {
          listReplace(b0, (or0(b17.value) + 8), ('2' + letterOf(indexGet(b0.value, or0(or0(b17.value) + 8)), 2)));
          if ((compareLessThan(b14.value, 250) && (or0(indexGet(b2.value, 1)) - or0(b1.value) < 10))) {
            listReplace(b0, (or0(b17.value) + 11), 250);
          } else {
            listReplace(b0, (or0(b17.value) + 11), b14.value);
            if (compareLessThan(b14.value, indexGet(b0.value, or0(or0(b17.value) + 19)))) {
              listReplace(b0, (or0(b17.value) + 19), b14.value);
            }
          }
          listReplace(b0, (or0(b17.value) + 12), b18.value);
          listReplace(b7, (or0(b16.value) + 2), ((scratchNumber(or0(or0(b8.value) * 60))).round() / 60));
          listReplace(b7, (or0(b16.value) + 3), ((scratchNumber(or0(or0(b10.value) * 60))).round() / 60));
          listReplace(b7, (or0(b16.value) + 4), (scratchNumber(or0(b12.value))).round());
          listReplace(b7, (or0(b16.value) + 5), (scratchNumber(or0(b13.value))).round());
          listReplace(b0, (or0(b17.value) + 18), indexGet(b2.value, 1));
        }
      }
    }
    b19.value = '';
    return '';
  };
}
