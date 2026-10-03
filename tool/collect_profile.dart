import 'dart:convert';
import 'dart:io';
// Flutter's pinned VM service client is used only by this diagnostic harness.
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final uri = Uri.parse(args[0]);
  final ws = uri.replace(scheme: 'ws', path: '${uri.path}ws');
  final service = await vmServiceConnectUri(ws.toString());
  try {
    final vm = await service.getVM();
    final isolate = vm.isolates!.firstWhere((i) => i.name == 'main');
    final id = isolate.id!;
    final start = await service.getVMTimelineMicros();
    await service.setVMTimelineFlags(['Dart', 'Embedder', 'GC']);
    await Future<void>.delayed(Duration(seconds: int.parse(args[2])));
    final end = await service.getVMTimelineMicros();
    final samples = await service.getCpuSamples(
      id,
      start.timestamp!,
      end.timestamp! - start.timestamp!,
    );
    final allocation = await service.getAllocationProfile(id);
    final processMemory = await service.getProcessMemoryUsage();
    final timeline = await service.getVMTimeline(
      timeOriginMicros: start.timestamp,
      timeExtentMicros: end.timestamp! - start.timestamp!,
    );
    await File(
      '${args[1]}.timeline.json',
    ).writeAsString(jsonEncode(timeline.toJson()));
    final isolateSamples = <Object?>[];
    for (final isolate in (await service.getVM()).isolates!) {
      if (isolate.id == id) continue;
      try {
        final other = await service.getCpuSamples(
          isolate.id!,
          start.timestamp!,
          end.timestamp! - start.timestamp!,
        );
        final functions = [...?other.functions]
          ..sort(
            (a, b) => (b.exclusiveTicks ?? 0).compareTo(a.exclusiveTicks ?? 0),
          );
        isolateSamples.add({
          'name': isolate.name,
          'sampleCount': other.sampleCount,
          'functions': [for (final f in functions.take(12)) f.toJson()],
        });
      } catch (error) {
        isolateSamples.add({'name': isolate.name, 'error': error.toString()});
      }
    }
    Map<String, dynamic>? runtime;
    try {
      runtime = (await service.callServiceExtension(
        'ext.rhythm.performance',
        isolateId: id,
      )).json;
    } catch (error) {
      runtime = {'diagnosticError': error.toString()};
    }
    final functions = [
      ...?samples.functions,
    ]..sort((a, b) => (b.inclusiveTicks ?? 0).compareTo(a.inclusiveTicks ?? 0));
    final classes = [...?allocation.members]
      ..sort((a, b) => (b.bytesCurrent ?? 0).compareTo(a.bytesCurrent ?? 0));
    final result = {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'sampleCount': samples.sampleCount,
      'heap': allocation.memoryUsage?.toJson(),
      'processMemory': processMemory.toJson(),
      'otherIsolates': isolateSamples,
      'hotFunctions': [for (final f in functions.take(45)) f.toJson()],
      'largestClasses': [for (final c in classes.take(25)) c.toJson()],
      'runtime': runtime,
    };
    await File(args[1]).writeAsString(jsonEncode(result));
    stdout.writeln(
      jsonEncode({
        'output': args[1],
        'sampleCount': samples.sampleCount,
        'heap': allocation.memoryUsage?.toJson(),
        'rssBytes': runtime?['rssBytes'],
        'hotFunctions': [
          for (final f in functions.take(12))
            {
              'name': f.function?.name,
              'inclusiveTicks': f.inclusiveTicks,
              'exclusiveTicks': f.exclusiveTicks,
            },
        ],
      }),
    );
  } finally {
    await service.dispose();
  }
}
