# Final Catalog Or Hi-net Revision Review Packet

- Status: `pass`
- Split blocker queue: `.dart_tool/source_estimation_split_blocker_queue/report.json`
- Attempts: `docs/data/source_estimation_external_input_attempts.json`
- Packets: `1`
- Manual-review required: `1`
- Automatic clearances: `0`
- Fixture mutations: `0`
- Split manifest mutations: `0`
- Truth promotions: `0`
- Negative attempts: `1`

## Validation

- Errors: none
- Warnings: none

## Packets

### `20260621_iwate_offshore_m33_eq8`

- Planned use: `offshore_reference_pool`
- Split status: `unassigned_reference`
- Fixture: `test/fixtures/source_estimation/iwate_offshore_m33_20260621_eq8.json`
- Truth source: `user_provided_equake_final_report_reference`
- Origin JST: `2026-06-21T11:32:12`
- Negative attempts: `1`
- Required paths:
  - versioned JMA final catalog row
  - authenticated revised Hi-net/JMA source row

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_estimation_split_blocker_queue.ps1
```

- Decision: this packet is intake guidance only. It does not promote the EQuake reference text to truth and does not assign a split.

