# Source Wording Surface Audit

- Status: `pass`
- Diagnostic only: `true`
- Checks: `7`
- Passed checks: `7`
- Failed checks: `0`

## Checks

| Check | Surface | Status | Expectation |
| --- | --- | --- | --- |
| `source_card_candidate_copy` | `source_estimation_unified_card` | `pass` | source card may show production quality plus explicit diagnostic candidate-region text |
| `candidate_region_expired_hidden` | `source_estimation_unified_card` | `pass` | expired candidate-region state must not be shown as alert uncertainty |
| `source_trigger_line_no_candidate_region` | `source_estimation_unified_card` | `pass` | source-estimation warnArea line remains trigger P/S/O text, not candidate-region wording |
| `source_event_not_inserted_into_official_unified_queue` | `provider_unified_queue` | `pass` | source-estimation event is composed locally for UI and is not inserted into provider unified event queue |
| `voice_path_excludes_candidate_region` | `voice_tts` | `pass` | voice/TTS path must not consume candidate-region diagnostic wording |
| `official_adapter_excludes_candidate_region` | `official_alert_adapter` | `pass` | official data adapters must not consume source-estimation candidate-region metadata |
| `debug_surface_keeps_full_candidate_region_metadata` | `debug_and_reports` | `pass` | debug surfaces may show full candidate-region residual/local-support metadata |

## Decision

- Current source-estimation candidate-region wording is limited to the source-estimation unified card apiTypeLabel.
- Expired candidate-region state is hidden from the source card and remains debug/report-only.
- Voice/TTS and official adapter paths do not consume candidate-region metadata.
- Production coordinate switching remains forbidden by upstream matrix and boundary reports.

## Validation

- Status: `pass`.
- Violations: none.

