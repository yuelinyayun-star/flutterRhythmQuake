import 'dart:math' as math;

/// JMA 30-step shindo scale (same as jp_shindo_scale.dart)
const scratchValues = [
  -3.0, -2.5, -2.0, -1.5, -1.17, -0.84, -0.5, -0.17, 0.16, 0.5,
  0.83, 1.16, 1.5, 1.83, 2.16, 2.5, 2.83, 3.16, 3.5, 3.83,
  4.16, 4.5, 4.75, 5.0, 5.25, 5.5, 5.75, 6.0, 6.25, 6.5,
];

double rawShindoFromLevel(int level) {
  if (level < 0) return -3.0;
  if (level >= scratchValues.length) return scratchValues.last;
  return scratchValues[level];
}

/// Our grid trigger: reference-aligned
class GridStats {
  int total = 0;
  int risingCount = 0;
  double score = 0;

  void addStation(int level, int thresholdCode, List<int> recentLevels) {
    total++;
    if (level < 0) return;
    final shindo = rawShindoFromLevel(level);
    if (shindo <= 0) return;

    // rise = latest level's rawShindo - older level's rawShindo
    double rise = 0;
    if (recentLevels.length >= 2 && recentLevels[0] >= 0) {
      for (int i = 1; i < math.min(recentLevels.length, 4); i++) {
        if (recentLevels[i] >= 0) {
          rise = shindo - rawShindoFromLevel(recentLevels[i]);
          break;
        }
      }
    }

    if (rise <= 0) return;
    risingCount++;

    // 連続上昇 bonus: latest > 2_steps_ago
    if (recentLevels.length >= 3 && recentLevels[0] >= 0 && recentLevels[2] >= 0 &&
        recentLevels[0] > recentLevels[2]) {
      score += 0.5;
    }

    // char1 bonus
    final c1 = thresholdCode ~/ 100 % 10;
    if (c1 < 3) {
      score += 5.0 / (c1 + 6);
    } else {
      score += 0.56;
    }

    // char2 bonus
    final c2 = (thresholdCode ~/ 10) % 10;
    if (c2 < 2) {
      score += 1.0 / (c2 + 3);
    } else {
      score += 0.4;
    }
  }

  bool get triggers => risingCount >= 5 && score / risingCount > 0.3;
}

void main() {
  print('=== Grid Trigger Numerical Test (Reference-Aligned) ===\n');

  // Test 1: 成片弱信号 — 15 stations, 5 rising, char1=2, char2=1
  final g1 = GridStats();
  for (int i = 0; i < 15; i++) {
    final rising = i < 5; // 5 stations rising
    g1.addStation(
      rising ? 1 : 0,           // level: rising=1(弱), others=0
      210,                       // char1=2, char2=1, char3=0
      rising ? [1, 0, -1] : [0, -1, -1],  // recent levels for rising
    );
  }
  print('成片弱信号 (15站,5上升):');
  print('  rising=${g1.risingCount} score=${g1.score.toStringAsFixed(3)} '
      'avg=${(g1.score / math.max(g1.risingCount, 1)).toStringAsFixed(3)} '
      '→ TRIGGER=${g1.triggers}');

  // Test 2: 成片 weak — 15 stations, 8 rising
  final g2 = GridStats();
  for (int i = 0; i < 15; i++) {
    final rising = i < 8;
    g2.addStation(rising ? 1 : 0, 210, rising ? [1, 0, -1] : [0, -1, -1]);
  }
  print('\n成片弱信号 (15站,8上升):');
  print('  rising=${g2.risingCount} score=${g2.score.toStringAsFixed(3)} '
      'avg=${(g2.score / math.max(g2.risingCount, 1)).toStringAsFixed(3)} '
      '→ TRIGGER=${g2.triggers}');

  // Test 3: 密集上升 (55 stations, 25 rising)
  final g3 = GridStats();
  for (int i = 0; i < 55; i++) {
    final rising = i < 25;
    g3.addStation(rising ? 3 : 0, 320, rising ? [3, 2, 1] : [0, -1, -1]);
  }
  print('\n密集上升 (55站,25上升,level=3):');
  print('  rising=${g3.risingCount} score=${g3.score.toStringAsFixed(3)} '
      'avg=${(g3.score / math.max(g3.risingCount, 1)).toStringAsFixed(3)} '
      '→ TRIGGER=${g3.triggers}');

  // Test 4: 仅4上升 (不够5)
  final g4 = GridStats();
  for (int i = 0; i < 10; i++) {
    g4.addStation(i < 4 ? 2 : 0, 210, [2, 1, 0]);
  }
  print('\n仅4上升 (10站):');
  print('  rising=${g4.risingCount} score=${g4.score.toStringAsFixed(3)} '
      'avg=${(g4.score / math.max(g4.risingCount, 1)).toStringAsFixed(3)} '
      '→ TRIGGER=${g4.triggers}');

  // Test 5: char3 过滤 — 各站不同 threshold
  print('\n=== 逐站 char3 过滤 (Branch B) ===');
  final testSignals = [
    (code: 'A', th: 210, c3: 0, rising: true),
    (code: 'B', th: 211, c3: 1, rising: true),
    (code: 'C', th: 212, c3: 2, rising: true),
    (code: 'D', th: 213, c3: 3, rising: true),
    (code: 'E', th: 214, c3: 4, rising: true),  // c3=4 → skip!
    (code: 'F', th: 215, c3: 5, rising: true),  // c3=5 → skip!
    (code: 'G', th: 210, c3: 0, rising: false), // no rise → skip!
  ];
  for (final s in testSignals) {
    final c3 = s.th % 10;
    final passes = s.rising && c3 < 4;
    print('  ${s.code}: th=$s.th c3=$c3 rising=${s.rising} → ${passes ? "TRIGGER" : "SKIP"}');
  }

  // Test 6: 极端场景 — 50站全上升
  final g6 = GridStats();
  for (int i = 0; i < 50; i++) {
    g6.addStation(3, 210, [3, 2, 1]);
  }
  print('\n极端 (50站全上升,level=3):');
  print('  rising=${g6.risingCount} score=${g6.score.toStringAsFixed(3)} '
      'avg=${(g6.score / math.max(g6.risingCount, 1)).toStringAsFixed(3)} '
      '→ TRIGGER=${g6.triggers}');
}
