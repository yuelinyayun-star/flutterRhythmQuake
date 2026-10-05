/// Display data from continuous raw-waveform analysis, not instrumental intensity.
class SeedLinkActivity {
  const SeedLinkActivity({this.ratio, this.event = false});

  final double? ratio;
  final bool event;

  Map<String, Object?> toJson() => {'ratio': ratio, 'event': event};

  static SeedLinkActivity? fromJson(Object? value) {
    if (value is! Map) return null;
    final ratio = value['ratio'];
    return SeedLinkActivity(
      ratio: ratio is num && ratio.isFinite && ratio >= 0
          ? ratio.toDouble()
          : null,
      event: value['event'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeedLinkActivity && ratio == other.ratio && event == other.event;
  @override
  int get hashCode => Object.hash(ratio, event);
}
