class NativeKaDetectionResult {
  const NativeKaDetectionResult({
    required this.activeIndices,
    required this.strongestIndex,
  });
  final List<int> activeIndices;
  final int? strongestIndex;
}
