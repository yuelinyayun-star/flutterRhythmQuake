import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/utils/jma_voice_location.dart';
import 'package:flutterrhythmquake/core/utils/jma_voice_locations.g.dart';

void main() {
  test('all generated names exactly match the unmodified JMA dictionary', () {
    final expected = <String, String>{};
    for (final file in ['epi', 'pref', 'city']) {
      final original =
          jsonDecode(
                File(
                  'test/fixtures/jma_voice/$file.json',
                ).readAsStringSync(encoding: utf8),
              )
              as Map<String, dynamic>;
      expect(
        original,
        hasLength({'epi': 343, 'pref': 47, 'city': 1901}[file]!),
      );
      for (final entry in original.entries) {
        final row = entry.value as Map<String, dynamic>;
        expected[row['japanese'] as String] = row['chinese_zs'] as String;
        expect(
          jmaVoiceLocation(row['japanese'] as String),
          row['chinese_zs'],
          reason: 'JMA $file code ${entry.key}',
        );
      }
    }
    expect(jmaVoiceLocations, expected);
  });

  test(
    'katakana places have official Chinese names, not deleted syllables',
    () {
      expect(jmaVoiceLocation('カムチャツカ半島付近'), '堪察加半岛附近');
      expect(jmaVoiceLocation('オホーツク海南部'), '鄂霍次克海南部');
      expect(jmaVoiceLocation('トカラ列島近海'), '吐葛剌列岛近海');
      expect(jmaVoiceLocation('ニセコ町'), '新雪谷町');
      expect(jmaVoiceLocation('むつ市'), '陆奥市');
      expect(jmaVoiceLocation('つくば市'), '筑波市');
    },
  );

  test('exact names within a list are mapped independently', () {
    expect(jmaVoiceLocation('カムチャツカ半島付近、オホーツク海南部'), '堪察加半岛附近、鄂霍次克海南部');
    expect(jmaVoiceLocation('カムチャツカ半島付近／未知のエリア'), '堪察加半岛附近／未知のエリア');
  });

  test('unknown names and existing Chinese are not guessed or abbreviated', () {
    for (final name in ['未知のエリア', 'カムチャツカ半島付近の未知領域', '堪察加半岛附近', '']) {
      expect(jmaVoiceLocation(name), name);
    }
  });
}
