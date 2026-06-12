import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

class AllowAnyCertTileProvider extends TileProvider {
  AllowAnyCertTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return _AllowAnyCertNetworkImage(url);
  }
}

class _AllowAnyCertNetworkImage extends ImageProvider<_AllowAnyCertNetworkImage> {
  final String url;

  _AllowAnyCertNetworkImage(this.url);

  @override
  Future<_AllowAnyCertNetworkImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_AllowAnyCertNetworkImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(_AllowAnyCertNetworkImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key),
      scale: 1.0,
    );
  }

  static Future<ui.Codec> _emptyCodec() {
    final data = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
      0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
      0x60, 0x82,
    ]);
    return ui.instantiateImageCodec(data);
  }

  Future<ui.Codec> _loadAsync(_AllowAnyCertNetworkImage key) async {
    final client = HttpClient()
      ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true)
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(key.url));
      request.headers.set('User-Agent', 'FlutterRhythmQuake/1.0');
      final response = await request.close();
      if (response.statusCode != 200) {
        return _emptyCodec();
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      return await ui.instantiateImageCodec(bytes);
    } catch (_) {
      return _emptyCodec();
    } finally {
      client.close();
    }
  }
}
