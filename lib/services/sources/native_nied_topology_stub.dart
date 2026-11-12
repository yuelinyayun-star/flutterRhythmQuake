class NativeNiedTopology {
  static bool get supported => false;
  static List<dynamic> build(
    List<int> ids,
    List<double> coordinates,
    List<String> codes,
  ) => throw UnsupportedError('Native NIED topology requires Windows');
}
