import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/providers/quake_provider.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/widgets/map/source_dashboard.dart';
import 'package:provider/provider.dart';

class _StatusProvider extends ChangeNotifier implements QuakeProvider {
  @override
  final sourceStatusListenable = ValueNotifier<int>(0);

  @override
  Map<String, SourceStatus> get sourceStatuses => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void dispose() {
    sourceStatusListenable.dispose();
    super.dispose();
  }
}

void main() {
  const sources = ['Wolfx', 'FAN', 'WHEWS', 'Jian Project', 'NowQuake', 'P2P'];
  const labels = ['Wolfx', 'FAN（未认证）', 'WHEWS', 'Jian', 'NowQuake', 'P2PQ'];

  for (final width in [800.0, 1600.0]) {
    for (final count in [0, 1, 4, 5, 6]) {
      testWidgets('$count APIs wrap after five at width $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final manager = SourceManager();
        final enabled = [
          for (final source in sources) manager.isSourceEnabled(source),
        ];
        addTearDown(() {
          for (var i = 0; i < sources.length; i++) {
            manager.setSourceEnabled(sources[i], enabled[i]);
          }
        });
        for (var i = 0; i < sources.length; i++) {
          manager.setSourceEnabled(sources[i], i < count);
        }
        final provider = _StatusProvider();
        await tester.pumpWidget(
          ChangeNotifierProvider<QuakeProvider>.value(
            value: provider,
            child: const MaterialApp(
              home: Scaffold(body: Stack(children: [SourceDashboard()])),
            ),
          ),
        );
        for (var i = 0; i < labels.length; i++) {
          expect(
            find.text(labels[i]),
            i < count ? findsOneWidget : findsNothing,
          );
          if (i >= count) continue;
          final rect = tester.getRect(find.text(labels[i]));
          final rowStart = tester.getRect(find.text(labels[(i ~/ 5) * 5]));
          expect(rect.top, closeTo(rowStart.top, 0.01));
          if (i >= 5) {
            expect(
              rect.top,
              greaterThan(tester.getRect(find.text(labels[0])).bottom),
            );
          }
        }
        final stationLines = find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText().contains('(UTC'),
        );
        if (count > 0 && stationLines.evaluate().isNotEmpty) {
          expect(
            tester.getRect(stationLines.first).top,
            greaterThanOrEqualTo(
              tester.getRect(find.text(labels[count - 1])).bottom - 0.01,
            ),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      });
    }
  }
}
