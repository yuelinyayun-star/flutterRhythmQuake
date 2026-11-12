import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart';

import '../../core/utils/replay_event_name.dart';
import '../../services/event_render_clipboard.dart';
import '../../models/unified_quake_data.dart';
import 'history_replay_file_web.dart'
    if (dart.library.io) 'history_replay_file_io.dart'
    as output;

/// Captures the poster at its selected export size, independently of preview scaling.
Future<Uint8List> captureEventRenderPng(RenderRepaintBoundary boundary) async {
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('无法编码 PNG 图片');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<String?> saveEventRenderPng(
  RenderRepaintBoundary boundary,
  UnifiedQuakeData event,
) async {
  final bytes = await captureEventRenderPng(boundary);
  final path = await FilePicker.platform.saveFile(
    dialogTitle: '保存事件图片',
    fileName: '${replayEventName(event)}.png',
    type: FileType.custom,
    allowedExtensions: ['png'],
    bytes: kIsWeb || output.isMobile ? bytes : null,
  );
  if (path == null) return null;
  if (!kIsWeb && !output.isMobile) await output.writeBytes(path, bytes);
  return path;
}

Future<void> copyEventRenderPng(RenderRepaintBoundary boundary) async {
  await EventRenderClipboard.writePng(await captureEventRenderPng(boundary));
}
