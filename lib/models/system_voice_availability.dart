enum SystemVoiceState { available, unavailable, checkFailed }

class SystemVoiceAvailability {
  const SystemVoiceAvailability(this.state, {this.diagnostic});
  final SystemVoiceState state;
  final String? diagnostic;
  bool get available => state == SystemVoiceState.available;
}
