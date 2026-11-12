# Station image core

## Other JSON API ingress

Windows JSON API ingress now shares a generic packed parser across 56 source/
model/core files and 86 call sites, including nested upstream JSON fields. It
does not prepare station-only numeric summaries. Original UTF-8 strings and
repeated keys stay encoded until read; UTF-16 surrogate/escape values remain
exact. Container scratch is reused by depth. Generic output's flagged header,
tag10 arrays and tag11 strings are documented in the C header.

The API adapter preserves mutable Map/List behavior through copy-on-write;
unchanged snapshots reuse independently immutable storage, while modified
paths freeze separately. No native pointer enters a snapshot. One weakly cached
parser per isolate permits GC and uses no idle timers; explicit shutdown also
releases resources. Profile GC diagnostics show zero native owners/allocations
while retained snapshots remain readable. HTTP/WS policy and domain conversion
stay in Dart, as do XML/HTML/text inputs and non-Windows implementations.

Large retained JSON workloads reduce memory and processing time; several small
inputs are slower, so this is not a claim of universal CPU improvement. Full
scope, raw comparisons, existing regression failures and Profile diagnostics:
`docs/rust_api_json_migration_20261015.md`.

## Station JSON and numeric arrays

Windows WHEWS/Jian station observation connections use JSON ABI 2 after their
initial catalogue. Rust parses immutable UTF-8 or UTF-16 into a packed immutable JSON
tree, preserving original integer/float values, UTF-16 units, unknown fields,
array order and object-key semantics. Separate numeric pools contain the exact
existing toDouble conversion and finite/min/max summaries; Dart applies existing
source thresholds without rebuilding each numeric array. String numeric inputs
retain the existing WHEWS-only Dart conversion rules. Initial catalogue parsing,
time filtering and all connection/notification policy stay in Dart.

Output is copied into independent Dart storage before the next native call.
Read-only JSON and Float64 views remain valid after connection disposal. Native
owners and reusable FFI buffers are freed on close/reconnect. Other platforms
retain Dart. Exact numeric interning retains type, bits and every original array
slot. Unique numeric arrays use contiguous nodes, repeated values use explicit
indices. Short repeated floating literals reuse exact parse results within one
frame; high-uniqueness inputs disable the dictionaries adaptively. The incoming
token limit applies before interning. UTF-8 avoids the former per-unit FFI copy;
literal surrogate inputs use UTF-16 to preserve original units.

Three alternating Profile receiver runs improve receive/snapshot/publication/
array-consumption time 36.21% versus frozen Dart. Retaining 1000 independently
decoded copies of the unchanged observation uses about 59.06% less live managed
plus external memory after GC; both return to about 4.4 MiB after release.
This offline diagnostic excludes networking, map rendering and whole-app
performance acceptance. Historical ABI 1 evidence remains in
`docs/rust_station_json_migration_20261015.md`; current measurements and lifecycle
checks: `docs/rust_station_json_deep_optimization_20261015.md`.

## GlobalQuake connection parsing

Windows GlobalQuake Java object streams use parser ABI 1. One native owner per
connection retains the original byte stream, Java handles and protocol graph.
Partial objects roll back newly added nodes/handles without copying the entire
existing handle table. Java TC_RESET compacts the old graph; disconnect, parse
failure, remote close and reconnect explicitly destroy the owner and FFI buffers.
Cancelled connection attempts cannot install a late socket. Other platforms
keep the Dart parser, including the corrected first-object/header split handling.

The binary output is a borrowed graph valid only until the next native call.
Dart reconstructs transient objects synchronously and copies block bytes; native
pointers never enter snapshots or event state. Integer values, Float64 bits,
UTF-8 decoding behavior, object references, custom blocks and packet order retain
the original contract. Event conversion, first-report filters, subscriptions and
heartbeat wire bytes stay in Dart. The unchanged capture contains no actual
hypocenter notification. Scope and measurements:
`docs/rust_global_quake_connection_migration_20261015.md`.

## SeedLink connection processing

