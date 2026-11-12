# Directory history and replay files

The IO application history store and the local collector use independent files.
The legacy formats remain read-only compatibility/migration inputs.

Windows and Linux directory file transactions run in the Rust `replay_files` owner.
Live reception submits each original immediately to a byte-bounded file writer,
leaving only file references in the history model. The settings worker handles
small manifest transactions; it no longer gates release of live frame graphs.
Raw JSON bytes and the layout
below remain unchanged. See [native history files](native_history_files_20261023.md)
for ownership, old gzip compatibility, validation and component measurements.
Other IO clients initialize the same directory layout at startup, using their
portable file owner where this Rust module is not supported. Browser storage
and portable ZIP orchestration retain their existing platform paths.

```text
replay_history/v3/
  index/<namespace hash>.json
  events/<event key hash>/
    event.json                   # summaries, receipt times, file references
    reports/<sha256>.json         # one complete report and sourcePayload
  frames/<frame key hash>.json.gz # one complete station frame per file
```

A new report/frame does not rewrite older bodies. Overlapping events share
frame references within their edition. The event manifest and namespace index
commit after the referenced files have been flushed. Failed live writes retain
the encoded item in the bounded writer for explicit retry, rather than retaining
all decoded frames in the caller. Retention removes a shared frame
only after no retained event in that namespace references it. Public and
personal frame identities are separate.

Each frame preserves the original `receivedAt`, `snapshot` and, when available,
`originalJson` values. Independent gzip level 1 compression avoids a large
increase in disk usage. There is no cross-frame node table, base64 JSON wrapper
or compression of an entire recording during capture. Each live model is
encoded once at the FFI boundary; Rust owns queued bytes, compression and disk IO.
Large single valid inputs may occupy the queue alone; normal queued bytes are
limited to 8 MiB, with the unchanged 128 MiB single-file input limit.
Readers keep the currently displayed sources, not all decoded frames.
Expanding the new-format history report rows reads their saved display summaries
and badge metadata without loading every original report body.

## Startup, migration and playback

Startup reads lightweight summaries. Existing `eew_history` files and
`shared_preferences.before_history_split.json` remain untouched. Unchanged old
events do not migrate during ordinary startup saves. An event converts when
selected for replay/export or when its reports/capture are updated. Conversion
reads one old station chunk at a time and publishes the new manifest only after
the independent files are durable. Live source startup does not wait for a
conversion of the whole old archive.

Replay preparation builds time/file descriptors. A report body loads when its
scheduled report is due; a frame loads when its frame is due. Stop invalidates
pending reads so an old read cannot deliver into a newer session. Imported
temporary directories are released when replaced or when the controller closes.
Raw source values, precision and times are not rewritten or thinned.

Manifest requests are coalesced to one running save plus a dirty flag, rather
than a growing chain of all-history saves. New receipts during a previous save
are protected from its retention pass. See
[2026-11-10 capture audit](replay_stream_capture_20261110.md) for exact scope and tests.

## Portable desktop export

New desktop `.rqreplay` files are ordinary ZIPs:

Suggested export names use the latest saved report's earthquake time (UTC+8),
hypocenter, magnitude, source and event ID, followed by an identity suffix.
The collector also uses readable event names for new capture folders and
completed packages, and still opens older hash-only capture folders.
Filename sanitization preserves Chinese/Japanese text without changing reports.
Internal application history indexes and content-addressed files retain stable
hash identities; event metadata and portable filenames identify the earthquake.

```text
manifest.json
reports/0000_<sha256>.json
reports/0001_<sha256>.json
frames/<receipt microseconds>_<source>_<sha256>.json.gz
```

The manifest carries summaries, original timing metadata, report file identities
and frame count. Every report/frame is a separate member. ZIP creation streams
existing files directly into the destination; already compressed frame members
are stored without recompression. No full-recording JSON string or whole-ZIP
byte array is built for desktop export. Import streams ZIP members to an owned
directory, validates paths, file counts, sizes and SHA-256, then retains only
file descriptors. Legacy v1/v2 JSON imports convert to the directory structure
in a short-lived worker before exposing the package to the UI.

## Verification

`test/history_directory_replay_test.dart` covers immutable append, deferred reads,
old-file preservation, failed commits/retry, ZIP layout/import and playback.
The existing history, retention, controls, timeline and collector suites remain.

Opt-in real-data tests in `test/history_directory_real_copy_test.dart` accept
only copies below the workspace `tmp` directory. The 2026-10-23 sample covered
two events, 6,163 station frames and 46 reports. Every decoded value and timestamp
matched the legacy originals. Warm preparation measured 31-66 ms compared with
5,950 ms for legacy block preparation. Independent compressed frame files used
about 89 MiB compared with 76 MiB of legacy shared chunks; plain frame JSON used
about 1.17 GiB. Per-frame file reads trade some IO overhead for much smaller
preparation work and a bounded expanded working set.

These are Flutter test process/storage measurements, not application FPS or
universal performance guarantees. First-access legacy conversion is measured
separately from warm replay preparation.
