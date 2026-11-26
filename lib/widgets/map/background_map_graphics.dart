import 'dart:async';

/// Retains the basemap through brief visibility changes such as a system
/// transition. The caller handles disposing the layers and their images.
class BackgroundMapGraphics {
  BackgroundMapGraphics({required this.onRetentionChanged});

  static const releaseDelay = Duration(milliseconds: 500);

  final void Function(bool retained) onRetentionChanged;
  Timer? _releaseTimer;
  bool _retained = true;

  bool get retained => _retained;

  void setWindowVisible(bool visible) {
    if (visible) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
      if (_retained) return;
      _retained = true;
      onRetentionChanged(true);
    } else if (_retained && _releaseTimer == null) {
      _releaseTimer = Timer(releaseDelay, () {
        _releaseTimer = null;
        _retained = false;
        onRetentionChanged(false);
      });
    }
  }

  void dispose() {
    _releaseTimer?.cancel();
  }
}
