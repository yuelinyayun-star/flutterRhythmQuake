import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/sources/fan_radar_service.dart';

/// Cache identity is the original byte buffer, as with MemoryImage. Desktop
/// consumes the already validated pixels; an Android handoff decodes locally.
class RadarFrameImage extends ImageProvider<RadarFrameImage> {
  const RadarFrameImage(this.frame);
  final FanRadarFrame frame;

  @override
  Future<RadarFrameImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    RadarFrameImage key,
    ImageDecoderCallback decode,
  ) {
    final validated = frame.validatedImage?.take();
    return OneFrameImageStreamCompleter(
      validated != null
          ? SynchronousFuture(ImageInfo(image: validated))
          : _decode(decode),
    );
  }

  Future<ImageInfo> _decode(ImageDecoderCallback decode) async {
    final codec = await decode(
      await ui.ImmutableBuffer.fromUint8List(frame.imageBytes),
    );
    try {
      return ImageInfo(image: (await codec.getNextFrame()).image);
    } finally {
      codec.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RadarFrameImage &&
      identical(frame.imageBytes, other.frame.imageBytes);
  @override
  int get hashCode => identityHashCode(frame.imageBytes);
}

class FanRadarLayer extends StatefulWidget {
  const FanRadarLayer({super.key, required this.frame});

  final FanRadarFrame? frame;

  @override
  State<FanRadarLayer> createState() => _FanRadarLayerState();
}

class _FanRadarLayerState extends State<FanRadarLayer> {
  @override
  void didUpdateWidget(covariant FanRadarLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.frame?.imageBytes;
    if (previous != null && !identical(previous, widget.frame?.imageBytes)) {
      // The displayed image owns its own handle. Evict only this retired frame
      // after the new overlay has been built; other layers keep their caches.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(previous, widget.frame?.imageBytes)) {
          PaintingBinding.instance.imageCache.evict(
            RadarFrameImage(oldWidget.frame!),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    final bytes = widget.frame?.imageBytes;
    if (bytes != null) {
      PaintingBinding.instance.imageCache.evict(RadarFrameImage(widget.frame!));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.frame;
    if (data == null) return const SizedBox.shrink();
    final bounds = LatLngBounds.fromPoints([data.southWest, data.northEast]);
    return RepaintBoundary(
      child: OverlayImageLayer(
        overlayImages: [
          OverlayImage(
            key: ValueKey('fan-radar-${data.time.toIso8601String()}'),
            bounds: bounds,
            imageProvider: RadarFrameImage(data),
            opacity: 0.60,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ],
      ),
    );
  }
}
