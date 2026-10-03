# Windows History Storage

Windows preferences previously held settings, event records and all station
archives in one JSON file. Every `setValue` or `remove` rewrote that entire file.
Restoring history also decoded all station archives on the UI isolate.

## Storage and Migration

- `shared_preferences.json` now contains ordinary settings only.
- `eew_history/<sha256-of-key>.json` stores individual history values as
  `{ "key": ..., "value": ... }`. Original JSON string values are unchanged.
- Initial migration runs in a short-lived isolate, keeps the original file as
  `shared_preferences.before_history_split.json`, writes and flushes every
  record, and only then atomically replaces the settings file.
- Interrupted migration can run again from the still-complete original file.
- Ordinary settings use a small cache. Removing an absent key or saving an
  unchanged value does not write to disk.
- Do not run an older app against the migrated directory concurrently. Older
  versions do not understand the separate history directory. The backup is
  retained for recovery, not automatically restored over newer settings.

## Memory and Replay

- Startup reads event reports and station frame/archive references, not the
  station observations themselves.
- After a successful history save, saved observations are released from the
  provider, including captured frames from an event that is still active.
  Frames received while saving remain in memory until their own successful save.
- Replay/export loads just the requested archives and decodes them off the UI
  isolate. Timeline matching uses lightweight metadata first, then loads only
  overlapping events. Stop cancels a pending playback preparation.
- New observations are written as lossless JSON archive chunks. No thinning,
  rounding or omission of LPGM or other enabled station sources is performed.
- Shared chunks are deleted only after no retained event references them.
- These separate-file changes apply to the Windows worker. Other platforms keep
  their existing storage backend and replay behavior.

## Validation

Run the normal storage, history replay, timeline, retention and credentials tests.
`test/windows_history_real_copy_test.dart` is opt-in with `RQ_HISTORY_COPY` and
rejects paths outside the workspace `tmp` directory. Only use a copied data file.
It checks all migrated values by digest and the original backup byte-for-byte,
and measures settings/history-list loading without decoding station archives.
These timings are storage-path measurements, not whole-application FPS, CPU or
resident-memory guarantees. First-run migration is separate from warm startup.
