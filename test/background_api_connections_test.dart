import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/background_api.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/services/background_api_connections.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';

void main() {
  final nativeLibraryMissing = !Platform.environment.containsKey(
    'RQ_STATION_CORE_LIBRARY',
  );

  testWidgets(
    'foreground, automatic background and manual API ownership',
    (tester) async {
      const sources = {
        BackgroundApi.wolfx: ['Wolfx'],
        BackgroundApi.jian: ['Jian Project'],
        BackgroundApi.whews: ['WHEWS'],
        BackgroundApi.rhythm: ['SASMEX', 'Rhythm KMA'],
        BackgroundApi.p2p: ['P2P'],
        BackgroundApi.fssn: ['FSSN'],
      };
      final active = <String>{};
      var whewsReady = false;
      final connections = BackgroundApiConnections(
        sources: sources,
        enabledInForeground: sources.keys
            .where((api) => api != BackgroundApi.fssn)
            .toSet(),
        setSourceEnabled: (name, enabled) {
          if (enabled) {
            active.add(name);
          } else {
            active.remove(name);
          }
        },
        whewsCoverageReady: () => whewsReady,
      );
      addTearDown(connections.dispose);

      void configure({
        required bool visible,
        bool automatic = true,
        Set<BackgroundApi> manual = const {},
      }) => connections.configure(
        visible: visible,
        automatic: automatic,
        manual: manual,
        eligible: sources.keys.toSet(),
      );

      configure(visible: true);
      expect(active, {
        'Wolfx',
        'Jian Project',
        'WHEWS',
        'SASMEX',
        'Rhythm KMA',
        'P2P',
      });
      connections.onStatus(SourceStatusUpdate('Wolfx', SourceStatus.connected));
      connections.onStatus(
        SourceStatusUpdate('Jian Project', SourceStatus.error),
      );

      configure(visible: false);
      expect(active.length, lessThanOrEqualTo(2));
      expect(active, contains('Wolfx'));
      await tester.pump(const Duration(seconds: 44));
      expect(active, contains('Wolfx'));
      await tester.pump(const Duration(seconds: 1));
      expect(active, contains('Wolfx'));
      whewsReady = true;
      connections.onStatus(SourceStatusUpdate('WHEWS', SourceStatus.connected));
      await tester.pump(const Duration(minutes: 4));
      expect(active, {'Wolfx', 'WHEWS'});

      configure(
        visible: false,
        automatic: false,
        manual: {BackgroundApi.rhythm, BackgroundApi.p2p, BackgroundApi.fssn},
      );
      expect(active, {'SASMEX', 'Rhythm KMA', 'P2P'});
      configure(visible: true, automatic: false);
      expect(active, {
        'Wolfx',
        'Jian Project',
        'WHEWS',
        'SASMEX',
        'Rhythm KMA',
        'P2P',
      });
    },
    skip: nativeLibraryMissing,
  );

  testWidgets(
    'cold start applies budget and retries when every API is down',
    (tester) async {
      final active = <String>{};
      final connections = BackgroundApiConnections(
        sources: const {
          BackgroundApi.wolfx: ['Wolfx'],
          BackgroundApi.jian: ['Jian Project'],
          BackgroundApi.whews: ['WHEWS'],
          BackgroundApi.fan: ['FAN'],
        },
        enabledInForeground: const {
          BackgroundApi.wolfx,
          BackgroundApi.jian,
          BackgroundApi.whews,
          BackgroundApi.fan,
        },
        setSourceEnabled: (name, enabled) {
          if (enabled) {
            active.add(name);
            expectSync(active.length, lessThanOrEqualTo(2));
          } else {
            active.remove(name);
          }
        },
        whewsCoverageReady: () => false,
      );
      addTearDown(connections.dispose);
      connections.configure(
        visible: false,
        automatic: true,
        manual: const {},
        eligible: const {
          BackgroundApi.wolfx,
          BackgroundApi.jian,
          BackgroundApi.whews,
        },
      );
      expect(active, {'Wolfx', 'Jian Project'});
      await tester.pump(const Duration(seconds: 45));
      expect(active, {'WHEWS'});
      await tester.pump(const Duration(seconds: 45));
      expect(active, {'Wolfx'});
      await tester.pump(const Duration(minutes: 2));
      expect(active, {'Wolfx', 'Jian Project'});
      connections.dispose();
    },
    skip: nativeLibraryMissing,
  );
}
