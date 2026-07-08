# Source Trigger Threshold Review

- Status: `pass`
- Case: `noto_m27_20260621_jma_eq5`
- Fixture: `test/fixtures/source_estimation/noto_m27_20260621_jma_eq5.json`
- Capture provenance locally complete: `1`
- Historical-fetch captures: `1`
- Source trigger missed events: `0`
- Quiet-window pass/total: `2/2`
- Quiet-window decoded frames: `341`
- Quiet-window candidate/confirmed frames: `0/0`
- Quiet-window false estimate frames: `0`
- Threshold review cleared: `1`
- Noise-window validation required: `0`

## Validation

- Errors: none
- Warnings: `capture_received_at_unavailable_historical_fetch`

## Quiet Windows

| Case | Artifact | Frames | Candidate | Confirmed | False estimates | Pass |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `20260614_quiet_175544` | `.dart_tool/source_estimation_benchmark/source_estimation_p0.json` | 41 | 0 | 0 | 0 | yes |
| `quiet_20260625_233535_jst_live` | `.dart_tool/source_estimation_benchmark/quiet_20260625_233535_jst_live.json` | 300 | 0 | 0 | 0 | yes |

## Event Evidence

| Field | Value |
| --- | --- |
| Capture directory | `tmp/captures/noto_m27_20260621_210754_multilayer` |
| Capture directory source | `legacy_capture_directory` |
| Expected GIFs | `1208` |
| Downloaded GIFs | `1208` |
| Failed GIFs | `0` |
| Received-at status | `unavailable_historical_fetch` |
| Triggered frames | `32` |
| Source trigger missed event | `false` |
| JMA-only first delay | `6.0` |
| JMA-only first error km | `7.46` |
| Physical first error km | `40.63` |
| Physical first-error delta km | `33.17` |
| Threshold review cleared | `true` |
| Next split action | `split_assignment_complete` |

## Decision

- The Noto capture is locally complete and uses the legacy `capture.directory` field correctly.
- The capture was obtained by historical fetch, so it does not prove live receive timing.
- Independent quiet-window replay now shows zero source-trigger candidate/confirmed frames and zero source-estimate frames.
- The source-trigger threshold blocker is cleared for this case; the next action is manual event-level split review.
- Experimental physical fusion worsens the early estimate on this case and remains non-production.
