#ifndef RQ_STATION_CORE_H
#define RQ_STATION_CORE_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
/* NIED-only immutable sampled RGBA (valid bit 32, alpha/r/g/b below it).
   Output count*3 doubles: position/NaN, shindo/NaN, quality
   0 valid, 1 transparent missing, 2 undecodable, 3 outside image.
   physical=1 returns physical color position semantics. Buffers are borrowed.
   Status 0 OK, 1 null, 3 invalid limits/mode, 5 panic. */
#ifdef __cplusplus
extern "C" {
#endif
/* Copies a borrowed PNG to the Windows image clipboard (PNG + CF_DIBV5).
   0 success; positive Win32 error; -1 invalid PNG; -2 unsupported; -3 panic.
   No input buffer is retained. Windows owns successfully transferred data. */
int32_t rq_event_render_copy_png(const uint8_t* bytes, size_t length);
/* Union of global/mobile weather source requests, limited to the seven
   documented source bits. Scalar-only ABI; no allocation or retained input. */
uint32_t rq_weather_map_required_sources(uint32_t general, uint32_t mobile);
uint8_t* rq_weather_playback_catalog(uint32_t kind, const uint8_t* input, size_t len, size_t* output_len);
void rq_weather_playback_free(uint8_t* output, size_t len);
uint32_t rq_nsmc_tile_bounds(int32_t z, int32_t x, int32_t y, double* output);
uint8_t* rq_nsmc_project(const uint8_t* input, size_t len, int32_t z, int32_t y, size_t* output_len);
void rq_nsmc_project_free(uint8_t* output, size_t len);
int32_t rq_nied_gif_sample_rgba(const uint64_t* pixels, size_t count,
    uint8_t physical, double* output);
uint64_t rq_nied_gif_sample_calls(void);
/* P-Alert levels ABI 1. configure remaps old station indexes (-1 = new).
   process reads count rows [PGA present 0/1, original PGA, original PGV/NaN],
   outputs count [current,held] int32 pairs. Time and inclusive hold cutoff use
   source microseconds, never wall clock. Missing PGA does not update history.
   configure and process borrow immutable input only during synchronous calls.
   No callbacks, owner is non-reentrant. Limit 1M stations.
   Status 0 OK, 1 null, 2 layout, 3 limit, 5 panic. Destroy exactly once. */
uint32_t rq_palert_levels_abi_version(void);
uint64_t rq_palert_levels_sessions(void);
uint64_t rq_palert_levels_calls(void);
void* rq_palert_levels_create(void);
int32_t rq_palert_levels_configure(void* owner, const int32_t* remap, size_t count);
int32_t rq_palert_levels_process(void* owner, int64_t time_micros,
    const double* input, size_t count, int32_t* output);
void rq_palert_levels_destroy(void* owner);

/* P-Alert fields ABI 1. Uses an existing station JSON owner (no second parse).
   configure: LE uint32 count, then [uint32 UTF16 length, LE UTF16 units] IDs.
   extract: borrowed count*4 doubles [PGA present,PGA,PGV present,PGV] and the
   count of numeric PGA entries (including unknown directory IDs). JSON duplicate
   keys use the final value. Original JSON storage is never modified. Copy rows
   before any next decode/extract/configure/destroy on the owner. No callbacks.
   Limits: 1M IDs and 64 MiB layout. Status 0 OK,1 null,2 layout,3 limit,5 panic. */
uint32_t rq_palert_values_abi_version(void);
uint64_t rq_palert_values_calls(void);
int32_t rq_palert_values_configure(void* owner, const uint8_t* input, size_t length);
int32_t rq_palert_values_extract(void* owner, const double** output, size_t* valid_pga);

/* Station JSON ABI 2. Immutable UTF-16 or UTF-8; one owner per connection.
   Output is a borrowed LE tree: four uint32 counts (nodes, children, strings,
   numbers), 16-byte nodes (tag32, aux32, bits64), uint32 children, uint16 strings,
   padding to 8 bytes, float64 numbers. Numeric array tag8 uses aux=child offset,
   tag9 uses aux=first contiguous node. Identical (type,bits) leaves can share
   indices without omitting any array items. Incoming tokens remain bounded.
   bits=length32|number-index32. Numeric pool: min,max,finite flag, converted rows.
   Original leaf tags/bits remain separate and unchanged. Copy output before
   next call/destroy. Limits 64 MiB input/output, 2M incoming value tokens,
   depth 512 (interning does not reduce the token count).
   Status 0 OK, 1 null, 2 malformed, 3 limit, 5 panic. No callback or retry. */
uint32_t rq_station_json_abi_version(void);
uint64_t rq_station_json_sessions(void);
uint64_t rq_station_json_calls(void);
void* rq_station_json_create(void);
int32_t rq_station_json_decode(void* owner, const uint16_t* input, size_t length,
    const uint8_t** output, size_t* output_length);
int32_t rq_station_json_decode_utf8(void* owner, const uint8_t* input, size_t length,
    const uint8_t** output, size_t* output_length);
void rq_station_json_destroy(void* owner);

/* API ingress ABI 1, uses station JSON owner and packed snapshot ownership.
   mode low byte: 0 JSON, 1..6 JsonWireEnvelope; bit 0x100: allowMalformed UTF8.
   SSE is the existing per-data-line contract (not multiline aggregation).
   feed immutable original chunks; finish=1 flushes EOF. Drain next before feed.
   next status 100 means no complete data line; malformed JSON lines are skipped,
   malformed UTF8 is status 2. Decoder destruction releases stream buffers. */
uint32_t rq_api_ingress_abi_version(void);
int32_t rq_api_ingress_utf8(void* owner, const uint8_t* input, size_t length,
    uint32_t mode, const uint8_t* name, size_t name_length,
    const uint8_t** output, size_t* output_length);
int32_t rq_api_sse_feed(void* owner, const uint8_t* input, size_t length, uint32_t finish);
int32_t rq_api_sse_next(void* owner, const uint8_t** output, size_t* output_length);

/* Generic API JSON uses the same owner, limits and ownership. Node count's
   high bit selects a 24-byte header: original four counts, then UTF-8 pool
   byte count and reserved zero. UTF-8 bytes follow UTF-16 units before padding.
   Numeric arrays use tag10 (aux=first contiguous original node, bits=length),
   without station summaries or normalized pools. String tag11 uses aux=byte
   offset/bits=byte length in the UTF-8 pool; escaped/literal-surrogate strings
   retain original UTF-16 via tag5. Identical key bytes may share nodes but each
   original key/value slot stays ordered. No numeric value/type/order changes. */
int32_t rq_api_json_decode(void* owner, const uint16_t* input, size_t length,
    const uint8_t** output, size_t* output_length);
int32_t rq_api_json_decode_utf8(void* owner, const uint8_t* input, size_t length,
    const uint8_t** output, size_t* output_length);

/* GlobalQuake Java stream ABI 1. One owner per connection; original TCP bytes
   are immutable. Stateful handles survive add calls and clear at TC_RESET.
   Limits: 64 MiB input/output, 1M graph nodes, depth 256. Output is a borrowed
   little-endian graph buffer, valid until next add/destroy; decode/copy it
   synchronously before returning. No callback; never share owners concurrently.
   Status 0 OK (including partial input), 1 null, 2 malformed, 3 limit, 5 panic.
   Destroy after errors, disconnect or reconnect, exactly once. */
uint32_t rq_gq_stream_abi_version(void);
uint64_t rq_gq_stream_sessions(void);
uint64_t rq_gq_stream_calls(void);
void* rq_gq_stream_create(void);
int32_t rq_gq_stream_add(void* owner, const uint8_t* input, size_t length,
    const uint8_t** output, size_t* output_length);
void rq_gq_stream_destroy(void* owner);

/* ABI 1. All buffers are caller-owned and valid for the complete call.
 * No pointers are retained. The decoder and its pixel storage are freed before
 * returning. xy contains count pairs. result contains count uint64_t values:
 * bit 32 = coordinate is valid, bits 0..31 = 0xAARRGGBB (unpremultiplied).
 * dimensions receives width,height. Samples outside the image are zero.
 * Status: 0 success, 1 invalid input, 2 decode error, 3 resource limit,
 *         4 unsupported format/depth, 5 caught panic.
 */
uint32_t rq_station_core_abi_version(void);
int32_t rq_station_decode_sample(const uint8_t* bytes, size_t length,
    const int64_t* xy, size_t count, uint64_t* result, uint32_t* dimensions);
uint64_t rq_station_memory_current(void);
uint64_t rq_station_memory_peak(void);
uint64_t rq_station_decode_calls(void);

/* Trigger ABI 1. Struct sizes on supported Windows x64: config 72, input 40,
 * output 64. Int64 times are original epoch microseconds. Station IDs are
 * caller-assigned stable indices below 1,048,576; input order (including duplicates) is kept.
 * No arrays are retained. A session is exclusively used on one worker isolate.
 * Destroy exactly once; reset_station drops only that station's state.
 * Process status: 0 success, 1 invalid pointer, 2 invalid numeric/time input,
 * 3 batch limit, 5 caught panic. On error, earlier rows may already be updated,
 * matching serial update semantics; do not retry the whole batch implicitly.
 */
typedef struct rq_trigger_session rq_trigger_session;
typedef struct {
  int64_t history_us, minimum_samples;
  double rising_delta, triggered_delta;
  int64_t rising_frames, triggered_frames, decay_frames, missing_frames, strong_level;
} rq_trigger_config;
typedef struct {
  uint64_t station;
  int64_t time;
  double signal;
  int64_t detect_level;
  uint64_t flags; /* bits: signal present, usable, detect present, time is UTC */
} rq_trigger_input;
typedef struct {
  uint32_t state, reason;
  int64_t ascend;
  double activity;
  int64_t rise_start, rise_end, trigger_start, trigger_end;
  uint64_t flags; /* rise/trigger present, rise start/end UTC, trigger start/end UTC */
} rq_trigger_output;
uint32_t rq_trigger_abi_version(void);
rq_trigger_session* rq_trigger_create(const rq_trigger_config* config);
void rq_trigger_destroy(rq_trigger_session* session);
int32_t rq_trigger_reset_station(rq_trigger_session* session, uint64_t station);
int32_t rq_trigger_process(rq_trigger_session* session, const rq_trigger_input* input,
    size_t count, rq_trigger_output* output);
uint64_t rq_trigger_sessions(void);
uint64_t rq_trigger_calls(void);

/* KA history ABI 1, Windows x64: input/output are each 48 bytes.
 * One exclusive session owns newest-first integer histories. No caller pointers
 * are retained; input/output arrays must be aligned and nonoverlapping.
 * Station indices are stable and below count passed to create (<= 1,048,576).
 * Time is the original epoch milliseconds. Null abnormal counters are encoded
 * separately from their signed value, including negative original values.
 * Process validates every station index before updating; duplicate indices are
 * processed in input order. Status: 0 success, 1 invalid pointer, 3 bounds/limit,
 * 5 caught panic. Do not implicitly retry after an error.
 * copy_history copies all original entries; capacity must be sufficient.
 * replace_history accepts original integers/order, including histories > 60;
 * the next process applies the original 60-entry update rule. Empty replacement
 * releases the station allocation. Destroy exactly once (null accepted).
 */
typedef struct rq_ka_session rq_ka_session;
typedef struct {
  uint64_t station;
  int64_t level, expire_seconds, time_ms;
  uint64_t flags; /* bit 0: active; bit 1: abnormal counter present */
  int64_t abnormal;
} rq_ka_input;
typedef struct {
  int64_t level, ascend, trigger_ms;
  double activity;
  int64_t abnormal;
  uint64_t length_flags; /* bits 0..31: length; bit 32: abnormal present */
} rq_ka_output;
uint32_t rq_ka_abi_version(void);
rq_ka_session* rq_ka_create(size_t count);
void rq_ka_destroy(rq_ka_session* session);
int32_t rq_ka_process(rq_ka_session* session, const rq_ka_input* input,
    size_t count, rq_ka_output* output);
int32_t rq_ka_copy_history(const rq_ka_session* session, size_t station,
    int64_t* output, size_t capacity);
/* Copies count*60 integers, original entries followed by zero padding in each
 * slot. count must equal the session size. Histories > 60 are rejected before
 * writing. Consumers use the original lengths, never the padding as data. */
int32_t rq_ka_copy_histories(const rq_ka_session* session, int64_t* output,
    size_t count);
int32_t rq_ka_replace_history(rq_ka_session* session, size_t station,
    const int64_t* input, size_t length);
uint64_t rq_ka_sessions(void);
uint64_t rq_ka_calls(void);
/* HYP geometry ABI 1. Existing Dart geodesic distances, followed by output
 * triples (surface distance km, P travel seconds, S travel seconds) in the
 * same station order. Uses unchanged Kanameishi JMA2001 samples and arithmetic
 * order. Caller owns aligned non-overlapping arrays; no pointers are retained.
 * count <= 1,048,576. Status 0 success, 1 invalid pointer, 3 limit, 5 panic.
 * No allocations or persistent state are owned by this kernel.
 */
uint32_t rq_hyp_geometry_abi_version(void);
uint64_t rq_hyp_geometry_calls(void);
int32_t rq_hyp_geometry(const double* distances, size_t count,
    double depth_km, double* output);
/* Observation ABI 1. Raw words: data/received microseconds, value bits,
   raw/detect levels, presence/UTC/trigger bits, opaque metadata ID.
   Push output: row count, oldest metadata ID (-1 when empty), capacity bytes.
   Caller retains and owns metadata; no row or output pointer is retained. */
// Batch ABI 1: rows[count*8] = original 7 words + cutoff (i64 bits).
// output[count*4] = status, length, oldest metadata ID, capacity bytes.
// Ordered duplicate handles allowed; first failure stops later rows (status 6).
uint32_t rq_observation_batch_abi_version(void);
uint64_t rq_observation_batch_calls(void);
int32_t rq_observation_push_batch(void* const* handles, const uint64_t* rows,
                                  size_t count, int64_t* output);
uint32_t rq_observation_abi_version(void);
uint64_t rq_observation_sessions(void);
uint64_t rq_observation_calls(void);
void* rq_observation_create(void);
void rq_observation_destroy(void* handle);
int32_t rq_observation_push(void* handle, const uint64_t* row,
    int64_t cutoff_us, int64_t* output);
int32_t rq_observation_copy(const void* handle, uint64_t* output, size_t capacity);
int32_t rq_observation_clear(void* handle);
/* Packed ABI 1: 24 bytes/row: value bits, i32 data/receive deltas from base,
   u32 metadata ID, i8 raw/detect, u8 flags, u8 wide marker. Wide rows preserve
   original seven u64 words in 64-byte ID + raw row records after compact rows.
   Header is count, base microseconds, wide count. All bytes little endian. */
size_t rq_observation_packed_size(const void* handle);
int32_t rq_observation_copy_packed(const void* handle, uint8_t* output,
    size_t capacity, int64_t* header);

/* Reference HYP scoring ABI 1. One session per ordered search. info[count*8]:
   neighbour count, ascend, level (-1 when absent), has-PAlert, PAlert maximum,
   second maximum (-1 absent), prior P/S choices (-1 missing, 0 P, 1 S).
   observed[count] retains original milliseconds/1000 in original station order.
   Inputs are copied at creation. evaluate uses caller's exact Dart geodesic
   distances[count+inactive_count]; no input/output pointer is retained.
   output[99]: best scenario, best P-side, best S-side (-1 absent), then six
   16-double scenario records: valid, origin, score, RMSE, weight sum, residual
   squares, inactive penalty, inactive weight, wave multiplier, effective count,
   quality, P/S/L/O counts, filter level. Order PP, PS, P_PREV, SP, SS, S_PREV.
   waves[2*count] is independently copied best P/S-side flags (-1,0,1).
   Status 0 success, 1 null pointer, 5 panic. Handles never cross isolates. */
uint32_t rq_hyp_score_abi_version(void);
uint64_t rq_hyp_score_sessions(void);
uint64_t rq_hyp_score_calls(void);
void* rq_hyp_score_create(const int64_t* info, const double* observed,
    size_t count, size_t inactive_count);
int32_t rq_hyp_score_evaluate(void* handle, const double* distances,
    double depth, double* output, int8_t* waves);
void rq_hyp_score_destroy(void* handle);

/* Reference four-stage search ABI 1, same scoring session. start[3] is original
   latitude/longitude/depth; summary[4] is final point and logical score calls.
   callback writes count+inactive_count exact geodesic distances synchronously
   on this calling thread; it must not reenter/mutate/destroy the session.
   Neither callback nor its buffers are retained. Nonzero callback -> status 6.
   output[99] and waves[2*count] follow scoring ABI (-2: domain-invalid start).
   Log rows contain 32 doubles; copy length is in doubles. Rows are moves (1),
   stage summary (0), then terminal candidates (2), keeping original order.
   Logs are owned until next search/destroy. Status 3: insufficient capacity.
   Search preserves four steps, six neighbor order, strict ties, +1e-9 move
   threshold and global 1000-iteration limit. Longitude remains unbounded. */
typedef int32_t (*rq_hyp_distance_callback)(double latitude, double longitude,
    double* output, size_t count);
uint32_t rq_hyp_search_abi_version(void);
uint64_t rq_hyp_search_calls(void);
uint64_t rq_hyp_search_distance_calls(void);
uint64_t rq_hyp_search_distance_hits(void);
int32_t rq_hyp_score_search(void* handle, const double* start,
    rq_hyp_distance_callback callback, double* summary, double* output,
    int8_t* waves);
/* Owned geometry: station coordinates are copied once into this scorer.
   count is active + inactive, coordinates has count * 2 original doubles.
   Search/evaluate perform all geometry and scoring without a Dart callback. */
int32_t rq_hyp_score_geometry_set(void* handle, const double* coordinates, size_t count);
void* rq_ka_detector_create_nied(const double* coordinates, size_t count);
void* rq_nied_topology_build(const int64_t* ids, const double* coordinates,
    size_t count, const uint8_t* codes_utf8, size_t codes_length);
const uint8_t* rq_nied_topology_bytes(const void* handle, size_t* length);
void rq_nied_topology_free(void* handle);
int32_t rq_hyp_score_search_owned(void* handle, const double* start,
    double* summary, double* output, int8_t* waves);
int32_t rq_hyp_score_search_owned_options(void* handle, const double* start,
    uint32_t final_joint, size_t final_joint_min_count,
    double final_joint_max_score, double* summary, double* output,
    int8_t* waves);
int32_t rq_hyp_score_evaluate_owned(void* handle, double latitude,
    double longitude, double depth, double* output, int8_t* waves);
size_t rq_hyp_search_log_words(const void* handle);
int32_t rq_hyp_search_log_copy(const void* handle, double* output, size_t capacity);

/* Topology sort ABI 1. Distances are original Dart doubles, IDs unique.
   Caller owns count doubles, count int64 IDs and count uint32 output entries,
   aligned and non-overlapping. Returns indices with distance <= 300, ordered
   by distance then ID; return is number written or negative status (1/3/5).
   No pointer is retained and no geometry is recalculated. */
uint32_t rq_topology_sort_abi_version(void);
uint64_t rq_topology_sort_calls(void);
int64_t rq_topology_sort(const double* distances, const int64_t* ids,
    size_t count, uint32_t* output);

/* KA spatial detector ABI 2. CSR offsets[count+1], neighbors[edges], max 6
   neighbors per station, retain their original order. Constructor copies CSR.
   Constructor also copies ordered station-pair indices and caller-computed Dart
   distances. Pair distances keep their original Float64 bits and are reused by
   every frame, so process never calls back into Dart.
   rows[count*6] are original int64 level, double activity bits, int64 ascend,
   int64 active (0/1), double shindo bits, int64 trigger milliseconds.
   output[count] and summary[2] are caller-owned, disjoint and aligned;
   summary is active length and strongest index (-1 for none). Returned active
   indices are sorted; strongest ties use original chain insertion order.
   Return: 0 success, 1 null pointer, 2 invalid boolean, 4 missing configured
   ordered pair distance, 5 panic. */
uint32_t rq_ka_detector_abi_version(void);
uint64_t rq_ka_detector_sessions(void);
uint64_t rq_ka_detector_calls(void);
void* rq_ka_detector_create(const uint32_t* offsets, const uint32_t* neighbors,
    size_t count, size_t edges, const uint32_t* pair_first,
    const uint32_t* pair_second, const double* pair_distances,
    size_t pair_count);
int32_t rq_ka_detector_process(void* handle, const int64_t* rows,
    int64_t sensitivity, uint8_t held, uint32_t* output, int64_t* summary);
void rq_ka_detector_destroy(void* handle);

/* Station archive ABI 1. Input: LE uint32 frame count, followed by JSON values.
   Tags: 0 null, 1/2 bool, 3 int64, 4 original finite float64 bits,
   5 uint32 UTF-16 length + LE units, 6 uint32 list length + values,
   7 uint32 map length + string-key/value pairs, 8 uint32 prior string ordinal,
   9 uint32 prior completed container ordinal (postorder list/map dictionary).
   Limits: 128 MiB input/output, 2M distinct nodes, depth 512, 100K frames.
   Create borrows input for the synchronous call; returns an owned archive.
   status: 0 OK, 1 null, 2 malformed/nonfinite, 3 limit, 4 compression, 5 panic.
   Create_gzip returns the same table compressed with gzip level 3.
   Length/copy borrow a live owner; copy requires disjoint output of exact size.
   Destroy exactly once, after copy. No pointer leaves the calling worker. */
uint32_t rq_station_archive_abi_version(void);
uint64_t rq_station_archive_calls(void);
uint64_t rq_station_archive_sessions(void);
void* rq_station_archive_create(const uint8_t* input, size_t length, int32_t* status);
void* rq_station_archive_create_gzip(const uint8_t* input, size_t length, int32_t* status);
size_t rq_station_archive_length(const void* handle);
int32_t rq_station_archive_copy(const void* handle, uint8_t* output, size_t length);
void rq_station_archive_destroy(void* handle);

/* Projected map coordinates ABI 1. Create copies count XY float64 pairs
   (maximum 2M vertices). Transform receives nine original float64 parameters:
   a,b,c,d,zoomScale,addedWorldWidth,negativeOriginX/Y,worldShift. It returns a
   borrowed output pointer valid until next transform or destroy. Same scalar
   IEEE operation order as flutter_map, without FMA, rounding or point removal.
   Caller must not reenter/share an owner concurrently. Destroy exactly once. */
uint32_t rq_map_coordinates_abi_version(void);
uint8_t* rq_camera_focus_prepare(const uint8_t* input, size_t len, size_t* output_len);
/* Borrow count unmodified latitude/longitude float64 pairs. The JSON result
   contains valid original indices and the minimal wrapped range view.
   Geometry accepts finite continuous longitude; event validation is separate.
   Maximum 2M pairs. Release the result with rq_camera_focus_free. */
uint8_t* rq_camera_geometry_prepare(const double* input, size_t count, size_t* output_len);
void rq_camera_focus_free(uint8_t* output, size_t len);
uint64_t rq_camera_focus_calls(void);
uint64_t rq_camera_focus_outputs(void);
uint64_t rq_map_coordinates_calls(void);
uint64_t rq_map_coordinates_sessions(void);
void* rq_map_coordinates_create(const double* input, size_t count);
const double* rq_map_coordinates_transform(void* handle, const double* params);
void rq_map_coordinates_destroy(void* handle);

/* SeedLink signal ABI 1. One independent owner per NSLC. accept receives up to
   65535 original signed int64 samples, rate, start microseconds and 15 original
   Dart biquad coefficients in a1,a2,b0,b1,b2 order for each of 3 stages.
   Output[2]: ratio (NaN if unknown), event (0/1). Input is never modified.
   No borrowed pointer or callback is retained. All calls on an owner are
   synchronous and non-reentrant. Return 0 OK, 1 null, 3 limit, 5 panic. */
uint32_t rq_seedlink_signal_abi_version(void);
uint64_t rq_seedlink_signal_sessions(void);
uint64_t rq_seedlink_signal_calls(void);
void* rq_seedlink_signal_create(void);
int32_t rq_seedlink_signal_accept(void* owner, const int64_t* samples,
    size_t count, double rate, int64_t start_micros,
    const double* coefficients, double* output);
void rq_seedlink_signal_destroy(void* owner);

/* SeedLink codec ABI 1. Decode INT16/INT32/STEIM1/STEIM2 sample payloads.
   Input is at most 1 MiB, count at most 65535. Output owns capacity int32s.
   written reports the original partial/full decoded length. big is 0/1.
   No pointer retained, input immutable. Status 0 OK, 1 null, 2 invalid, 3 limit,
   5 panic. Unsupported encodings yield an empty result, matching Dart. */
uint32_t rq_seedlink_codec_abi_version(void);
uint64_t rq_seedlink_codec_calls(void);
int32_t rq_seedlink_decode(const uint8_t* input, size_t length,
    uint32_t encoding, uint8_t big, size_t count, int32_t* output,
    size_t capacity, size_t* written);

/* JSON wrapper ABI 1, using an existing station JSON owner in API mode.
   kinds: 1 JSONP with whitespace before (, 2 var assignment, 3 SSE data line,
   4 JSONP requiring callback immediately followed by (. No JS execution.
   Inputs/selectors immutable and borrowed only for this synchronous call.
   UTF8 consumes one transport BOM; UTF16 retains original code units.
   Output has the existing packed JSON contract and ownership/lifetime.
   Status 0 OK, 1 arguments/kind, 2 malformed, 3 JSON limit, 5 panic. */
uint32_t rq_json_envelope_abi_version(void);
int32_t rq_api_json_wrapped_utf8(void* owner, const uint8_t* input, size_t length,
    uint32_t kind, const uint8_t* name, size_t name_length,
    const uint8_t** output, size_t* size);
int32_t rq_api_json_wrapped_utf16(void* owner, const uint16_t* input, size_t length,
    uint32_t kind, const uint16_t* name, size_t name_length,
    const uint8_t** output, size_t* size);

/* Windows WS ABI 1. NativeApi.postCObject is retained until release; its port
   may be closed before release. UTF-8 host/path/headers are NUL-terminated and
   copied by open. flags: 1 TLS, 2 existing source's insecure certificate policy.
   No implicit proxy route. take returns a borrowed pointer valid until the
   next take/release on this ID; copy before returning to the event loop.
   kinds: 1 ready, 2 text UTF-8, 3 binary, 4 error, 5 close status, 6 finished.
   Max message and input/output queues: 64 MiB. IDs never reused. */
uint32_t rq_ws_abi_version(void);
uint64_t rq_ws_open(const uint8_t* host, const uint8_t* path,
    const uint8_t* headers, uint32_t port, uint32_t flags, uint32_t timeout_ms,
    uint32_t keepalive_ms, int64_t dart_port,
    bool (*post_c_object)(int64_t, void*));
uint32_t rq_ws_send(uint64_t id, const uint8_t* input, size_t length, uint32_t text);
const uint8_t* rq_ws_take(uint64_t id, size_t* length, uint32_t* kind, uint32_t* code);
void rq_ws_close(uint64_t id, uint32_t code, const uint8_t* reason, size_t length);
void rq_ws_release(uint64_t id);
void rq_ws_release_finalizer(void* id);
size_t rq_ws_workers(void);

/* Windows TCP ABI 1. One shared IOCP reactor. IP is already OS-resolved;
   authority is empty for direct, otherwise the HTTP CONNECT target host:port.
   UTF-8 strings and send bytes are copied before return. take is borrowed until
   next take/release: 1 ready, 2 bytes, 3 written(serial), 4 error, 5 finished.
   Explicit pause/resume controls reading; release closes both directions.
   Serial > 0; an empty send is an ordered flush barrier. Queue limit 64 MiB. */
uint32_t rq_tcp_abi_version(void);
uint64_t rq_tcp_open(const uint8_t* ip, uint32_t port, const uint8_t* authority,
    uint32_t timeout_ms, int64_t dart_port, bool (*post_c_object)(int64_t, void*));
uint32_t rq_tcp_send(uint64_t id, const uint8_t* input, size_t length, uint64_t serial);
const uint8_t* rq_tcp_take(uint64_t id, size_t* length, uint32_t* kind,
    uint32_t* code, uint64_t* serial);
/* Owned alternative: a non-null owner must be released exactly once, either
   explicitly or by external typed-data finalizer. Data survives socket release. */
const uint8_t* rq_tcp_take_owned(uint64_t id, size_t* length, uint32_t* kind,
    uint32_t* code, uint64_t* serial, void** owner);
void rq_tcp_chunk_release(void* owner);
void rq_tcp_pause(uint64_t id, uint32_t paused);
void rq_tcp_release(uint64_t id);
void rq_tcp_release_finalizer(void* id);
size_t rq_tcp_sessions(void);
size_t rq_tcp_sockets(void);
size_t rq_tcp_threads(void);
/* Windows HTTP ABI 1. One async WinHTTP reactor. Ordinary buffered requests;
   direct route, automatic Windows auth/cookies/redirects disabled. flags:
   1 TLS, 2 disable keepalive, 4 complete-body GET (64 MiB cap; no Dart merge).
   Strings are UTF-8 NUL-terminated, inputs copied.
   take transfers an owned chunk, freed exactly once via chunk_release.
   kinds: 1 UTF-8 raw headers, 2 body bytes, 3 EOF, 4 WinHTTP error(code).
   Receive queue high water: 64 KiB. Callback buffers survive handle closing. */
uint64_t rq_http_client_open(const uint8_t* user_agent);
void rq_http_client_close(uint64_t client);
void rq_http_client_finalizer(void* client);
uint64_t rq_http_open(uint64_t client, const uint8_t* host, const uint8_t* path,
    const uint8_t* method, const uint8_t* headers, const uint8_t* body,
    size_t body_length, uint32_t port, uint32_t flags, int64_t dart_port,
    bool (*post_c_object)(int64_t, void*));
const uint8_t* rq_http_take(uint64_t id, size_t* length, uint32_t* kind,
    uint32_t* code, void** owner);
void rq_http_chunk_release(void* owner);
void rq_http_release(uint64_t id);
void rq_http_release_finalizer(void* id);
size_t rq_http_clients(void);
size_t rq_http_requests(void);
size_t rq_http_queue_peak(void);

/* Native replay archive session. Inputs copied unchanged before return.
   One ordered worker owns journals, rolling GIF cache, dedupe and autosave.
   op: 1 start(config), 2 frame, 3 detection, 4 epicenter, 5 source trigger,
   6 GIF(metadata + raw blob), 7 stop/flush, 8 explicit flush.
   take: small status/ack JSON; query(records=1) materializes logs ON DEMAND.
   Returned query/take bytes owned by allocation, free exactly once.
   release asynchronously drains queued commands and closes its own journals. */
uint64_t rq_replay_open(int64_t dart_port, bool (*post_c_object)(int64_t, void*));
uint32_t rq_replay_send(uint64_t id, uint32_t op, const uint8_t* json,
    size_t length, const uint8_t* blob, size_t blob_length, uint64_t serial);
const uint8_t* rq_replay_query(uint64_t id, uint32_t records, size_t* length, void** allocation);
const uint8_t* rq_replay_take(uint64_t id, size_t* length, uint64_t* serial, void** allocation);
void rq_replay_free(void* allocation);
void rq_replay_barrier(uint64_t id);
void rq_replay_release(uint64_t id);
void rq_replay_finalizer(void* id);
size_t rq_replay_workers(void);
size_t rq_tcp_queue_peak(void);

/* K-NET duration-proxy intensity for finite positive sampling rate.
   Borrows count f64 acceleration magnitudes; NaN denotes unavailable result. */
double rq_knet_duration_proxy(const double* samples, size_t count,
                              double sampling_hz, double duration_seconds);

/* Borrowed K-NET channel; writes count aligned offset-corrected samples. */
int32_t rq_knet_align_component(const double* samples, size_t length,
    size_t start, size_t count, double offset_gal, double* output);

/* Computes aligned offset-corrected K-NET features once per station.
   channels/lengths/starts/offsets have exactly three entries (NS, EW, UD).
   Missing channels use null pointers with zero length and start.
   Output has floor(sample_count / samples_per_second) rows of six doubles:
   PGA, horizontal PGA, PGV, RMS, baseline ratio, duration intensity proxy.
   Nullable columns are NaN. Inputs are borrowed; returns zero on success. */
int32_t rq_knet_batch_features(const double* const* channels,
    const size_t* lengths, const size_t* starts, const double* offsets,
    size_t sample_count, size_t samples_per_second, double sampling_hz,
    double duration_seconds, intptr_t baseline_seconds, double epsilon,
    double* output);

/* NIED history queries; original seven-word rows remain unchanged except for
   the internal unusable-evidence bit 64 in flags (missing/stale/undecodable).
   Summary output[9]: delta1/4/9, immediate, recent count, three converted slots,
   four-bit presence mask. An absent delta uses record.lastAscend.
   Pretrigger returns 0 absent, 1 present, negative on error. Fast-rise returns
   0/1 or negative on error. Borrowed handles and output; no pointers retained. */
int32_t rq_observation_nied_summary(const void* history, int64_t observed_us,
    uint32_t has_observed, double* output);
int32_t rq_observation_pretrigger(const void* history, int64_t earliest_us,
    int64_t fallback_us, double* output);
int32_t rq_observation_fast_rise(const void* history, int64_t observed_us, int64_t digit);
uint64_t rq_observation_summary_calls(void);
uint64_t rq_observation_snapshot_calls(void);

/* NIED strict station records: a persistent owner per active event. Input rows
   have 42 u64 words (raw f64 bits), output rows 28. Borrowed arrays, no callback
   or retained pointer. Destroy releases all station state. */
void* rq_station_record_create(int64_t started_us);
void rq_station_record_destroy(void* owner);
int32_t rq_station_record_apply(void* owner, const uint64_t* input, size_t count,
    int64_t observed_us, uint32_t observed_utc, uint64_t* output);
uint64_t rq_station_record_sessions(void);
uint64_t rq_station_record_frames(void);

/* Replay preparation/publication-time policy: borrowed UTF-8 input, owned
   output freed exactly once. No retained payloads or native replay sessions. */
uint8_t* rq_replay_policy_prepare(const uint8_t* input, size_t length, size_t* size);
void rq_replay_policy_free(uint8_t* output, size_t length);
uint64_t rq_replay_policy_calls(void);
uint64_t rq_replay_policy_outputs(void);

#ifdef __cplusplus
}
#endif
#endif

