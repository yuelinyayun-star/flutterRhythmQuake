import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/models/cmt_moment_tensor.dart';
import 'package:flutterrhythmquake/models/cmt_solution_metadata.dart';
import 'package:flutterrhythmquake/models/quake_message.dart';
import 'package:flutterrhythmquake/widgets/ui/cmt_sidebar_panel.dart';

void main() {
  testWidgets('shows retained raw CMT fields and the reference-only type', (
    tester,
  ) async {
    final event = QuakeMessage(
      source: QuakeSourceType.usgsCmt,
      eventId: 'us-test',
      location: '测试位置',
      magnitude: 5.6,
      latitude: 28.55,
      longitude: 104.67,
      depth: 5,
      originTime: DateTime(2026, 8, 3, 13),
      centroidDepth: 2,
      nodalPlane1: '358/45/85',
      nodalPlane2: '185/45/95',
      momentTensor: const CmtMomentTensor(
        mnn: 1,
        mee: 2,
        mdd: 3,
        mne: 4,
        mnd: 5,
        med: 6,
      ),
      cmtMetadata: const CmtSolutionMetadata(
        scalarMoment: '3.18E+17',
        doubleCoupleRatio: 0.9417,
        rawMomentTensor: {'mrr': '1.20E+17', 'mtt': '-2.20E+17'},
        momentTensorConvention: 'rtp',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 260,
          height: 430,
          child: CmtSidebarPanel(event: event, scale: (value) => value),
        ),
      ),
    );

    expect(find.text('USGS 震源机制解'), findsOneWidget);
    expect(find.textContaining('张量坐标：RTP'), findsOneWidget);
    expect(find.textContaining('Mrr：1.20E+17'), findsOneWidget);
    expect(find.text('断层类型：逆冲断层型（仅供参考）'), findsOneWidget);
  });
}
