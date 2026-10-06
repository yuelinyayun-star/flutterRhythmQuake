# NIED Depth Experiment Archive

Status: experimental only; not integrated into the application.

The user requires all experiments to remain separate from production algorithms.
Do not apply the archived patch to `lib/` for an experiment. A future runnable
candidate must use an isolated experimental implementation and explicit entrypoint.

- `candidate.patch.txt` preserves an unapproved depth-only refinement proposal.
- `candidate_test.dart.txt` preserves candidate-specific synthetic unit tests.
  These are not real observations and are not evidence of real-world accuracy.
- Neither archived file is executable or part of normal Flutter test discovery.
- Production solver SHA-256 at isolation:
  `0b04aedd13a349bf8a3787557ad28e886207ea9a7b27a8706d6ced1ecd7b0f58`.

Raw capture: `tmp/captures/20261003_kii_screenshot_214551_jst_candidate`,
151 original NIED GIFs with capture metadata. Screenshot alignment remains
unverified; EQuake's displayed depth is a reference, not ground truth.

The corrected original-solver baseline passed seven capture cases (1206 frames,
zero missing frames), recorded under
`.dart_tool/small_depth_review_20261003/timed_before/report.json`.
The replay harness advances station timers using original frame timestamps.
Earlier untimed replay comparisons are not valid real-time accuracy evidence:
station hold timers advanced in wall-clock time rather than capture time.
No candidate run with the corrected replay clock has been validated.

The current published local magnitude uses the SREV-kaizou intensity and
epicentral-distance calculation; depth is not a direct input. Alternative
depth-aware magnitude calculations currently contribute diagnostics only.
