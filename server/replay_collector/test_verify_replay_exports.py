import io
import base64
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from verify_replay_exports import (JsonStream, fingerprint, verify_file,
                                   compressed_block_hashes, stored_hashes, fields)


class VerificationTests(unittest.TestCase):
    def test_original_compressed_block_and_tampering(self):
        chunks = sorted(Path("build/performance/20261005-app-history-input").glob("*.stations.json"))
        if not chunks:
            self.skipTest("Original retained checkpoint is not available")
        raw = chunks[0].read_bytes()
        table = json.loads(raw)
        compressed = gzip.compress(raw, compresslevel=1)
        nodes = table["nodes"]
        block = {"data": base64.b64encode(compressed).decode("ascii"),
                 "sha256": hashlib.sha256(compressed).hexdigest(),
                 "frames": [[nodes[fields(nodes, root)["receivedAt"]],
                             nodes[fields(nodes, fields(nodes, root)["snapshot"])["kind"]]]
                            for root in table["frames"]]}
        self.assertEqual(compressed_block_hashes(block), stored_hashes(table))
        block["frames"][0][0] = "invalid-time"
        with self.assertRaisesRegex(ValueError, "index changed"):
            compressed_block_hashes(block)
        block["data"] = base64.b64encode(b"corrupt").decode("ascii")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            compressed_block_hashes(block)

    def test_standard_json_parser_keeps_original_report_and_unicode(self):
        path = Path("test/fixtures/history_replay/cwa_1150074.rqreplay")
        original = json.loads(path.read_text(encoding="utf-8"))
        stream = JsonStream(io.StringIO(path.read_text(encoding="utf-8")))
        restored = {}
        stream.object(lambda key: restored.update({key: stream.value()}))
        self.assertEqual(restored, original)
        self.assertEqual(stream.peek(), "")

    def test_numeric_token_at_read_boundary_is_not_truncated(self):
        # Parser primitives, not invented station observations.
        values = ["x" * 65530, 1234567890123456789, -0.0, 1.0]
        stream = JsonStream(io.StringIO(json.dumps(values)))
        restored = []
        stream.array(restored.append)
        self.assertEqual(restored, values)
        self.assertEqual(json.dumps(restored), json.dumps(values))

    def test_fingerprints_preserve_numeric_types_and_signed_zero(self):
        self.assertNotEqual(fingerprint(1, None), fingerprint(1.0, None))
        self.assertNotEqual(fingerprint(0.0, None), fingerprint(-0.0, None))

    def test_real_original_760_frame_export(self):
        files = list(Path("build/performance/20261004-recording-probe").glob("*.rqreplay"))
        chunks = Path("build/performance/20261005-app-history-input")
        if len(files) != 1 or not chunks.exists():
            self.skipTest("Original retained local performance artifacts are not available")
        replay = files[0]
        key = replay.name.split("_")[1]
        original = json.loads(Path("test/fixtures/history_replay/cwa_1150074.rqreplay").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory(prefix="rq-original-verification-") as temporary:
            audit = Path(temporary)
            event = audit / key
            event.mkdir()
            for chunk in chunks.glob("*.stations.json"):
                shutil.copyfile(chunk, event / chunk.name)
            (event / "event.json").write_text(json.dumps({"group": {"reports": original["reports"]}}, ensure_ascii=False), encoding="utf-8")
            result = verify_file(replay, audit)
            self.assertEqual(sum(result["frames"].values()), 760)
            self.assertEqual(result["sha256"], "a87c36b4802fd1250020fb7ad7daf1457fea78b8110b7b3f107a183f6fb2c4a0")


if __name__ == "__main__":
    unittest.main()
