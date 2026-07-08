import 'dart:convert';
import 'dart:io';

Future<Uri> writeTencentJsMapHtml(String html) async {
  final directory = Directory('${Directory.systemTemp.path}/rhythmquake_map');
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  final file = File('${directory.path}/tencent_js_map.html');
  await file.writeAsString(html, encoding: utf8, flush: true);
  return file.uri;
}
