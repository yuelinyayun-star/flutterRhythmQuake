# SREV detector port

This vendored Rust crate is the previously validated Rust port of the Scratch Realtime Earthquake Viewer modified edition, based on the modified project's `srev-s/assets/project.json` (not the unmodified upstream).

- Original SREV: kotoho7, https://github.com/kotoho7/scratch-realtime-earthquake-viewer-page
- Modified edition: https://srev-s.t0729.com/ ; Chinese translation snapshot ZeroStar645/srev-chinese-translation.
- License: CC BY-SA 2.0, https://creativecommons.org/licenses/by-sa/2.0/ ; upstream credits: https://github.com/kotoho7/scratch-realtime-earthquake-viewer-page#クレジット
- Changes: Rust translation of original block procedures, runtime optimization, reproducible HYP RNG and magnitude wrapper; this copy preserves that implementation. Original port and conversion tooling are in `D:\flutterApp\srev-chinese-translation-tauri\src-tauri` on the development device. Integration adapter outside this crate: `native/station_core/src/srev_nied.rs`.

RhythmQuake uses the detection path only. Its own HYP and magnitude algorithms are retained. See `docs/srev_nied_migration_handoff_20261125.md` and the integration report for validation scope.
