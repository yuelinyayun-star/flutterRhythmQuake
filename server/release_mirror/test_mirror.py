import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch, MagicMock

import mirror


class MirrorTests(unittest.TestCase):
    def setUp(self):
        self.release = {"tag_name": "v1.0.5.21-public", "draft": False,
                        "prerelease": False, "published_at": "2026-10-05T05:01:34Z"}
        self.asset = {"id": 1, "name": "RhythmQuake_1.0.5.21_public.apk",
                      "size": 113185454, "state": "uploaded",
                      "digest": "sha256:9cf06c91e476ef9d978a5a1004816a814464a4e81de810d03bc5282c7332eb5e"}
        self.asset["browser_download_url"] = (
            f"https://github.com/{mirror.REPO}/releases/download/"
            f"{self.release['tag_name']}/{self.asset['name']}")
        self.release["assets"] = [self.asset]

    def test_live_asset_names_and_platforms(self):
        for name, platform in [(self.asset["name"], "Android"),
                ("RhythmQuake_Setup_1.0.5.21_public_x64.exe", "Windows"),
                ("RhythmQuake_1.0.5.21_public_linux_x64.tar.gz", "Linux"),
                ("RhythmQuake_1.0.5.21_public_web.zip", "Web")]:
            for suffix in ("", ".sha256"):
                asset = dict(self.asset, name=name + suffix)
                asset["browser_download_url"] = self.asset["browser_download_url"].replace(self.asset["name"], asset["name"])
                self.assertEqual(mirror.asset_info(self.release, asset)[0], platform)

    def test_unrelated_and_development_assets_ignored(self):
        for name in ["../secret.apk", "RhythmQuake_1.0.5.21_dev.apk", "source.zip"]:
            self.assertIsNone(mirror.asset_info(self.release, dict(self.asset, name=name)))

    def test_url_digest_size_and_release_validation(self):
        for change in [{"browser_download_url": "https://example.com/a.apk"},
                       {"digest": None}, {"size": mirror.MAX_ASSET + 1}, {"state": "new"}]:
            with self.assertRaises((ValueError, TypeError)):
                mirror.asset_info(self.release, dict(self.asset, **change))
        for change in [{"draft": True}, {"prerelease": True}, {"tag_name": "../../escape"}]:
            with self.assertRaises(ValueError):
                mirror.asset_info(dict(self.release, **change), self.asset)

    def test_initial_latest_only_and_baseline(self):
        state = {"assets": {}}
        with patch.object(mirror, "api", return_value=self.release):
            self.assertEqual(mirror.select_releases(state), [self.release])
        self.assertEqual(state["since"], self.release["published_at"])

    def test_poll_does_not_miss_intermediate_release(self):
        newer = dict(self.release, tag_name="v1.0.5.22-public", published_at="2026-10-06T00:00:00Z")
        old = dict(self.release, tag_name="v1.0.5.20-public", published_at="2026-10-03T00:00:00Z")
        with patch.object(mirror, "api", return_value=[newer, self.release, old]):
            self.assertEqual(mirror.select_releases({"since": self.release["published_at"]}), [self.release, newer])

    def test_download_is_streamed_and_validated(self):
        payload = b"unit-test-download"
        asset = dict(self.asset, size=len(payload))
        checksum = hashlib.sha256(payload).hexdigest()
        with tempfile.TemporaryDirectory() as directory, patch.object(mirror, "urlopen", return_value=io.BytesIO(payload)):
            path = Path(directory) / "download.part"
            mirror.download(asset, checksum, path)
            self.assertEqual(path.read_bytes(), payload)
            with patch.object(mirror, "urlopen", side_effect=AssertionError("must reuse validated staging")):
                mirror.download(asset, checksum, path)
        with tempfile.TemporaryDirectory() as directory, patch.object(mirror, "urlopen", return_value=io.BytesIO(payload + b"extra")):
            with self.assertRaises(ValueError):
                mirror.download(asset, checksum, Path(directory) / "download.part")

    def test_failed_upload_does_not_create_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(mirror, "validate_config"), patch.object(mirror, "select_releases", return_value=[self.release]), \
                    patch.object(mirror, "download"), patch.object(mirror, "upload", side_effect=ValueError("mismatch")):
                with self.assertRaises(ValueError):
                    mirror.mirror(Path("private.conf"), root)
            self.assertEqual(json.loads((root / "state.json").read_text())["assets"], {})

    def test_success_receipt_then_no_duplicate_upload(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def stage(*args):
                args[-1].write_bytes(b"unit-test-staging")
            with patch.object(mirror, "validate_config"), patch.object(mirror, "select_releases", return_value=[self.release]), \
                    patch.object(mirror, "download", side_effect=stage) as download, patch.object(mirror, "upload") as upload:
                mirror.mirror(Path("private.conf"), root)
                mirror.mirror(Path("private.conf"), root)
                self.assertEqual(download.call_count, 1)
                self.assertEqual(upload.call_count, 1)
                self.assertFalse((root / "download.part").exists())
            state = json.loads((root / "state.json").read_text(encoding="utf-8"))
            self.assertIn("verified_at", state["assets"]["1"])

    def test_lost_response_requires_exact_readback(self):
        payload = b"unit-test-remote"
        process = MagicMock()
        process.__enter__.return_value = process
        process.stdout = io.BytesIO(payload)
        process.wait.return_value = 0
        with patch.object(mirror.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "rclone")), \
                patch.object(mirror.subprocess, "Popen", return_value=process):
            mirror.upload(Path("private.conf"), Path("stage"), "tgfs:test", hashlib.sha256(payload).hexdigest(), len(payload))
        process.stdout = io.BytesIO(payload)
        with patch.object(mirror.subprocess, "run"), patch.object(mirror.subprocess, "Popen", return_value=process):
            with self.assertRaises(ValueError):
                mirror.upload(Path("private.conf"), Path("stage"), "tgfs:test", "0" * 64, len(payload))

    def test_wrong_remote_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config"
            config.write_text("[tgfs]\ntype=alias\nremote=local:path\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                mirror.validate_config(config)


if __name__ == "__main__":
    unittest.main()
