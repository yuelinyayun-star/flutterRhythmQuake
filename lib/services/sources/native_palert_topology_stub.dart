class NativePAlertTopology {
  static bool get supported => false;
  static List<List<int>> build(List<double> coordinates) =>
      throw UnsupportedError('Native P-Alert topology requires Windows');
}
