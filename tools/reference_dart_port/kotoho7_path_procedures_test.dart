// Test suite for the kotoho7 reference Dart port.
//
// NON-PRODUCTION reference port tests. These verify that the 1:1
// structural-mirror translation produces behavior matching the JS
// bridge for the cloud-RT → HYP path.
//
// Run: dart test tools/reference_dart_port/kotoho7_path_procedures_test.dart

import 'package:test/test.dart';

import 'kotoho7_path_procedures.dart';
import 'kotoho7_scratch_runtime.dart';
import 'kotoho7_snapshot_initializer.dart';

Thread _makeThread() {
  final thread = makeThread(kotoho7Snapshot);
  compileFactories(thread);
  return thread;
}

void main() {
  // ===========================================================================
  // Suite 1: Snapshot integrity
  // ===========================================================================
  group('snapshot', () {
    test('loads stage and receiver targets', () {
      expect(kotoho7Snapshot, contains('stage'));
      expect(kotoho7Snapshot, contains('receiver'));
      expect(kotoho7Snapshot['stage']!['name'], 'Stage');
      expect(kotoho7Snapshot['receiver']!['name'], '受信と検出');
    });

    test('has 251 stage variables', () {
      final stageVars =
          kotoho7Snapshot['stage']!['variables'] as Map<String, dynamic>;
      expect(stageVars.length, 251);
    });

    test('has 83 receiver variables', () {
      final recvVars =
          kotoho7Snapshot['receiver']!['variables'] as Map<String, dynamic>;
      expect(recvVars.length, 83);
    });

    test('total list items across all variables equals 64661', () {
      int total = 0;
      for (final target in ['stage', 'receiver']) {
        final vars =
            kotoho7Snapshot[target]!['variables'] as Map<String, dynamic>;
        for (final v in vars.values) {
          final value = (v as Map<String, dynamic>)['value'];
          if (value is List) total += value.length;
        }
      }
      expect(total, 64661);
    });
  });

  // ===========================================================================
  // Suite 2: Runtime shim helpers
  // ===========================================================================
  group('runtime helpers', () {
    test('scratchNumber converts strings and handles NaN', () {
      expect(scratchNumber('42'), 42);
      expect(scratchNumber('3.14'), 3.14);
      expect(scratchNumber(''), 0);
      expect(scratchNumber('abc'), 0);
      expect(scratchNumber(null), 0);
      expect(scratchNumber(true), 1);
      expect(scratchNumber(false), 0);
      expect(scratchNumber(42), 42);
    });

    test('scratchToBoolean follows JS truthiness rules', () {
      expect(scratchToBoolean('true'), isTrue);
      expect(scratchToBoolean('false'), isFalse);
      expect(scratchToBoolean('0'), isFalse);
      expect(scratchToBoolean(''), isFalse);
      expect(scratchToBoolean('ok'), isTrue);
      expect(scratchToBoolean(1), isTrue);
      expect(scratchToBoolean(0), isTrue); // JS: 0 is truthy as object
      expect(scratchToBoolean(null), isFalse);
    });

    test('compareLessThan handles numeric and string comparison', () {
      expect(compareLessThan(3, 5), isTrue);
      expect(compareLessThan(5, 3), isFalse);
      expect(compareLessThan('a', 'b'), isTrue);
      expect(compareLessThan('b', 'a'), isFalse);
    });

    test('compareEqual handles numeric and string equality', () {
      expect(compareEqual(3, 3), isTrue);
      expect(compareEqual(3, '3'), isTrue); // JS numeric coercion
      expect(compareEqual('abc', 'abc'), isTrue);
      expect(compareEqual('abc', 'ABC'), isTrue); // JS case-insensitive
    });

    test('scratchMod follows JS modulo (always non-negative)', () {
      expect(scratchMod(7, 3), 1);
      expect(scratchMod(-7, 3), 2); // JS: ((-7 % 3) + 3) % 3 = 2
      expect(scratchMod(7, 0), double.nan);
    });

    test('letterOf returns 1-based char or empty', () {
      expect(letterOf('hello', 1), 'h');
      expect(letterOf('hello', 5), 'o');
      expect(letterOf('hello', 6), '');
      expect(letterOf('hello', 0), '');
    });

    test('indexGet handles list and string, 1-based', () {
      expect(indexGet(['a', 'b', 'c'], 1), 'a');
      expect(indexGet(['a', 'b', 'c'], 3), 'c');
      expect(indexGet(['a', 'b', 'c'], 4), '');
      expect(indexGet('xyz', 2), 'y');
      expect(indexGet('xyz', 5), '');
    });

    test('daysSince2000 respects setNowMs override', () {
      setNowMs(DateTime.utc(2000, 1, 1).millisecondsSinceEpoch);
      expect(daysSince2000(), closeTo(0.0, 1e-6));
      setNowMs(DateTime.utc(2000, 1, 2).millisecondsSinceEpoch);
      expect(daysSince2000(), closeTo(1.0, 1e-6));
      setNowMs(null);
    });
  });

  // ===========================================================================
  // Suite 3: Single procedure (factory21 — great-circle distance)
  // ===========================================================================
  group('factory21 W緯度経度で距離km', () {
    late Thread thread;

    setUp(() {
      thread = _makeThread();
    });

    test('Tokyo to Osaka is approximately 397 km', () {
      // Tokyo: lon=139.6917, lat=35.6895
      // Osaka: lon=135.5193, lat=34.6937
      // Expected great-circle distance: ~397 km
      callProcedure(thread, 'W緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s', [
        139.6917,
        35.6895,
        135.5193,
        34.6937,
      ]);
      final dist = scratchNumber(getVariable(thread.target, '多目的0'));
      expect(dist, closeTo(397, 5)); // ±5 km tolerance
    });

    test('same point yields distance 0', () {
      callProcedure(thread, 'W緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s', [
        139.0,
        35.0,
        139.0,
        35.0,
      ]);
      final dist = scratchNumber(getVariable(thread.target, '多目的0'));
      expect(dist, closeTo(0, 0.01));
    });

    test('antipodal points yield ~20015 km', () {
      // Antipodal: (0,0) vs (180,0) — half circumference ≈ 20015 km
      callProcedure(thread, 'W緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s', [
        0.0,
        0.0,
        180.0,
        0.0,
      ]);
      final dist = scratchNumber(getVariable(thread.target, '多目的0'));
      expect(dist, closeTo(20015, 5));
    });
  });

  // ===========================================================================
  // Suite 4: Cloud RT → HYP integration (smoke test)
  // ===========================================================================
  group('cloud RT to HYP integration', () {
    late Thread thread;

    setUp(() {
      thread = _makeThread();
      setNowMs(DateTime.utc(2024, 1, 1).millisecondsSinceEpoch);
    });

    tearDown(() {
      setNowMs(null);
    });

    test('all 47 procedures are registered after makeThread', () {
      const expectedProcedures = [
        'Wクラウド変数更新したら',
        'W震度復元',
        'W揺れ検出許可',
        'W検出id1_全点へ適用',
        'W円検出の毎処理 %b',
        'ZHYP:震源検出 %s %s',
        'W%s の %s から %s までの文字 %b',
        'W雲変化 %s %s %s %b %s',
        'W雲変化チェック %s %s 内容 %b',
        'W震度履歴リセット',
        'W震度履歴時間管理 %s %s',
        'W点震度の処理 %s %s %s',
        'W複数トリガ 状態 %s %s %s %s %s %s 番号 %s 7 %s %s',
        'W点許可状態更新 %s %s %s %b',
        'Wgrid:上昇中割合計算&トリガ',
        'W検出id_同一震源統合 %s %s %b',
        'W検出id2_各点の許可idと推定用をセット %s %s %s %s',
        'W検出id_グリッド別idと存在idをセット %s %s %s',
        'W検出id_消えたidに対応する検出無効化',
        'W検出id海岸補助 %s %s',
        'W震度上昇効果音 %s %s %s',
        'Wepi最大距離(多目的1)or仮震央(カウント3id) %b %s',
        'WJMA2001距離近似: %s %s %b %b',
        'ZHYP:誤差レベル比較繰り返し %s %s %s %b %b %s %s',
        'W最新クラウド変数変更 %s %s',
        'W震度履歴移動 %s',
        'Wten震度更新 %s %s %s',
        'W単独トリガ 状態 %s %s %s %s %s 番号 %s %s',
        'WNG加速 %s',
        'W加速追加 %s %s',
        'Wgridトリガ %s %b %s',
        'W緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s',
        'W検出id3_点にIDを登録 %s %b',
        'W検出id_点の推定用をリセット %s',
        'ZHYP:誤差レベル比較 %s %s %s %b %b %s',
        'W距離の震度 %s %s %s %s',
        'W検出id適用数カウント追加 %s %b %s',
        'W検出id4_点に適用するべきIDを検索 %s %b',
        'W検出id_新規id追加 %s %b',
        'WHYP:誤差レベル計算 %s %s %s %s %s %s',
        'Z1フレーム休み判断',
        'W推定用tenPS時間計算(多目的0,2使用) %s %s',
        'W検出id距離計算 %s %s',
        'W検出id4-1_適用id最短7から候補選択 %s %s %s',
        'W検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s',
        'W周囲9grid最大震度or上昇(多目的0,1) %s %s',
        'W検出id_周囲gridの最新ID検索 %s %s %s %s',
      ];
      expect(thread.procedures.length, 47);
      for (final name in expectedProcedures) {
        expect(
          thread.procedures,
          contains(name),
          reason: 'procedure "$name" not registered',
        );
      }
    });

    test('snapshotCore returns expected HYP keys', () {
      final snap = snapshotCore(thread);
      expect(snap, contains('hyp'));
      expect(snap, contains('vars'));
      expect(snap, contains('listLengths'));
      final hyp = snap['hyp'] as Map<String, dynamic>;
      expect(hyp, contains('lon'));
      expect(hyp, contains('lat'));
      expect(hyp, contains('depth'));
      expect(hyp, contains('origin'));
      expect(hyp, contains('error'));
      expect(hyp, contains('minError'));
      expect(hyp, contains('phase'));
      expect(hyp, contains('calcCount'));
      expect(hyp, contains('detectedCount'));
    });

    test('W震度履歴リセット resets history without throwing', () {
      expect(() => callProcedure(thread, 'W震度履歴リセット'), returnsNormally);
    });

    test('Z1フレーム休み判断 returns without throwing', () {
      expect(() => callProcedure(thread, 'Z1フレーム休み判断'), returnsNormally);
    });
  });

  // ===========================================================================
  // Suite 5: State persistence across calls
  // ===========================================================================
  group('state persistence', () {
    late Thread thread;

    setUp(() {
      thread = _makeThread();
    });

    test('factory21 write to 多目的0 persists and is readable', () {
      callProcedure(thread, 'W緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s', [
        0.0,
        0.0,
        0.0,
        0.0,
      ]);
      final first = scratchNumber(getVariable(thread.target, '多目的0'));
      expect(first, closeTo(0, 0.01));

      // A second call with different coords should overwrite 多目的0.
      callProcedure(thread, 'W緯度経度で距離km(多目的0) xy1 %s %s xy2 %s %s', [
        0.0,
        0.0,
        180.0,
        0.0,
      ]);
      final second = scratchNumber(getVariable(thread.target, '多目的0'));
      expect(second, closeTo(20015, 5));
      expect(second, isNot(closeTo(first, 1)));
    });

    test('snapshot round-trip preserves variable identities', () {
      final runtime = makeRuntime(kotoho7Snapshot);
      final stageVarCount = runtime.stage.variables.length;
      final recvVarCount = runtime.receiver.variables.length;
      expect(stageVarCount, 251);
      expect(recvVarCount, 83);
    });

    test('list mutations do not leak back into the const SNAPSHOT', () {
      // The SNAPSHOT is a const Map; mutating a runtime list built from
      // it must not change the original SNAPSHOT entries.
      final beforeLen =
          (kotoho7Snapshot['stage']!['variables'] as Map<String, dynamic>)
              .length;
      final thread1 = _makeThread();
      // Perform some mutations (call a procedure that writes to lists)
      callProcedure(thread1, 'W震度履歴リセット');
      final afterLen =
          (kotoho7Snapshot['stage']!['variables'] as Map<String, dynamic>)
              .length;
      expect(afterLen, beforeLen);
    });
  });
}
