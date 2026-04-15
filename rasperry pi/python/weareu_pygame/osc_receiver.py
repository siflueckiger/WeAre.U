from __future__ import annotations

import queue
import threading

from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import ThreadingOSCUDPServer


class OSCReceiver:
    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self.msg_queue: queue.Queue[tuple[str, tuple]] = queue.Queue()
        self.server = None

    def enqueue_message(self, address: str, *args):
        self.msg_queue.put((address, args))

    def start(self):
        dispatcher = Dispatcher()
        dispatcher.set_default_handler(lambda addr, *args: self.enqueue_message(addr, *args))
        self.server = ThreadingOSCUDPServer((self.host, self.port), dispatcher)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        print(f"OSC listening on {self.host}:{self.port}")

    def poll(self):
        while True:
            try:
                yield self.msg_queue.get_nowait()
            except queue.Empty:
                break

    def stop(self):
        if self.server is not None:
            self.server.shutdown()
