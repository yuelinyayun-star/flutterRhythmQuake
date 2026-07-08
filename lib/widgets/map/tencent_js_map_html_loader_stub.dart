import 'dart:convert';

Future<Uri> writeTencentJsMapHtml(String html) async {
  return Uri.dataFromString(html, mimeType: 'text/html', encoding: utf8);
}
