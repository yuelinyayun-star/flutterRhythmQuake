import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from upload_telegram import discover, upload_file


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.identifier = 'tgfs'
        self.config = self.root / 'telegram.conf'
        self.remote_config()

    def tearDown(self):
        self.temp.cleanup()

    def remote_config(self, alias='tgfs-webdav:telegram', endpoint='http://127.0.0.1:1900/webdav', kind='webdav'):
        self.config.write_text(
            f'[tgfs]\ntype = alias\nremote = {alias}\n'
            f'[tgfs-webdav]\ntype = {kind}\nurl = {endpoint}\n', encoding='utf-8')

    def replay(self):
        # Only exercise queue bytes here; application compatibility has Dart tests.
        data = b'{"protocol-test":true}'
        name = f'RhythmQuake_{"b" * 64}_{hashlib.sha256(data).hexdigest()}.rqreplay'
        file = self.root / name
        file.write_bytes(data)
        return file, data

    def test_discovery_selects_telegram_not_local_or_r2(self):
        self.assertEqual(discover(self.config), (self.identifier, self.config))
        self.remote_config(kind='local')
        with self.assertRaises(ValueError):
            discover(self.config)

    def test_wrong_aliases_fail_closed(self):
        for alias in ['r2:', '/tmp/local', 'tgfs-webdav:other', 'tgfs-webdav:telegram/../other']:
            self.remote_config(alias=alias)
            with self.assertRaises(ValueError):
                discover(self.config)

    def test_non_loopback_remote_is_rejected(self):
        for endpoint in ['https://example.com/', 'http://127.0.0.1:1901/webdav',
                         'http://127.0.0.1:1900/other', 'http://user@127.0.0.1:1900/webdav']:
            self.remote_config(endpoint=endpoint)
            with self.assertRaises(ValueError):
                discover(self.config)

    def test_upload_retained_until_remote_readback_matches(self):
        file, data = self.replay()
        calls = []
        def remote(config, *args, output=None):
            calls.append(args)
            if args[0] == 'cat':
                output.write(data)
        with patch('upload_telegram.run_rclone', remote):
            upload_file(file, self.config, self.identifier)
        self.assertFalse(file.exists())
        self.assertTrue(file.with_suffix('.uploaded.json').exists())
        self.assertEqual(calls[0][0], 'copyto')
        self.assertTrue(calls[0][2].startswith('tgfs:RhythmQuake回放文件夹/'))
        self.assertIn('--immutable', calls[0])
        self.assertEqual(calls[1][0], 'cat')

    def test_failure_and_mismatch_keep_pending_file(self):
        file, _ = self.replay()
        with patch('upload_telegram.run_rclone', side_effect=RuntimeError('test')):
            with self.assertRaises(RuntimeError):
                upload_file(file, self.config, self.identifier)
        self.assertTrue(file.exists())
        with patch('upload_telegram.run_rclone'):
            with self.assertRaises(ValueError):
                upload_file(file, self.config, self.identifier)
        self.assertTrue(file.exists())
        self.assertFalse(file.with_suffix('.uploaded.json').exists())

    def test_local_hash_mismatch_never_uploads(self):
        file, _ = self.replay()
        file.write_bytes(b'changed')
        with patch('upload_telegram.run_rclone') as remote:
            with self.assertRaises(ValueError):
                upload_file(file, self.config, self.identifier)
            remote.assert_not_called()
        self.assertTrue(file.exists())

    def test_unknown_upload_result_recovers_only_with_matching_readback(self):
        file, data = self.replay()
        def remote(config, *args, output=None):
            if args[0] == 'copyto':
                raise RuntimeError('response lost')
            output.write(data)
        with patch('upload_telegram.run_rclone', remote):
            upload_file(file, self.config, self.identifier)
        self.assertFalse(file.exists())
        self.assertTrue(file.with_suffix('.uploaded.json').exists())


if __name__ == '__main__':
    unittest.main()
