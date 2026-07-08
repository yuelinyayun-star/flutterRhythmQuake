# Hi-net Capture Provenance Review

- Status: `pass`
- Truth review: `.dart_tool/hinet_truth_quality_review/report.json`
- Decision file: `docs/data/hinet_capture_provenance_review_decisions.json`
- Cases: `1`
- Pending repair/exclusion: `0`
- Exclusion approved: `1`
- Ready after exclusion: `1`
- Unresolved capture issues: `0`
- Failed GIFs: `1`
- Missing frames: `1`

## Validation

- Errors: none
- Warnings: none

## Cases

| Case | Decision | Capture | Failed | Missing | Exclusion | Ready | Blocking evidence |
| --- | --- | --- | ---: | ---: | --- | --- | --- |
| `20260620_iwate_offshore_m34_ref` | `capture_frame_exclusion_approved` | `tmp/captures/20260620_212527_jst_iwate_offshore_m34_ref` | 1 | 1 | yes | yes | `capture_repair_attempt` |

## Decision

- This report does not repair or exclude files automatically.
- A capture-incomplete Hi-net case remains blocked until the missing frame is repaired or a reviewer explicitly approves exclusion in the decision file.
