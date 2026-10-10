"""Background serial reader for the BU03 DW3000 anchor (USB).

Runs in its own daemon thread so UWB traffic is never blocked by rendering.
Parses the `CmdM:4` binary frames and hands (tagid, mask, kalman) to a
callback. Auto-reconnects to any port matching PORT_HINT.
"""

import struct
import threading
import time

try:
    import serial
    from serial.tools import list_ports
    _HAVE_SERIAL = True
except Exception:                       # pyserial not installed
    _HAVE_SERIAL = False

HEAD = b"CmdM:4"
FRAME_LEN = 101
EXPECTED_LEN = 91


class FrameParser:
    """Incremental parser; feeding arbitrary byte chunks yields whole frames."""

    def __init__(self):
        self.buf = bytearray()

    def push(self, data):
        self.buf.extend(data)

    def next(self):
        while True:
            idx = self.buf.find(HEAD)
            if idx < 0:
                if len(self.buf) > len(HEAD) - 1:
                    del self.buf[:len(self.buf) - (len(HEAD) - 1)]
                return None
            if len(self.buf) - idx < FRAME_LEN:
                del self.buf[:idx]
                return None
            if self.buf[idx + 6] != EXPECTED_LEN:
                del self.buf[:idx + 1]
                continue
            tagid = self.buf[idx + 11] | (self.buf[idx + 12] << 8)
            mask = self.buf[idx + 16]
            kalman = list(struct.unpack_from("<8I", self.buf, idx + 50))
            del self.buf[:idx + FRAME_LEN]
            return (tagid, mask, kalman)


class SerialReader:
    def __init__(self, on_frame, port_hint="usbmodem", baud=115200,
                 on_status=None):
        self.on_frame = on_frame
        self.on_status = on_status          # callback(text) for status changes
        self.port_hint = port_hint
        self.baud = baud
        self.port = None
        self.port_name = ""
        self._stop = threading.Event()
        self._thread = None
        self._parser = FrameParser()

    def start(self):
        if not _HAVE_SERIAL:
            self._status("pyserial not installed -- serial disabled")
            return
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self.port is not None:
            try:
                self.port.close()
            except Exception:
                pass

    def _status(self, text):
        if self.on_status:
            self.on_status(text)

    def _find_port(self):
        for p in list_ports.comports():
            name = p.device or ""
            if self.port_hint.lower() in name.lower():
                return name
        return None

    def _run(self):
        while not self._stop.is_set():
            if self.port is None:
                name = self._find_port()
                if name is None:
                    self._status("no port matching \"" + self.port_hint + "\"")
                    time.sleep(2)
                    continue
                try:
                    self.port = serial.Serial(name, self.baud, timeout=0.1)
                    self.port_name = name
                    self._status("connected: " + name)
                except Exception as e:
                    self.port = None
                    self._status("failed to open " + name + ": " + e)
                    time.sleep(2)
                    continue
            try:
                data = self.port.read(4096)
                if data:
                    self._parser.push(data)
                    while True:
                        f = self._parser.next()
                        if f is None:
                            break
                        self.on_frame(*f)
            except Exception as e:
                self._status("serial error: " + str(e))
                try:
                    self.port.close()
                except Exception:
                    pass
                self.port = None
                time.sleep(1)
