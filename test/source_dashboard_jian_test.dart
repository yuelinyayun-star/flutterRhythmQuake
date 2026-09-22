import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutterrhythmquake/models/source_credential_info.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/widgets/map/source_dashboard.dart';

class _Provider extends ChangeNotifier implements QuakeProvider {
  String? auth = 'authenticated';
  SourceCredentialInfo? info = const SourceCredentialInfo(configured: true);
  @override
  final sourceStatusListenable = ValueNotifier<int>(0);
  @override
  final sourceStatuses = <String, SourceStatus>{
    'Jian Project': SourceStatus.connected,
  };
  @override
  String? sourceAuthenticationStatus(String source) =>
      source == 'Jian Project' ? auth : null;
  @override
  SourceCredentialInfo? sourceCredentialInfo(String source) =>
      source == 'Jian Project' ? info : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void dispose() {
    sourceStatusListenable.dispose();
    super.dispose();
  }
}

void main() {
  final now = DateTime.utc(2026, 9, 21, 12);
  test(
    'expiry labels distinguish missing metadata, estimates and server rejection',
    () {
      SourceCredentialInfo expires(Duration duration) =>
          SourceCredentialInfo(configured: true, expiresAt: now.add(duration));
      expect(jianCredentialValidityText(null, now), '到期时间未知');
      expect(
        jianCredentialValidityText(expires(const Duration(days: 10)), now),
        '长期凭证约剩 10 天',
      );
      expect(
        jianCredentialValidityText(expires(const Duration(hours: 3)), now),
        '长期凭证约剩 3 小时',
      );
      expect(
        jianCredentialValidityText(expires(const Duration(minutes: 3)), now),
        '长期凭证约剩 3 分钟',
      );
      expect(
        jianCredentialValidityText(expires(const Duration(seconds: 3)), now),
        '长期凭证不足 1 分钟',
      );
      expect(
        jianCredentialValidityText(expires(Duration.zero), now),
        '已到预计到期时间',
      );
      expect(
        jianCredentialValidityText(
          const SourceCredentialInfo(
            configured: true,
            errorCode: 'expired_refresh_token',
          ),
          now,
        ),
        '长期凭证已过期',
      );
      expect(
        SourceCredentialInfo.fromMap({
          'configured': true,
          'expiresAt': 'invalid',
        })?.expiresAt,
        isNull,
      );
      expect(SourceCredentialInfo.fromMap(null), isNull);
    },
  );

  for (final width in [320.0, 800.0, 1600.0]) {
    testWidgets(
      'Jian has its own row and preserves other source order at $width',
      (tester) async {
        if (const bool.fromEnvironment('JIAN_DASHBOARD_PREVIEW')) {
          await tester.runAsync(() async {
            final font = FontLoader('JetBrainsMono')
              ..addFont(
                File(
                  '${Platform.environment['SystemRoot']}/Fonts/msyh.ttc',
                ).readAsBytes().then(ByteData.sublistView),
              );
            await font.load();
          });
        }
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final manager = SourceManager();
        const sources = [
          'Wolfx',
          'FAN',
          'WHEWS',
          'Jian Project',
          'NowQuake',
          'P2P',
        ];
        final enabled = {
          for (final source in sources) source: manager.isSourceEnabled(source),
        };
        addTearDown(() {
          for (final entry in enabled.entries) {
            manager.setSourceEnabled(entry.key, entry.value);
          }
        });
        for (final source in sources) {
          manager.setSourceEnabled(source, true);
        }
        final provider = _Provider();
        var clock = now;
        provider.info = SourceCredentialInfo(
          configured: true,
          expiresAt: now.add(const Duration(days: 10)),
        );
        await tester.pumpWidget(
          ChangeNotifierProvider<QuakeProvider>.value(
            value: provider,
            child: MaterialApp(
              home: Scaffold(
                body: Stack(children: [SourceDashboard(now: () => clock)]),
              ),
            ),
          ),
        );
        final separate = find.byKey(
          const ValueKey('jian-credential-status-line'),
        );
        expect(separate, findsOneWidget);
        expect(find.text('Jian（已认证）'), findsOneWidget);
        expect(find.text('长期凭证约剩 10 天'), findsOneWidget);
        if (const bool.fromEnvironment('JIAN_DASHBOARD_PREVIEW')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find
                  .descendant(
                    of: find.byType(SourceDashboard),
                    matching: find.byType(RepaintBoundary),
                  )
                  .first,
            );
            final image = await boundary.toImage(pixelRatio: 3);
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/ui-previews/jian-dashboard-${width.toInt()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        final otherLabels = ['Wolfx', 'FAN（未认证）', 'WHEWS', 'NowQuake', 'P2PQ'];
        Rect? previous;
        for (final label in otherLabels) {
          final rect = tester.getRect(find.text(label));
          expect(
            rect.top,
            greaterThanOrEqualTo(tester.getRect(separate).bottom),
          );
          if (previous != null) {
            expect(
              rect.top > previous.top || rect.left > previous.left,
              isTrue,
            );
            if (width >= 800) expect(rect.top, closeTo(previous.top, 0.01));
          }
          previous = rect;
        }
        expect(tester.getRect(separate).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(separate).right, lessThanOrEqualTo(width));
        // Timer refresh changes only the displayed estimate, not connection state.
        clock = now.add(const Duration(days: 11));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('已到预计到期时间'), findsOneWidget);
        expect(provider.sourceStatuses['Jian Project'], SourceStatus.connected);
        provider.auth = 'unavailable';
        provider.sourceStatuses['Jian Project'] = SourceStatus.error;
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(separate, findsOneWidget);
        expect(find.text('Jian（连接暂不可用）'), findsOneWidget);
        provider.info = const SourceCredentialInfo(configured: true, errorCode: 'network');
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(find.text('Jian（鉴权连接失败）'), findsOneWidget);
        provider.info = const SourceCredentialInfo(configured: true, errorCode: 'conn_limit');
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(find.text('Jian（并发已满）'), findsOneWidget);
        provider.info = const SourceCredentialInfo(
          configured: true,
          errorCode: 'expired_refresh_token',
        );
        provider.auth = 'invalid';
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(find.text('长期凭证已过期'), findsOneWidget);
        provider.info = const SourceCredentialInfo(configured: true);
        provider.auth = 'authenticated';
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(find.text('到期时间未知'), findsOneWidget);
        manager.setSourceEnabled('Jian Project', false);
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(separate, findsNothing);
        manager.setSourceEnabled('Jian Project', true);
        provider.info = const SourceCredentialInfo();
        provider.auth = 'anonymous';
        provider.sourceStatusListenable.value++;
        await tester.pump();
        expect(separate, findsNothing);
        expect(find.text('Jian（未认证）'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      },
    );
  }
}
