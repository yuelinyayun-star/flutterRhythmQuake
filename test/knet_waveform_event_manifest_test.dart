import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_event_manifest.dart';

void main() {
  test('builds explicit NIED HTTPS zip targets without guessing event id', () {
    final event = KnetWaveformEventCandidate(
      eventId: 'kumamoto_20160416',
      originTimeUtc: DateTime.utc(2016, 4, 15, 16, 25, 10),
      latitude: 32.75,
      longitude: 130.76,
      depthKm: 12,
      magnitude: 7.3,
      eventLabels: const ['inland', 'shallow'],
      niedDirectoryId: '20160416012500',
      source: 'manual_seed',
      notes: null,
    );

    final plan = const KnetWaveformDownloadPlanner().buildPlan(
      [event],
      collections: const [KnetDownloadCollection.knet],
      formats: const ['ascii'],
    );

    expect(plan.schemaVersion, knetWaveformDownloadManifestVersion);
    expect(
      plan.events.single.originTimeJst,
      DateTime.utc(2016, 4, 16, 1, 25, 10),
    );
    expect(
      plan.targetsByEventId['kumamoto_20160416']!.single.url,
      'https://www.kyoshin.bosai.go.jp/kyoshin/download/'
      'knet/zip/2016/04/20160416012500/20160416012500_ascii.zip',
    );
    expect(
      plan.targetsByEventId['kumamoto_20160416']!.single.qualityFlags,
      contains('explicit_directory_id'),
    );
  });

  test('suggested directory id snaps to 00 or 30 seconds only as a helper', () {
    expect(
      suggestedKnetNiedDirectoryId(DateTime.utc(2011, 3, 11, 5, 46, 26)),
      '20110311144600',
    );
    expect(
      suggestedKnetNiedDirectoryId(DateTime.utc(2026, 6, 20, 12, 44, 42)),
      '20260620214430',
    );
  });
}
