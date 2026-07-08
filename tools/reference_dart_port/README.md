# kotoho7 Reference Dart Port (NON-PRODUCTION)

## NON-PRODUCTION declaration

This directory (`tools/reference_dart_port/`) is a **reference-only** Dart port
of the kotoho7 receiver-core JavaScript (`tools/kotoho7_receiver_compiled_core.js`).
It is **NOT compiled into the Flutter app** and is **NOT used in production**.

The port exists to make the cloud-RT → HYP (震源推算) procedure chain auditable
in Dart: every JavaScript procedure factory along the path is mirrored 1:1,
preserving aliases (`b0`..`bN`), factory names, generator names, parameter names
(`p0`..`pN`), control flow branches, and expression nesting.

## Cloud variable limitation

The JS bridge does **NOT** fetch cloud variables from a server. Cloud strings
(`☁ c2h`, `☁ c2b0`..`☁ c2b7`) must be supplied externally as a parameter to the
ported `Wクラウド変数更新したら` procedure.

For real-time WebSocket acquisition, mirror the handshake in
`tools/probe_kotoho7_cloud_eew.py:215-266`:
- `wss://clouddata-srev.kothn.net` / `.turbowarp.org` / `.turbowarp.xyz`
- `project_id`: `kotoho7.github.io/srev`

The Dart port provides **no network code**. Cloud strings are inputs.

## Files

| File | Purpose |
|---|---|
| `kotoho7_scratch_runtime.dart` | 1:1 Dart port of the Scratch/TurboWarp runtime shim (Variable/Target/Runtime/Thread, `scratchNumber`, `compareLessThan`, `mod`, `listGet`, `letterOf`, `daysSince2000`, `startHats`, `callProcedure`, `snapshotCore`, `makeThread`). Mirrors JS lines 66924-66962 of `kotoho7_receiver_compiled_core.js`. |
| `kotoho7_snapshot_initializer.dart` | GENERATED const initializer for the SNAPSHOT (334 variables: 251 stage + 83 receiver; 64661 list items; 1160 KB). Produced by `tools/_extract_snapshot_to_dart.js`. **Do not edit by hand.** |
| `kotoho7_path_procedures.dart` | 1:1 structural-mirror port of the 47 procedure factories along the cloud-RT → W震度復元 → W揺れ検出許可 → W検出id1_全点へ適用 → W円検出の毎処理 → HYP path. Extracted from `PROCEDURE_FACTORY_SOURCES` (JS lines 7-165) and dumped readably to `tools/_extracted_path_procedures.js`. |

## Path

The 47 procedures implement the following call chain (mirrors JS exactly):

```
Wクラウド変数更新したら  (cloud RT string entry point)
  └─ W震度復元            (intensity restoration from cloud string)
       └─ W揺れ検出許可    (shake detection permission)
            └─ W検出id1_全点へ適用  (apply detection id1 to all points)
                 └─ W円検出の毎処理  (per-circle detection processing)
                      └─ ZHYP:震源検出  (epicenter detection → HYP output)
```

## How to use

```dart
import 'tools/reference_dart_port/kotoho7_scratch_runtime.dart';
import 'tools/reference_dart_port/kotoho7_snapshot_initializer.dart';

// 1. Build a thread from the SNAPSHOT (registers all 47 procedures).
final thread = makeThread(kotoho7Snapshot);

// 2. Inject time (optional — defaults to wall clock).
setNowMs(1234567890000);

// 3. Supply a cloud RT string externally.
const cloudRt = '<c2h string from wss://clouddata-srev.kothn.net>';

// 4. Run the cloud update entry point.
callProcedure(thread, 'Wクラウド変数更新したら', [cloudRt]);

// 5. Read back HYP results.
final result = snapshotCore(thread);
print(result['hyp']); // {lon, lat, depth, origin, error, ...}
```

## Translation rules

See the header of `kotoho7_path_procedures.dart` for the full mapping table.
Key conventions:

- `+x || 0` → `or0(x)` (JS `Number(x)` with falsy → 0 fallback)
- `("" + x)` → `x.toString()`
- `(("" + x))[(i|0)-1] || ""` → `letterOf(x, i)` (1-based char access)
- `value[(i|0)-1] ?? ""` → `indexGet(value, i)` (1-based list access)
- `(i | 0)` → `scratchNumber(i).truncate()`
- `mod(a, b)` → `scratchMod(a, b)`
- `Math.PI` → `math.pi`; `Math.round(x)` → `(scratchNumber(x)).round()`
- `yield;` → `// yield` (procedures are synchronous; `runMaybeGenerator` drains)
- `yield* thread.procedures["K"](args)` → `callProcedure(thread, 'K', args)  // yield*`
- Variable IDs containing `$` are escaped as `\$` in Dart string literals

## Testing

```bash
dart analyze tools/reference_dart_port/
dart test tools/reference_dart_port/kotoho7_path_procedures_test.dart
```

## Regenerating the snapshot

```bash
node tools/_extract_snapshot_to_dart.js
```

This re-extracts the SNAPSHOT from `tools/kotoho7_receiver_compiled_core.js`
and overwrites `kotoho7_snapshot_initializer.dart`.
