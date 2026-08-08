class JpShindoScale {
  JpShindoScale._();

  static const List<double> scratchValues = [
    -3.0,
    -2.5,
    -2.0,
    -1.5,
    -1.17,
    -0.84,
    -0.5,
    -0.17,
    0.16,
    0.5,
    0.83,
    1.16,
    1.5,
    1.83,
    2.16,
    2.5,
    2.83,
    3.16,
    3.5,
    3.83,
    4.16,
    4.5,
    4.75,
    5.0,
    5.25,
    5.5,
    5.75,
    6.0,
    6.25,
    6.5,
  ];

  static int levelFromShindo(double shindo) {
    if (shindo.isNaN || shindo < scratchValues.first) return -1;
    if (shindo >= scratchValues.last) return scratchValues.length - 1;
    for (int i = scratchValues.length - 1; i >= 0; i--) {
      if (shindo >= scratchValues[i]) return i;
    }
    return -1;
  }

  static int kanameishiLevelFromShindo(double shindo) {
    // KA getLevelFromInstShindo parity:
    // -1: < -3.0, 0: exactly -3.0, 1: (-3.0, -2.5),
    // 2..19: [(level - 7) / 2, (level - 6) / 2), 20: >= 6.5.
    if (shindo.isNaN || shindo < -3.0) return -1;
    if (shindo == -3.0) return 0;
    if (shindo >= 6.5) return 20;
    return (shindo * 2 + 7).floor();
  }

  static double rawShindoFromKanameishiLevel(int level) {
    if (level < 0) return -3.0;
    if (level == 0) return -3.0;
    if (level >= 20) return 6.5;
    return (level + 0.5 - 7) / 2;
  }

  static double rawShindoFromLevel(int level) {
    if (level < 0) return -3.0;
    if (level >= scratchValues.length) return scratchValues.last;
    return scratchValues[level];
  }

  static double displayShindoFromLevel(int level) {
    return rawShindoFromLevel(level).clamp(0.0, 7.0).toDouble();
  }

  static int jmaIndexFromLevel(int level) {
    if (level < 0) return 0;
    return jmaIndexFromShindo(rawShindoFromLevel(level));
  }

  static int jmaNumberFromLevel(int level) {
    final index = jmaIndexFromLevel(level);
    if (index <= 4) return index;
    if (index <= 6) return 5;
    if (index <= 8) return 6;
    return 7;
  }

  static int jmaIndexFromShindo(double shindo) {
    if (shindo < 0.5) return 0;
    if (shindo < 1.5) return 1;
    if (shindo < 2.5) return 2;
    if (shindo < 3.5) return 3;
    if (shindo < 4.5) return 4;
    if (shindo < 5.0) return 5;
    if (shindo < 5.5) return 6;
    if (shindo < 6.0) return 7;
    if (shindo < 6.5) return 8;
    return 9;
  }

  static int jmaIndexFromKanameishiLevel(int level) {
    return jmaIndexFromShindo((level + 0.5 - 7) / 2);
  }

  static int jmaNumberFromKanameishiLevel(int level) {
    if (level < 0) return -1;
    if (level <= 7) return 0;
    if (level <= 9) return 1;
    if (level <= 11) return 2;
    if (level <= 13) return 3;
    if (level <= 15) return 4;
    if (level == 16) return 5;
    if (level == 17) return 5;
    if (level == 18) return 6;
    if (level == 19) return 6;
    return 7;
  }

  static int activityLevel(int level) {
    if (level < 0) return -1;
    final shindo = rawShindoFromLevel(level);
    if (shindo <= -3.0) return 0;
    if (shindo >= 6.5) return 20;
    return (shindo * 2 + 7).floor().clamp(0, 20).toInt();
  }

  static int activityRise(int currentLevel, int previousLevel) {
    if (currentLevel < 0 || previousLevel < 0) return 0;
    return activityLevel(currentLevel) - activityLevel(previousLevel);
  }
}
