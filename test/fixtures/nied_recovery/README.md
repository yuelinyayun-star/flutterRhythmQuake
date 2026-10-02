# Original NIED Recovery Test Frames

These 18 GIF files are byte-for-byte copies from the existing local Nara
capture `20260610_180130_jst_nara_m36`. The filename timestamps are JST:
2026-06-10 18:01:20 through 18:01:35, plus 18:01:50 and 18:01:51.

No pixels, station values or image metadata were modified. SHA-256 hashes
were compared with the original files when these fixtures were copied.

They support offline recovery-order, late-response and station-JSON archive
tests without requiring the ignored local `tmp/captures` directory. Test
transport clock and metadata timing are controlled separately; GIF bytes
are always read directly from these original observations.
