"""Read-only TCP_INFO_v0 for a socket owned by the diagnostic process."""

import ctypes
import sys


class TcpInfo(ctypes.Structure):
    _fields_ = [
        ('State', ctypes.c_uint32), ('Mss', ctypes.c_uint32),
        ('ConnectionTimeMs', ctypes.c_uint64),
        ('TimestampsEnabled', ctypes.c_uint8),
        *[(name, ctypes.c_uint32) for name in (
            'RttUs', 'MinRttUs', 'BytesInFlight', 'Cwnd', 'SndWnd',
            'RcvWnd', 'RcvBuf')],
        ('BytesOut', ctypes.c_uint64), ('BytesIn', ctypes.c_uint64),
        *[(name, ctypes.c_uint32) for name in (
            'BytesReordered', 'BytesRetrans', 'FastRetrans', 'DupAcksIn',
            'TimeoutEpisodes')],
        ('SynRetrans', ctypes.c_uint8),
    ]


def tcp_info(sock):
    if sys.platform != 'win32':
        raise RuntimeError('TCP_INFO_v0 diagnostic requires Windows')
    dll = ctypes.WinDLL('Ws2_32.dll')
    ioctl = dll.WSAIoctl
    ioctl.argtypes = [ctypes.c_size_t, ctypes.c_uint32, ctypes.c_void_p,
                     ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32,
                     ctypes.POINTER(ctypes.c_uint32), ctypes.c_void_p,
                     ctypes.c_void_p]
    ioctl.restype = ctypes.c_int
    version = ctypes.c_uint32(0)
    result = TcpInfo()
    returned = ctypes.c_uint32()
    # mstcpip.h: SIO_TCP_INFO = _WSAIORW(IOC_VENDOR, 39).
    status = ioctl(sock.fileno(), 0xD8000027, ctypes.byref(version), 4,
                   ctypes.byref(result), ctypes.sizeof(result),
                   ctypes.byref(returned), None, None)
    if status != 0:
        raise OSError(dll.WSAGetLastError(), 'SIO_TCP_INFO failed')
    if returned.value < TcpInfo.SynRetrans.offset + 1:
        raise RuntimeError(f'Truncated TCP_INFO_v0: {returned.value}')
    return {name: getattr(result, name) for name, _ in TcpInfo._fields_}