Windows SeedLink connections use sample codec ABI 1 for INT16/INT32/STEIM1/STEIM2 payloads and signal ABI 1 for continuous three-stage filtering, time windows and display detection. Original integer samples, packet order, timestamps, partial decode behavior, D0 skip and signed 32-bit integration are preserved. Filter design stays in Dart and exports its original 15 Float64 coefficients. Each NSLC owns separate native signal state; shared synchronous FFI scratch buffers are bounded and never escape into returned sample records. Stop and reconnect explicitly destroy signal owners and free scratch storage. Native finalizers also release abandoned signal owners. Other platforms retain the Dart implementation. Measurements and raw-data validation: `docs/rust_seedlink_connection_migration_20261015.md`.

Windows x64 NIED background decoding and pixel sampling, called from the existing persistent Dart worker isolate. Flutter/Dart versions are unchanged. Android and other platforms retain their existing decoder.

Builds require Cargo and the `x86_64-pc-windows-msvc` target. The Windows Flutter CMake build compiles the locked release DLL and installs it beside the executable, together with dependency notices. No runtime download is used.

`include/rq_station_core.h` defines ABI 1. The caller owns all buffers; Rust retains no pointers and releases decoded image memory before returning. Sampling returns original unpremultiplied channel bytes and an explicit valid-coordinate bit. The existing Dart shindo conversion remains authoritative.

Input is limited to 8 MiB, decoded images to 1,048,576 pixels, and station count to 1,048,576. Errors return a status; panics cannot unwind across FFI. Caller buffers are reused and explicitly freed on reconfiguration or graceful worker shutdown, with native finalizers as a secondary lifecycle safeguard.

Rust statistics report requested allocations in this DLL, excluding allocator reservations, Dart-owned FFI buffers, engine allocations and process RSS. Dart diagnostics separately report FFI buffer capacity.

To test the native implementation, first run `cargo test --locked --manifest-path native/station_core/Cargo.toml` and `cargo build --release --locked --manifest-path native/station_core/Cargo.toml`. Set `RQ_STATION_CORE_LIBRARY` to the absolute built DLL path and run `flutter test test/native_station_image_decoder_test.dart`. Tests deliberately require opt-in; packaged Windows applications always require the bundled DLL. Original GIF/PNG fixtures are committed; additional unmodified local GIF/BMP captures are checked when present.

Migration evidence and scope: `docs/rust_station_core_migration_20261011.md`.

## Persistent trigger session

The same DLL now exports trigger ABI 1 (also declared in the header). Windows NIED source-estimation workers use one native session for the generic robust station trigger detector. A frame is marshaled as one batch; original station IDs remain in Dart and map to stable reusable native indices. Numeric history, integer histograms, streaks and trigger transitions live only in Rust. Dart retains immutable display intervals while unchanged, without duplicating the numeric history.

History preserves insertion order, duplicate times, out-of-order filtering, exact cutoff inclusion, missing frames, fractional medians and UTC/local flags of each interval endpoint. Resetting one station releases its sample storage and reuses its index; whole reset destroys the session and caller buffers. Worker close is cooperative, including a ready/spawn race, and releases native ownership before isolate exit. Session handles also have native finalizers.

The session has at most 1,048,576 indexed slots. ABI statuses are explicit; an error after earlier rows does not roll back those rows and must not be retried implicitly. `rq_station_memory_*` counts all requested Rust allocations in this DLL, including live trigger state; it is no longer expected to return zero while a trigger session is active. `rq_trigger_sessions/calls` are internal diagnostics, independent of alert report counts. Optional per-phase timings are disabled in the application.

Original-data equivalence and migration measurements: `docs/rust_station_trigger_migration_20261011.md`. Observation event histories, source calculation and Android implementation remain separate migration work.

## KA station history session

KA history ABI 1 owns Lmoni's newest-first 60-entry station level histories on Windows. A frame crosses FFI once, with original incoming levels, expiry, base time, active flag and nullable quarantine counter. The original missing-value hold, abnormal peak detection, quarantine, short missing-gap fill, ascend, trigger timestamp and activity rules remain unchanged. Source location, physical observations, timers, source subscriptions and alert policy remain in Dart.

The Dart list adapter copies history only when a consumer reads it. For frame snapshots, one lazy bulk FFI copy fills a reusable private buffer, then typed indexed copies return independently owned growable Dart lists. Native views never escape the session. Retained station objects remain readable and mutable after session disposal. Snapshots are independent, and reset preserves adapter identities. Clearing an imported history frees its native allocation. All FFI input/output and scratch buffers are reused and explicitly disposed. Android and alternate station input paths retain the existing Dart implementation.

