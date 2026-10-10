/**
 * Background serial reader for the BU03 DW3000 anchor (USB).
 *
 * Reads 115200 baud from any port matching `portHint` (default `usbmodem`) and
 * auto-reconnects. Parses the binary `CmdM:4` frames and calls `onFrame` with
 * (tagid, mask, kalman). Ported from `sender_py/serial_reader.py`.
 */
import { SerialPort } from "serialport";

export const HEAD = Buffer.from("CmdM:4", "ascii");
export const FRAME_LEN = 101;
export const EXPECTED_LEN = 91;

export interface Frame {
  tagid: number;
  mask: number;
  kalman: number[];
}

/** Incremental parser; feeding arbitrary chunks yields whole frames. */
export class FrameParser {
  private buf: Buffer = Buffer.alloc(0);

  push(data: Buffer): void {
    this.buf = this.buf.length === 0 ? data : Buffer.concat([this.buf, data]);
  }

  next(): Frame | null {
    for (;;) {
      const idx = this.buf.indexOf(HEAD);
      if (idx < 0) {
        if (this.buf.length > HEAD.length - 1) {
          this.buf = this.buf.subarray(this.buf.length - (HEAD.length - 1));
        }
        return null;
      }
      if (this.buf.length - idx < FRAME_LEN) {
        this.buf = this.buf.subarray(idx);
        return null;
      }
      if (this.buf.readUInt8(idx + 6) !== EXPECTED_LEN) {
        this.buf = this.buf.subarray(idx + 1);
        continue;
      }
      const tagid = this.buf.readUInt16LE(idx + 11);
      const mask = this.buf.readUInt8(idx + 16);
      const kalman: number[] = new Array(8);
      for (let i = 0; i < 8; i++) kalman[i] = this.buf.readUInt32LE(idx + 50 + i * 4);
      this.buf = this.buf.subarray(idx + FRAME_LEN);
      return { tagid, mask, kalman };
    }
  }
}

export interface SerialReaderOptions {
  onFrame: (frame: Frame) => void;
  onStatus?: (text: string) => void;
  portHint?: string;
  baudRate?: number;
}

export class SerialReader {
  private onFrame: (frame: Frame) => void;
  private onStatus: (text: string) => void;
  private portHint: string;
  private baudRate: number;
  private port: SerialPort | null = null;
  private parser = new FrameParser();
  private stopped = true;
  private connecting = false;
  private timer: NodeJS.Timeout | null = null;
  private listTimer: NodeJS.Timeout | null = null;

  portName = "";

  constructor(opts: SerialReaderOptions) {
    this.onFrame = opts.onFrame;
    this.onStatus = opts.onStatus ?? (() => {});
    this.portHint = (opts.portHint ?? "usbmodem").toLowerCase();
    this.baudRate = opts.baudRate ?? 115200;
  }

  isConnected(): boolean {
    return this.port !== null && this.port.isOpen;
  }

  start(): void {
    if (!this.stopped) return;
    this.stopped = false;
    void this.scan();
  }

  stop(): void {
    this.stopped = true;
    if (this.timer) clearTimeout(this.timer);
    if (this.listTimer) clearTimeout(this.listTimer);
    this.timer = null;
    this.listTimer = null;
    const p = this.port;
    this.port = null;
    if (p && p.isOpen) {
      p.removeAllListeners();
      p.close(() => {});
    }
  }

  private async scan(): Promise<void> {
    if (this.stopped || this.connecting || this.port) return;
    this.connecting = true;
    try {
      const ports = await SerialPort.list();
      const match = ports.find((p) => (p.path ?? "").toLowerCase().includes(this.portHint));
      if (!match) {
        this.onStatus(`no port matching "${this.portHint}"`);
        this.listTimer = setTimeout(() => void this.scan(), 2000);
        return;
      }
      await this.open(match.path);
    } catch (err) {
      this.onStatus(`serial scan error: ${String(err)}`);
      this.listTimer = setTimeout(() => void this.scan(), 2000);
    } finally {
      this.connecting = false;
    }
  }

  private open(path: string): Promise<void> {
    return new Promise((resolve) => {
      const port = new SerialPort({ path, baudRate: this.baudRate, autoOpen: false });
      port.open((err) => {
        if (err) {
          this.onStatus(`failed to open ${path}: ${err.message}`);
          this.listTimer = setTimeout(() => void this.scan(), 2000);
          resolve();
          return;
        }
        this.port = port;
        this.portName = path;
        this.parser = new FrameParser();
        this.onStatus(`connected: ${path}`);
        port.on("data", (chunk: Buffer) => this.handleData(chunk));
        port.on("error", (e) => this.handleError(e));
        port.on("close", () => this.handleClose(port));
        resolve();
      });
    });
  }

  private handleData(chunk: Buffer): void {
    this.parser.push(chunk);
    for (;;) {
      const frame = this.parser.next();
      if (frame === null) break;
      this.onFrame(frame);
    }
  }

  private handleError(err: Error): void {
    this.onStatus(`serial error: ${err.message}`);
    const p = this.port;
    this.port = null;
    if (p && p.isOpen) p.close(() => {});
    this.scheduleReconnect();
  }

  private handleClose(port: SerialPort): void {
    if (this.port === port) {
      this.port = null;
      if (!this.stopped) {
        this.onStatus("serial disconnected");
        this.scheduleReconnect();
      }
    }
  }

  private scheduleReconnect(): void {
    if (this.stopped) return;
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => void this.scan(), 1000);
  }
}
