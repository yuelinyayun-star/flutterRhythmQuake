// GENERATED: Strict 1:1 structural-mirror Dart port of procedures #1-#6.
// Source: tools/_extracted_path_procedures.js lines 3-533
// See kotoho7_path_procedures.dart header for the full mapping table.

import 'dart:math' as math;

import 'kotoho7_scratch_runtime.dart';

num or0(Object? x) {
  final n = scratchNumber(x);
  return (n == 0 || n.isNaN) ? 0 : n;
}

// ============================================================================
// Procedure 1: Wクラウド変数更新したら (factory91)
// JS: function factory91(thread) { ... return function* gen36____________ () { ... }; }
// Source: tools/_extracted_path_procedures.js L3-L189
// ============================================================================
void _factory91(Thread thread) {
  final target = thread.target;
  final runtime = target.runtime;
  final stage = runtime.getTargetForStage();
  final b0 = stage.variables['5]%SOR^uyht9y!H;o-O8']!;
  final b1 = target.variables['LSk^z:1T8%_ss8]Ux_xm']!;
  final b2 = stage.variables['sDxK7oJ4qK@VD-/xcgq-']!;
  final b3 = stage.variables[',])D6W^HO1YB2g+m^vXU']!;
  final b4 = stage.variables['Orkw5weMR?pK8^W7w!s0']!;
  final b5 = stage.variables['G8#k[]!i0%0`Xp;\$^;wP']!;
  final b6 = stage.variables['Au;LF0vh{OY(?f^*Q*m|']!;
  final b7 = stage.variables['*\$*4IQG9uk/C=DA1~2Am']!;
  final b8 = stage.variables['{sR6,rYtD_PXkSn*+,I~']!;
  final b9 = stage.variables['4~VhCURq^qSGYZk[0n#V']!;
  final b10 = target.variables['*m8qDcgr/phnB5oFAX*j']!;
  final b11 = target.variables['e_g^rDIUuXE|]H|A^Z2g']!;
  final b12 = stage.variables['qM{_c9Qzrq.,\$j.enLYz']!;
  final b13 = target.variables['V\$M{0^.%oXP_#PQ=O27{']!;
  final b14 = stage.variables['pPs(Dg^SmS.v8*,O[yUP']!;
  final b15 = stage.variables['|-\$]i?VXM:wz}RW[R0@W']!;
  final b16 = stage.variables['tgB[I#TDXGYW%MO6PtCs']!;
  final b17 = stage.variables['2YG,eY%UG]7O{_Jnx)V!']!;
  final b18 = stage.variables['0w[!vD-hLI9euPb!+CyB']!;
  final b19 = stage.variables['*d]U{q-4,0WOovd0md?V']!;
  final b20 = target.variables['B8n:I^y:xgyV6QTk9EZ}']!;
  final b21 = stage.variables['S);6DYiuwZThkbJbh/u^']!;
  final b22 = target.variables['^bO4NH+QG=O_p//.)mA1']!;
  final b23 = target.variables['P=JbM#SY%t;:`}W)1J5a']!;
  final b24 = target.variables['r-?LO={DRz/48KK|k)lp']!;
  thread.procedures['Wクラウド変数更新したら'] = (args) {
    // gen36____________ — JS: function* gen36____________ ()
    if ((256 < (b0.value.toString()).length)) {
      b1.value = 'ok';
    } else {
      b1.value = letterOf(b2.value, 1);
      if (compareEqual(b1.value, letterOf(b3.value, 1))) {
        if (compareEqual(b1.value, letterOf(b4.value, 1))) {
          if (compareEqual(b1.value, letterOf(b5.value, 1))) {
            if (compareEqual(b1.value, letterOf(b6.value, 1))) {
              if (compareEqual(b1.value, letterOf(b7.value, 1))) {
                if (compareEqual(b1.value, letterOf(b8.value, 1))) {
                  if (compareEqual(b1.value, letterOf(b9.value, 1))) {
                    if (compareEqual(b1.value, letterOf(b0.value, 45))) {
                      b1.value = 'ok';
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    if ((b1.value.toString().toLowerCase() == 'ok'.toLowerCase())) {
      callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b0.value, 1, 10, 'false']);
      if (!compareEqual((b1.value.toString() + (letterOf(b0.value, 45) + letterOf(b0.value, 50))), b10.value)) {
        b10.value = (b1.value.toString() + (letterOf(b0.value, 45) + letterOf(b0.value, 50)));
        b11.value = b1.value;
        if (compareEqual(b12.value, 0)) {
          b13.value = b1.value;
          listReplace(b14, 11, daysSince2000());
          if ((256 < (b0.value.toString()).length)) {
            callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b0.value, 263, 274, 'false']);
            if ((scratchToBoolean(indexGet(b15.value, 70)) && (3600 < (scratchNumber(or0(b16.value))).abs()))) {
            } else {
              if ((3 < (scratchNumber(or0(or0(or0(daysSince2000() * 86400) + or0(b16.value)) - or0(or0(b1.value) / 1000)))).abs())) {
                b16.value = (or0(or0(b1.value) / 1000) - or0(daysSince2000() * 86400));
              } else {
                b16.value = (or0(b16.value) + or0(or0(or0(or0(or0(b1.value) / 1000) - or0(daysSince2000() * 86400)) - or0(b16.value)) / 6));
              }
            }
            if (false) {
            } else {
              if (!compareEqual(letterOf(b0.value, 275), b17.value)) {
                b17.value = letterOf(b0.value, 275);
                startHats('event_whenbroadcastreceived', { 'BROADCAST_OPTION': '強震制限更新' });
              }
            }
          } else {
            if ((60 < (scratchNumber(or0(or0(b16.value) - (scratchNumber(or0(or0(or0(b1.value) - or0(daysSince2000() * 86400)) + 0))).floor()))).abs())) {
              b16.value = (scratchNumber(or0(or0(or0(b1.value) - or0(daysSince2000() * 86400)) + 0))).floor();
            } else {
              if ((2 < (scratchNumber(or0(or0(b16.value) - (scratchNumber(or0(or0(or0(b1.value) - or0(daysSince2000() * 86400)) + 2))).floor()))).abs())) {
                b16.value = (scratchNumber(or0(or0(or0(b1.value) - or0(daysSince2000() * 86400)) + 2))).floor();
              }
            }
            if (compareLessThan(b17.value, 0)) {
              b17.value = (scratchNumber(b17.value)).abs();
              startHats('event_whenbroadcastreceived', { 'BROADCAST_OPTION': '強震制限更新' });
            }
          }
        }
        callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b0.value, 11, 50, 'false']);
        callProcedure(thread, 'W雲変化 %s %s %s %b %s', [b11.value, b1.value, 2, !compareEqual(scratchMod(or0(b11.value), 10), 0), '']);
        callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b0.value, 43, 44, 'false']);
        b18.value = b1.value;
        callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b0.value, 51, 256, 'false']);
        callProcedure(thread, 'W雲変化 %s %s %s %b %s', [b11.value, b1.value, 5, !compareEqual(scratchMod(or0(b11.value), 10), 0), '']);
        if ((256 < (b0.value.toString()).length)) {
          callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b0.value, 257, 259, 'false']);
          b19.value = (0 + or0(b1.value));
          if ((scratchMod(or0(or0(b13.value) + 20), 40) < 4)) {
            if ((or0(b20.value) == 999)) {
              b20.value = (4 + or0(scratchMod(or0(runtime.ext_scratch3_operators.random(scratchRandomFloat(-2000, 2000), scratchRandomFloat(-2000, 2000))), 1) * 30));
            }
          } else {
            if ((scratchMod(or0(or0(b13.value) + 20), 40) < 37)) {
              if (compareLessThan(b20.value, scratchMod(or0(or0(b13.value) + 20), 40))) {
                b21.value = (b22.value.toString() + ((0 + or0(indexGet(b15.value, 61))).toString() + (b23.value.toString() + ('' + ('' + ('' + ''))))));
                runtime.ioDevices['cloud']!.requestUpdateVariable('☁ c2u', b21.value);
                b20.value = 999;
              }
            }
          }
        } else {
          if ((scratchMod(or0(or0(b13.value) + 20), 40) < 4)) {
            if ((or0(b20.value) == 999)) {
              b20.value = (4 + or0(scratchMod(or0(runtime.ext_scratch3_operators.random(scratchRandomFloat(-2000, 2000), scratchRandomFloat(-2000, 2000))), 1) * 30));
            }
            if (!compareEqual(b21.value, 0)) {
              b21.value = 0;
              runtime.ioDevices['cloud']!.requestUpdateVariable('☁ c2u', b21.value);
            }
          } else {
            if ((scratchMod(or0(or0(b13.value) + 20), 40) < 37)) {
              if (compareLessThan(b20.value, scratchMod(or0(or0(b13.value) + 20), 40))) {
                b21.value = (or0(b21.value) + 1);
                runtime.ioDevices['cloud']!.requestUpdateVariable('☁ c2u', b21.value);
                b20.value = 999;
              }
            } else {
              b19.value = b21.value;
            }
          }
          callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b2.value, 2, 256, 'false']);
          b24.value = b1.value;
          callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b3.value, 2, 256, 'false']);
          b24.value = (b24.value.toString() + b1.value.toString());
          callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b4.value, 2, 256, 'false']);
          b24.value = (b24.value.toString() + b1.value.toString());
          callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b5.value, 2, 256, 'false']);
          b24.value = (b24.value.toString() + b1.value.toString());
          callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b6.value, 2, 256, 'false']);
          b24.value = (b24.value.toString() + b1.value.toString());
          callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b7.value, 2, 256, 'false']);
          b24.value = (b24.value.toString() + b1.value.toString());
          callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b8.value, 2, 256, 'false']);
          b24.value = (b24.value.toString() + b1.value.toString());
          callProcedure(thread, 'W%s の %s から %s までの文字 %b', [b9.value, 2, 256, 'false']);
          b24.value = (b24.value.toString() + b1.value.toString());
          if (compareEqual(letterOf(b0.value, 50), 0)) {
            callProcedure(thread, 'W雲変化 %s %s %s %b %s', [b11.value, b24.value, 3, '', '']);
          } else {
            if ((or0(letterOf(b0.value, 50)) == 1)) {
              callProcedure(thread, 'W雲変化 %s %s %s %b %s', [b11.value, b24.value, 4, '', '']);
            } else {
              if ((or0(letterOf(b0.value, 50)) == 2)) {
                callProcedure(thread, 'W雲変化 %s %s %s %b %s', [b11.value, b24.value, 6, !false, '']);
              } else {
                if ((or0(letterOf(b0.value, 50)) == 3)) {
                } else {
                  if ((or0(letterOf(b0.value, 50)) == 4)) {
                    callProcedure(thread, 'W雲変化 %s %s %s %b %s', [b11.value, b24.value, 8, '', '']);
                  } else {
                    if ((or0(letterOf(b0.value, 50)) == 5)) {
                      callProcedure(thread, 'W雲変化 %s %s %s %b %s', [b11.value, b24.value, 7, !false, '']);
                    } else {
                      if ((or0(letterOf(b0.value, 50)) == 6)) {
                        callProcedure(thread, 'W雲変化 %s %s %s %b %s', [b11.value, b24.value, 9, !false, '']);
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      if ((256 < (b0.value.toString()).length)) {
        callProcedure(thread, 'W雲変化チェック %s %s 内容 %b', [b2.value, 3, 'false']);  // yield*
        callProcedure(thread, 'W雲変化チェック %s %s 内容 %b', [b3.value, 4, 'false']);  // yield*
        callProcedure(thread, 'W雲変化チェック %s %s 内容 %b', [b4.value, 6, !false]);  // yield*
        callProcedure(thread, 'W雲変化チェック %s %s 内容 %b', [b6.value, 8, 'false']);  // yield*
        callProcedure(thread, 'W雲変化チェック %s %s 内容 %b', [b7.value, 7, !false]);  // yield*
        callProcedure(thread, 'W雲変化チェック %s %s 内容 %b', [b8.value, 9, !false]);  // yield*
      }
    }
    return '';
  };
}

// ============================================================================
// Procedure 4: W検出id1_全点へ適用 (factory162)
// JS: function factory162(thread) { ... return function fun84___id1______ () { ... }; }
// Source: tools/_extracted_path_procedures.js L306-L385
// ============================================================================
void _factory162(Thread thread) {
  final target = thread.target;
  final runtime = target.runtime;
  final stage = runtime.getTargetForStage();
  final b0 = target.variables[')5M=db;SK)cguY*ueqHD']!;
  final b1 = stage.variables['K=dB~/Qs0QP8?S-nu[mN']!;
  final b2 = stage.variables['KCECrVs;pLwx/(9hj.!)']!;
  final b3 = stage.variables['Ji1-e,bGkERCj*Iyh9Mb']!;
  final b4 = stage.variables['\$cjV99dtvSV(8m5!Qv/Q']!;
  final b5 = stage.variables['rkKG{p^hgg)UI#A}J)_v']!;
  final b6 = stage.variables['?3O+o;-ScK5B^xw[i2hW']!;
  final b7 = stage.variables['=JPx=2Bx`ODTh1-EguI2']!;
  final b8 = stage.variables['w(#nQ9k*#@6t_FYZ-Ku=']!;
  final b9 = target.variables['~bN)\$e(,5@XqMp|2IRDw']!;
  final b10 = stage.variables['`eNpRtm9s@jEX@igP0L`']!;
  final b11 = target.variables['Yc3.A8VWi~HC?uz3TzsF']!;
  final b12 = stage.variables['t%ofjB[rJ`j4l!SKSLyL']!;
  final b13 = stage.variables['a2{*m(q6TnFclX9Ot^rW']!;
  final b14 = stage.variables['j)bQdNA;*o13ZKRlPCgG']!;
  final b15 = stage.variables['uc97C!W~0aVf80T|BZhi']!;
  final b16 = stage.variables['BA~yAWP\$oF[gq,?.U[kG']!;
  final b17 = target.variables['WDsK_h|jFINR5#GrDcRV']!;
  final b18 = target.variables['3uoW]i;{vIp1Xyu~*0em']!;
  thread.procedures['W検出id1_全点へ適用'] = (args) {
    // fun84___id1______ — JS: function fun84___id1______ ()
    callProcedure(thread, 'W検出id_同一震源統合 %s %s %b', ['', '', 'false']);
    b0.value = 1;
    for (var a0 = (b1.value as List).length; a0 >= 0.5; a0--) {
      callProcedure(thread, 'W検出id2_各点の許可idと推定用をセット %s %s %s %s', [b0.value, indexGet(b2.value, b0.value), indexGet(b3.value, b0.value), (1 + or0(14 * or0(or0(b0.value) - 1)))]);
      b0.value = (or0(b0.value) + 1);
    }
    callProcedure(thread, 'W検出id_グリッド別idと存在idをセット %s %s %s', ['', '', '']);
    callProcedure(thread, 'W検出id_消えたidに対応する検出無効化');
    b0.value = 1;
    for (var a1 = (b4.value as List).length; a1 >= 0.5; a1--) {
      if (compareLessThan(0, indexGet(b5.value, indexGet(b4.value, b0.value)))) {
        if ((!scratchToBoolean(indexGet(b6.value, or0(or0(or0(or0(indexGet(b5.value, indexGet(b4.value, b0.value))) - 1) * 20) + 2))) || compareLessThan(indexGet(b7.value, indexGet(b4.value, b0.value)), indexGet(b8.value, 1)))) {
          listReplace(b5, indexGet(b4.value, b0.value), '');
          listReplace(b7, indexGet(b4.value, b0.value), 0);
        }
      }
      callProcedure(thread, 'W検出id海岸補助 %s %s', [indexGet(b4.value, b0.value), (or0(indexGet(b4.value, b0.value)) + 1)]);
      callProcedure(thread, 'W検出id海岸補助 %s %s', [indexGet(b4.value, b0.value), (or0(indexGet(b4.value, b0.value)) - 1)]);
      callProcedure(thread, 'W検出id海岸補助 %s %s', [indexGet(b4.value, b0.value), (or0(indexGet(b4.value, b0.value)) + 23)]);
      callProcedure(thread, 'W検出id海岸補助 %s %s', [indexGet(b4.value, b0.value), (or0(indexGet(b4.value, b0.value)) - 23)]);
      b0.value = (or0(b0.value) + 1);
    }
    b0.value = 0;
    b9.value = 1;
    for (var a2 = (b1.value as List).length; a2 >= 0.5; a2--) {
      if (!compareEqual(indexGet(b10.value, or0(or0(or0(b0.value) * 10) + 1)), '')) {
        b9.value = (or0(b9.value) + 1);
      }
      if (!compareEqual(indexGet(b10.value, or0(or0(or0(b0.value) * 10) + 3)), '')) {
        b11.value = (or0(or0(or0(indexGet(b10.value, or0(or0(or0(b0.value) * 10) + 3))) - 1)) * 20);
        if ((compareEqual(letterOf(indexGet(b6.value, or0(or0(b11.value) + 8)), 2), 0) || (compareLessThan(2, indexGet(b13.value, or0(60 + or0(indexGet(b12.value, or0(or0(b0.value) + 1)))))) || compareLessThan(3, indexGet(b6.value, or0(or0(b11.value) + 4)))))) {
          if (compareLessThan(indexGet(b6.value, or0(or0(b11.value) + 6)), indexGet(b13.value, or0(60 + or0(indexGet(b12.value, or0(or0(b0.value) + 1))))))) {
            if ((compareLessThan(indexGet(b15.value, or0(or0(or0(b0.value) * 10) + or0(indexGet(b14.value, 12)))), indexGet(b15.value, or0(or0(or0(b0.value) * 10) + 1))) && (compareLessThan(9, indexGet(b12.value, or0(or0(b0.value) + 1))) || compareLessThan(indexGet(b17.value, indexGet(b16.value, or0(or0(b0.value) + 1))), -1)))) {
              listReplace(b6, (or0(b11.value) + 6), indexGet(b13.value, or0(60 + or0(indexGet(b12.value, or0(or0(b0.value) + 1))))));
              if ((or0(indexGet(b6.value, or0(or0(b11.value) + 7))) == -3)) {
                callProcedure(thread, 'W震度上昇効果音 %s %s %s', [-4, indexGet(b6.value, or0(or0(b11.value) + 6)), (or0(b0.value) + 1)]);
              } else {
                callProcedure(thread, 'W震度上昇効果音 %s %s %s', [indexGet(b6.value, or0(or0(b11.value) + 7)), indexGet(b6.value, or0(or0(b11.value) + 6)), (or0(b0.value) + 1)]);
              }
            }
          }
        }
      }
      b0.value = (or0(b0.value) + 1);
    }
    listReplace(b18, 15, b9.value);
    b0.value = 0;
    while (((b6.value as List).length >= (or0(or0(b0.value) * 20) + 1))) {
      if (scratchToBoolean(indexGet(b6.value, or0(or0(or0(b0.value) * 20) + 2)))) {
        if (compareLessThan(indexGet(b6.value, or0(or0(or0(b0.value) * 20) + 4)), 2)) {
          listReplace(b6, (or0(or0(b0.value) * 20) + 2), (0 == 1));
        }
      }
      b0.value = (or0(b0.value) + 1);
    }
    return '';
  };
}

// ============================================================================
// Procedure 3: W揺れ検出許可 (factory69)
// JS: function factory69(thread) { ... return function fun38_______ () { ... }; }
// Source: tools/_extracted_path_procedures.js L274-L304
// ============================================================================
void _factory69(Thread thread) {
  final target = thread.target;
  final runtime = target.runtime;
  final stage = runtime.getTargetForStage();
  final b0 = stage.variables['|-\$]i?VXM:wz}RW[R0@W']!;
  final b1 = target.variables[')5M=db;SK)cguY*ueqHD']!;
  final b2 = stage.variables['K=dB~/Qs0QP8?S-nu[mN']!;
  final b3 = stage.variables['MG0Ndm+d0MZj|S.;jWTy']!;
  final b4 = stage.variables['a2{*m(q6TnFclX9Ot^rW']!;
  final b5 = stage.variables['KCECrVs;pLwx/(9hj.!)']!;
  final b6 = stage.variables['m@xP0^2O,fQ)v0G,WV!W']!;
  final b7 = stage.variables['w(#nQ9k*#@6t_FYZ-Ku=']!;
  final b8 = stage.variables['h@DnYh@j/ZM)rvzDn.zE']!;
  final b9 = stage.variables['Ji1-e,bGkERCj*Iyh9Mb']!;
  thread.procedures['W揺れ検出許可'] = (args) {
    // fun38_______ — JS: function fun38_______ ()
    if (scratchToBoolean(indexGet(b0.value, 62))) {
      b1.value = 1;
      for (var a0 = (b2.value as List).length; a0 >= 0.5; a0--) {
        callProcedure(thread, 'W複数トリガ 状態 %s %s %s %s %s %s 番号 %s 7 %s %s', [indexGet(b4.value, indexGet(b3.value, b1.value)), indexGet(b5.value, b1.value), (0 + or0(letterOf(indexGet(b6.value, b1.value), 2))), (0 + or0(letterOf(indexGet(b6.value, b1.value), 1))), (or0(indexGet(b7.value, 1)) - or0(indexGet(b8.value, b1.value))), indexGet(b9.value, b1.value), b1.value, (1 + (14 * or0(or0(b1.value) - 1))), (0 + or0(letterOf(indexGet(b6.value, b1.value), 3)))]);
        if (scratchToBoolean(indexGet(b0.value, 54))) {
          if (compareLessThan(0.5, indexGet(b4.value, indexGet(b3.value, b1.value)))) {
            if (compareLessThan(indexGet(b9.value, b1.value), 5)) {
              callProcedure(thread, 'W点許可状態更新 %s %s %s %b', [b1.value, 5, 'test', 'false']);
            }
          }
        }
        b1.value = (or0(b1.value) + 1);
      }
      callProcedure(thread, 'Wgrid:上昇中割合計算&トリガ');
    }
    return '';
  };
}

// ============================================================================
// Procedure 2: W震度復元 (factory216)
// JS: function factory216(thread) { ... return function fun110_____ () { ... }; }
// Source: tools/_extracted_path_procedures.js L191-L272
// ============================================================================
void _factory216(Thread thread) {
  final target = thread.target;
  final runtime = target.runtime;
  final stage = runtime.getTargetForStage();
  final b0 = stage.variables['w(#nQ9k*#@6t_FYZ-Ku=']!;
  final b1 = target.variables[')5M=db;SK)cguY*ueqHD']!;
  final b2 = stage.variables['Ae(nkga~tubxi^N;eJ~Q']!;
  final b3 = target.variables['-wWa,0Ku)G51Mljm,*}Z']!;
  final b4 = stage.variables['pPs(Dg^SmS.v8*,O[yUP']!;
  final b5 = stage.variables['ZCr:M!/uqY;Dw9jN{5Th']!;
  final b6 = target.variables['Yc3.A8VWi~HC?uz3TzsF']!;
  final b7 = target.variables['5,6.Rr.Zsi6H12mU.E2R']!;
  final b8 = target.variables['?nVl]xf~kOseiCQpj~3M']!;
  final b9 = stage.variables['|-\$]i?VXM:wz}RW[R0@W']!;
  final b10 = target.variables['?|!~XT,6R1%bazDyKR5;']!;
  thread.procedures['W震度復元'] = (args) {
    // fun110_____ — JS: function fun110_____ ()
    if (((indexGet(b0.value, 3)).toString().length == 2040)) {
      b1.value = (2 * (or0((scratchNumber(or0(letterOf(indexGet(b0.value, 3), 31)) / 4)) == 1 ? 1 : 0)));
      if (!compareEqual(b2.value, b1.value)) {
        b2.value = b1.value;
        callProcedure(thread, 'W震度履歴リセット');
      }
      callProcedure(thread, 'W震度履歴時間管理 %s %s', ['', '']);
      b1.value = 0;
      b3.value = 0;
      listReplace(b4, 4, 0);
      listReplace(b5, 13, 0);
      for (var a0 = 738; a0 >= 0.5; a0--) {
        b6.value = ((letterOf(indexGet(b0.value, 3), or0(or0(or0(b1.value) * 3) + 1)) + letterOf(indexGet(b0.value, 3), or0(or0(or0(b1.value) * 3) + 2))) + letterOf(indexGet(b0.value, 3), or0(or0(or0(b1.value) * 3) + 3)));
        if (compareLessThan(961, b6.value)) {
          return '';
        }
        callProcedure(thread, 'W点震度の処理 %s %s %s', [(or0(indexGet(b7.value, or0(1 + or0(or0(b1.value) * 2)))) - 1), scratchMod(or0(b6.value), 31), '']);
        callProcedure(thread, 'W点震度の処理 %s %s %s', [(or0(indexGet(b7.value, or0(2 + or0(or0(b1.value) * 2)))) - 1), (scratchNumber(or0(or0((letterOf(indexGet(b0.value, 3), or0(or0(or0(b1.value) * 3) + 1)) + letterOf(indexGet(b0.value, 3), or0(or0(or0(b1.value) * 3) + 2))) + letterOf(indexGet(b0.value, 3), or0(or0(or0(b1.value) * 3) + 3))) / 31))).floor(), '']);
        b1.value = (or0(b1.value) + 1);
      }
      if (!compareEqual(b3.value, 0)) {
        b8.value = daysSince2000();
      }
    }
    if (((3500 < (indexGet(b0.value, 3)).toString().length) && (scratchToBoolean(indexGet(b9.value, 70)) || ((indexGet(b0.value, 3)).toString().length < 3600)))) {
      b1.value = letterOf(indexGet(b0.value, 3), 30);
      if (!compareEqual(b2.value, b1.value)) {
        b2.value = b1.value;
        callProcedure(thread, 'W震度履歴リセット');
      }
      callProcedure(thread, 'W震度履歴時間管理 %s %s', ['', '']);
      b1.value = 0;
      b3.value = 0;
      listReplace(b4, 4, 0);
      listReplace(b5, 13, 0);
      while ((indexGet(b0.value, 3)).toString().length >= (32 + or0(or0(b1.value) * 2))) {
        b6.value = (0 + or0(scratchNumber(letterOf(indexGet(b0.value, 3), or0(31 + or0(or0(b1.value) * 2))) + letterOf(indexGet(b0.value, 3), or0(32 + or0(or0(b1.value) * 2))))));
        if ((compareLessThan(b6.value, 99))) {
          b10.value = (or0(or0(b6.value) - 30) / 10);
          if (compareLessThan(b6.value, 15)) {
            b6.value = (1 + (scratchNumber(or0(or0(b6.value) * 0.2))).floor());
          } else {
            if (compareLessThan(b6.value, 75)) {
              b6.value = (4 + (scratchNumber(or0(or0(or0(b6.value) - 15) * 0.3))).floor());
            } else {
              if (compareLessThan(b6.value, 95)) {
                b6.value = (22 + (scratchNumber(or0(or0(or0(b6.value) - 75) * 0.4))).floor());
              } else {
                b6.value = 30;
              }
            }
          }
          callProcedure(thread, 'W点震度の処理 %s %s %s', [b1.value, b6.value, b10.value]);
        } else {
          callProcedure(thread, 'W点震度の処理 %s %s %s', [b1.value, 0, '-3.0']);
        }
        b1.value = (or0(b1.value) + 1);
      }
      if (!compareEqual(b3.value, 0)) {
        b8.value = daysSince2000();
      }
      if ((compareLessThan(indexGet(b5.value, 16), 10) && compareLessThan(100, indexGet(b5.value, 13)))) {
        callProcedure(thread, 'W震度履歴リセット');
      }
    }
    return '';
  };
}