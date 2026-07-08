# PLUM Operating-Point Acceptance Diagnostic

- Status: `pass`
- Frozen test evaluated: `false`
- Production ready: `false`
- Production UI connected: `false`
- Recommended diagnostic candidate: `none`

## Criteria

- Replay `shindo4` recall must be >= `60.0%`.
- Replay `shindo4` false-alarm stations must drop by >= `25.0%` versus baseline.
- Combined synthetic-reveal `shindo4` recall must be >= `70.0%`.
- Combined synthetic-reveal `shindo4` F1 must not fall below the baseline combined branch.
- Replay coverage must include at least `7` complete cases and `1000` decoded frames.

## Baseline

- `plum_like` replay shindo4 recall `84.4%`, false alarms `27`, combined shindo4 P/R/F1 `49.7% / 83.0% / 62.2%`.

## Candidates

| Candidate | Status | Replay shindo4 recall | Replay shindo4 false alarms | Replay false-alarm reduction | Combined shindo4 P/R/F1 | Combined shindo5- P/R/F1 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `plum_like_r20_d0_50` | `warn` | 56.3% | 14 | 48.1% | 56.0% / 72.0% / 63.0% | 58.7% / 45.5% / 51.3% |
| `plum_like_r30_d0_50` | `warn` | 62.5% | 17 | 37.0% | 55.9% / 72.5% / 63.1% | 58.8% / 46.9% / 52.2% |

## Decision

- Advance to frozen test: `false`
- Advance to production: `false`
- Next action: `expand_replay_or_revise_operating_point`

This report is diagnostic-only and must not drive production UI, notifications or warning wording.

