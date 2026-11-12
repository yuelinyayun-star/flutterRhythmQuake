# Windows speech initialization guard

Project-owned copy of hosted `flutter_tts` 4.2.5. The upstream license and
the source for other platforms are retained without changes. The root pubspec
selects this copy; the shared Pub cache is not edited.

On the affected Windows 10 cloud computer, `SpeechSynthesizer.AllVoices` returns
zero and constructing `SpeechSynthesizer` throws HRESULT `0x800455A0`.
The original WinRT member construction let this exception escape plugin
registration, terminating the process outside Dart's exception handling.

Only the WinRT Windows implementation changes: construct null WinRT handles,
activate inside the existing constructor with a specific `hresult_error` catch,
retain the original error, and return `tts_initialization_failed` plus the
original HRESULT to speech channel calls. Never return successful speech or
invent voices when initialization failed. Skip closing a null media player.

Successful initialization follows the original synthesis, settings, playback
and callbacks. The Windows SAPI branch, Dart sources, other platforms and the
APP's Windows speech policy are unchanged. The fix is native platform error
handling, not a migration or rewrite of speech queue business rules.
