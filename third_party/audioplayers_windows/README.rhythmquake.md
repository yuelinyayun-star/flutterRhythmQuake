# RhythmQuake Windows audio patch

Project-owned copy of `audioplayers_windows` 4.3.1, from the hosted package;
the upstream license is retained. No shared Pub cache files are modified.

Media Foundation emits prepared/duration/seek/complete/error events on worker
threads. `PlatformDispatcher` creates a message-only window during Flutter
plugin registration and queues every event to that platform thread. The
stream handler checks its subscription generation before delivery, so cancel,
re-listen and disposal cannot deliver old queued events to a new Dart stream.
Cancel also destroys the sink instead of leaking it. Plugin teardown disposes
players before removing channels; global reinitialization removes old channels.
The global emitError method replies once.

The root pubspec overrides only this Windows implementation. Dart playback,
the upstream Media Foundation engine and other platforms remain upstream.

`windows/tests/platform_event_test.cpp` verifies worker-to-platform delivery,
ordering, errors, cancellation, resubscription and destruction with queued
events using the actual dispatcher and event-stream handler.
