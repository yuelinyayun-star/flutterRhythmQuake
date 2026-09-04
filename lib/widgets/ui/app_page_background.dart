import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/page_background_provider.dart';

class AppPageBackground extends StatefulWidget {
  static const String assetPath = 'assets/images/madoka_bg.png';
  static Future<Uint8List>? _cachedBytes;

  final double opacity;
  final Alignment alignment;

  const AppPageBackground({
    super.key,
    this.opacity = 0.35,
    this.alignment = Alignment.center,
  });

  static Future<Uint8List> _loadBytes() async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  }

  static Future<Uint8List> cachedBytes() {
    return _cachedBytes ??= _loadBytes();
  }

  @override
  State<AppPageBackground> createState() => _AppPageBackgroundState();
}

class _AppPageBackgroundState extends State<AppPageBackground> {
  late final Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = AppPageBackground.cachedBytes();
  }

  @override
  Widget build(BuildContext context) {
    final pageBg = context.watch<PageBackgroundProvider>();
    final customBytes = pageBg.customBytes;
    final useCustom =
        !kIsWeb &&
        pageBg.useCustom &&
        pageBg.hasCustomImage &&
        customBytes != null;

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: const Color(0xFF020208),
          child: useCustom
              ? _buildCustomImage(customBytes, pageBg.revision)
              : FutureBuilder<Uint8List>(
                  future: _bytesFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const _FallbackBackground();
                    }
                    return Opacity(
                      opacity: widget.opacity,
                      child: Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        alignment: widget.alignment,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const _FallbackBackground(),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildCustomImage(Uint8List bytes, int revision) {
    return Opacity(
      opacity: widget.opacity,
      child: Image.memory(
        bytes,
        key: ValueKey('page-bg-custom-$revision-${bytes.length}'),
        fit: BoxFit.cover,
        alignment: widget.alignment,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const _FallbackBackground(),
      ),
    );
  }
}

class _FallbackBackground extends StatelessWidget {
  const _FallbackBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF020208), Color(0xFF101A33)],
        ),
      ),
    );
  }
}