`rq_ka_sessions/calls` measure internal processing, not earthquake report numbers. Shared memory statistics include KA, generic trigger and decoder allocations; a live KA session intentionally makes current bytes nonzero. Equivalence, backup and performance evidence: `docs/rust_ka_history_migration_20261011.md`.

## HYP travel interpolation

HYP geometry ABI 1 processes an ordered batch of original Dart geodesic distances into distance/P/S triples using the existing JMA2001 table. The standalone geometry adapter retains its caller-owned buffer API; the reference search scorer now reuses the same interpolation kernel within its scoring session. The generated table preserves all original numeric samples; interpolation order and extrapolation remain unchanged. The original Dart geodesic is retained because a Rust trigonometry prototype differed by one ULP on the original station catalogue. Independent original-frame equivalence and measurements: `docs/rust_hyp_travel_migration_20261012.md`.

## Observation windows

Windows NIED inference owns native ordered numeric observation windows. Ordinary rows are 24 bytes with exact integer microsecond deltas and original Float64 bits. Values that cannot fit use wide rows preserving all original words. Quality flags and physical-observation metadata remain in Dart. Transport snapshots own their bytes and contain no native handles; explicit old history views remain readable after reset or disposal. Evidence and measurement limits: `docs/rust_observation_history_migration_20261012.md`.

## Reference HYP scoring sessions

HYP scoring ABI 1 loads one ordered search's original station fields, neighbour counts, observation times and inherited P/S choices. Weights, origin arrays, anchor selection, middle-out insertion order, inherited filtering and six scenario work vectors live in Rust and are reused for each candidate. Dart retains its exact geodesic operations and event/publication lifecycle. NIED and P-Alert reference searches share this kernel; other platforms retain the Dart scorer.

Each call returns a fixed numeric block and independently owned selected P/S flags. No borrowed pointer or native handle enters an isolate message. Explicit disposal in finally and a native finalizer release the search session; global allocator statistics count its allocations. `rq_hyp_score_calls/sessions` are diagnostics, unrelated to earthquake reports. Frozen-reference Float64 comparisons and original-frame performance results: `docs/rust_hyp_score_migration_20261012.md`. This does not complete migration of full search/event state.

## KA spatial detector

KA detector ABI 2 owns adjacency, reusable traversal state and ordered pair distances. Dart computes every distance once from the unchanged station coordinates during configuration and passes the original Float64 values to Rust. Per-frame detection no longer calls back across FFI into Dart. Thresholds, traversal order, abnormal-pair caching, strongest-station tie behavior and sorted output remain unchanged. The 51-frame untouched GIF regression compares all active indices and strongest indices against the frozen Dart implementation.

## Reference HYP four-stage search

Search ABI 1 reuses the scoring session for ordered candidate traversal, strict tie selection, moves and stage termination. Only the final score/phase buffers and recorded moves/terminal candidates are exported. The exact Dart distance function is called synchronously on the owning isolate thread with a scoped `NativeCallable`; no callback is retained, called from another thread or allowed to reenter the session. A failed callback returns status 6 and propagates its original Dart exception.

An eight-entry FIFO inside each search reuses distances only for identical latitude/longitude Float64 bits. It keeps signed zeros distinct, never rounds coordinates, reuses evicted buffers, and is destroyed at search end. Search and distance reuse counters are internal diagnostics. Original-frame equivalence, modest measured benefit and remaining acceptance limits are documented in `docs/rust_hyp_search_migration_20261012.md`; no full APP memory reduction is claimed.

## Batched observation appends

Observation batch ABI 1 submits ordered raw seven-word rows plus cutoff to the existing window kernel. Duplicate handles are legal and processed sequentially. A failed row stops the batch; later results have status 6 and are not retried. No pointers or callbacks are retained by Rust. Dart applies metadata acknowledgements only after FFI returns.

The inference isolate uses at most 2,048 rows per caller-owned batch, reuses one typed view per buffer, and releases all batch buffers at scope exit. History reads, clear and dispose flush pending appends; exception exits preserve the accepted prefix. Original timestamps, raw value bits, metadata, latest behavior and independently owned history snapshots remain unchanged. Logical observation counts and batch call counts are diagnostic only. Evidence, the rejected per-row-view prototype and remaining acceptance limits: `docs/rust_observation_batch_migration_20261013.md`.
