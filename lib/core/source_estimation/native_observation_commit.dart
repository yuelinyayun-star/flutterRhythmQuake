/// Called synchronously in the inference isolate after a native append.
/// Implementations must not enqueue more appends from these callbacks.
abstract interface class NativeObservationCommit {
  void observationCommitted(int oldestMetadataId, int appendedMetadataId);
  void observationBatchFailed();
}
