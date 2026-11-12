import 'package:flutter/material.dart';
import '../../models/tsunami_message.dart';
import '../../services/nmefc_coastal_map_service.dart';
import 'jma_tsunami_sidebar.dart';

/// Right sidebar only. The existing left information list is untouched.
class NmefcCoastalMapPanel extends StatefulWidget {
  const NmefcCoastalMapPanel({
    super.key,
    required this.message,
    required this.scale,
    this.service,
  });
  final TsunamiMessage message;
  final double scale;
  final NmefcCoastalMapService? service;
  @override
  State<NmefcCoastalMapPanel> createState() => _NmefcCoastalMapPanelState();
}

class _NmefcCoastalMapPanelState extends State<NmefcCoastalMapPanel> {
  late Future<NmefcCoastalMap?> _image;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _image = (widget.service ?? NmefcCoastalMapService()).load(widget.message);
  }

  @override
  void didUpdateWidget(covariant NmefcCoastalMapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.message, oldWidget.message) ||
        widget.service != oldWidget.service) {
      _load();
    }
  }

  Future<void> _enlarge(NmefcCoastalMap image) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(image.caption)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                ),
              ],
            ),
            Expanded(
              child: InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Image.memory(
                    image.bytes,
                    fit: BoxFit.contain,
                    semanticLabel: image.caption,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => FutureBuilder<NmefcCoastalMap?>(
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError &&
            snapshot.data == null) {
          // Information/cancellation reports often have no coastal chart.
          // Keep the existing full text, never replace it with a different map.
          return JmaTsunamiSidebar.nmefc(
            message: widget.message,
            scale: widget.scale,
            maxHeight: constraints.maxHeight,
          );
        }
        final image = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
        return Column(
          key: const ValueKey('nmefc_coastal_map_panel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              image?.caption ?? 'NMEFC 岸段预报图',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12 * widget.scale,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.message.reportTime.isNotEmpty)
              Text(
                widget.message.formatLocalTime(widget.message.reportTime),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 10 * widget.scale,
                ),
              ),
            SizedBox(height: 6 * widget.scale),
            Expanded(
              child: image != null
                  ? Semantics(
                      button: true,
                      label: '放大岸段预报图',
                      child: GestureDetector(
                        onTap: () => _enlarge(image),
                        child: Image.memory(
                          image.bytes,
                          key: ObjectKey(image.bytes),
                          cacheWidth:
                              (constraints.maxWidth *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .ceil()
                                  .clamp(1, 1024),
                          fit: BoxFit.contain,
                          semanticLabel: image.caption,
                          errorBuilder: (_, _, _) => const Center(
                            child: Text(
                              '岸段预报图无法显示',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: snapshot.hasError
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '岸段预报图加载失败',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                TextButton(
                                  onPressed: () => setState(_load),
                                  child: const Text('重试'),
                                ),
                              ],
                            )
                          : const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                    ),
            ),
          ],
        );
      },
    ),
  );
}
