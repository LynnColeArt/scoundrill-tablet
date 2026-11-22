"""In-process, length-delimited native calls; no subprocess or NUL-terminated data."""
import ctypes as C
import json
from pathlib import Path
import sys
import weakref

class NativeError(Exception):
    def __init__(self, status, data):
        self.status, self.data = status, data
        self.kind = data.get('error', {}).get('type', 'NativeError') if isinstance(data, dict) else 'NativeError'
        super().__init__(self.kind)

class Result(C.Structure):
    _fields_ = [('data', C.c_void_p), ('len', C.c_size_t), ('owner', C.c_uint64)]

class Cancellation:
    def __init__(self, library):
        self.library = library
        self.handle = library.lib.ziggify_cancel_new()
        if not self.handle:
            raise MemoryError('cancellation allocation failed')
        self._finalizer = weakref.finalize(self, library.lib.ziggify_cancel_free, self.handle)
    def cancel(self):
        if self.library.lib.ziggify_cancel(self.handle):
            raise ValueError('closed cancellation handle')
    def close(self):
        if self.handle:
            self._finalizer()
            self.handle = 0
    def __enter__(self):
        return self
    def __exit__(self, *_):
        self.close()

class Library:
    def __init__(self, path=None):
        suffix = 'ziggify_port.dll' if sys.platform == 'win32' else 'libziggify_port.dylib' if sys.platform == 'darwin' else 'libziggify_port.so'
        self.lib = C.CDLL(str(path or Path(__file__).parent/'zig-out'/'lib'/suffix))
        self.lib.ziggify_abi_version.restype = C.c_uint32
        if self.lib.ziggify_abi_version() != 1:
            raise RuntimeError('unsupported Ziggify ABI version')
        self.lib.ziggify_call.argtypes = [C.c_void_p, C.c_size_t, C.c_uint64, C.POINTER(Result)]
        self.lib.ziggify_call.restype = C.c_uint32
        self.lib.ziggify_release.argtypes = [C.POINTER(Result)]
        self.lib.ziggify_release.restype = C.c_uint32
        self.lib.ziggify_cancel_new.restype = C.c_uint64
        for name in ['ziggify_cancel','ziggify_cancel_free']:
            f = getattr(self.lib, name); f.argtypes = [C.c_uint64]; f.restype = C.c_uint32
        self.lib.ziggify_live_allocations.restype = C.c_size_t
    def cancellation(self):
        return Cancellation(self)
    def call_raw(self, request, cancellation=None):
        request = bytes(request)
        if len(request) > 16*1024*1024:
            raise ValueError('request exceeds native input limit')
        # Close/cancel racing with call acquisition is safe in the native registry.
        # A closed wrapper is rejected, rather than silently disabling cancellation.
        if cancellation is not None and cancellation.library is not self:
            raise ValueError('cancellation belongs to another library wrapper')
        handle = cancellation.handle if cancellation is not None else 0
        if cancellation is not None and not handle:
            raise ValueError('closed cancellation handle')
        result = Result()
        status = self.lib.ziggify_call(request, len(request), handle, C.byref(result))
        try:
            data = C.string_at(result.data, result.len) if result.data else b''
            return status, data
        finally:
            self.lib.ziggify_release(C.byref(result))
    def call(self, request, cancellation=None):
        status, raw = self.call_raw(json.dumps(request, ensure_ascii=False, separators=(',',':'), allow_nan=False).encode(), cancellation)
        data = json.loads(raw) if raw else None
        if status:
            raise NativeError(status, data)
        return data
