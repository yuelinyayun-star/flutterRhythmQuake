"""Test diagnostic socket setup without connecting to a public service."""

import socket
import unittest
from unittest.mock import Mock, call, patch

from probe_seedlink_waveform_transport import connect_tcp


class ConnectTcpTest(unittest.TestCase):
    addresses = [
        (socket.AF_INET, socket.SOCK_STREAM, 6, '', ('192.0.2.1', 18500)),
        (socket.AF_INET, socket.SOCK_STREAM, 6, '', ('192.0.2.2', 18500)),
    ]

    def test_default_preserves_existing_connect(self):
        with patch('socket.create_connection') as connect:
            result = connect_tcp('example.test', 18500)
        connect.assert_called_once_with(('example.test', 18500), timeout=12)
        self.assertIs(result, connect.return_value)

    def test_buffer_is_set_before_connect(self):
        sock = Mock()
        with patch('socket.getaddrinfo', return_value=self.addresses), \
                patch('socket.socket', return_value=sock):
            self.assertIs(connect_tcp('example.test', 18500, 4194304), sock)
        self.assertEqual(sock.mock_calls, [
            call.settimeout(12),
            call.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4194304),
            call.connect(('192.0.2.1', 18500)),
        ])

    def test_failed_address_is_closed_before_next_address(self):
        first, second = Mock(), Mock()
        first.connect.side_effect = OSError('first address failed')
        with patch('socket.getaddrinfo', return_value=self.addresses), \
                patch('socket.socket', side_effect=[first, second]):
            self.assertIs(connect_tcp('example.test', 18500, 4194304), second)
        first.close.assert_called_once()
        second.connect.assert_called_once_with(('192.0.2.2', 18500))
        second.close.assert_not_called()

    def test_explicit_address_must_be_in_current_dns(self):
        with patch('socket.getaddrinfo', return_value=self.addresses), \
                patch('socket.socket') as create:
            with self.assertRaisesRegex(ValueError, 'current hostname DNS'):
                connect_tcp('example.test', 18500, resolved_address='192.0.2.3')
        create.assert_not_called()

    def test_explicit_address_does_not_fall_back_to_other_ingress(self):
        sock = Mock()
        failure = OSError('selected address failed')
        sock.connect.side_effect = failure
        with patch('socket.getaddrinfo', return_value=self.addresses), \
                patch('socket.socket', return_value=sock) as create:
            with self.assertRaises(OSError) as raised:
                connect_tcp('example.test', 18500, resolved_address='192.0.2.2')
        self.assertIs(raised.exception, failure)
        self.assertEqual(create.call_count, 1)
        sock.connect.assert_called_once_with(('192.0.2.2', 18500))
        sock.setsockopt.assert_not_called()
        sock.close.assert_called_once()


if __name__ == '__main__':
    unittest.main()
