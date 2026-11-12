import '../models/unified_quake_data.dart';
import '../models/quake_message.dart';

class NativeUnifiedEventOwner {
  NativeUnifiedEventOwner({
    required void Function(Map<String, dynamic>, Map<int, UnifiedQuakeData>)
    onBatch,
    void Function(List<QuakeMessage>)? onCatalog,
    bool? manualClock,
  }) {
    throw UnsupportedError('Native unified event owner requires Windows');
  }
  static bool get supported => false;
  static Map<String, int> get diagnostics => const {};
  static List<Map<String, dynamic>> get runtimeDiagnostics => const [];
  int get retainedViewCount => 0;
  bool get usesWorker => false;
  bool retainsView(UnifiedQuakeData event) => false;
  Future<({List<QuakeMessage> rows, int notifications})> upsertBucketAsync(
    String bucket,
    List<QuakeMessage> current,
    QuakeMessage incoming, {
    required bool replayOnly,
  }) => throw UnsupportedError('Native unified events unavailable');
  Map<String, dynamic> messageFields(UnifiedQuakeData event) =>
      throw UnsupportedError('Native unified events unavailable');
  void admit(
    UnifiedQuakeData event,
    Map<String, dynamic> context, {
    bool alreadyAccepted = false,
    bool suppressEffects = false,
  }) {}
  void send(Map<String, dynamic> command) {}
  dynamic query(
    String op, {
    UnifiedQuakeData? event,
    UnifiedQuakeData? previous,
    Map<String, dynamic> parameters = const {},
  }) => null;
  String key(UnifiedQuakeData event) => '';
  Map<String, dynamic> describe(UnifiedQuakeData event) => {};
  List<UnifiedQuakeData> sortViews(List<UnifiedQuakeData> events) =>
      throw UnsupportedError('Native unified events unavailable');
  UnifiedQuakeData merge(UnifiedQuakeData previous, UnifiedQuakeData event) =>
      throw UnsupportedError('Native unified events unavailable');
  dynamic queryRaw(Map<String, dynamic> command) => null;
  void dispose() {}
  ({List<QuakeMessage> rows, int notifications}) upsertBucket(
    String bucket,
    List<QuakeMessage> current,
    QuakeMessage incoming, {
    required bool replayOnly,
  }) => throw UnsupportedError('Native unified events unavailable');
  void rebindHistory(
    List<UnifiedQuakeData> original,
    List<UnifiedQuakeData> summaries,
  ) {}
  void projectCatalog(
    Map<String, List<QuakeMessage>> buckets, {
    required Set<String> sourceFilter,
    required double magnitudeFilter,
    required Map<String, double> bucketFilters,
  }) {}
}
