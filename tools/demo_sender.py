#!/usr/bin/env python3
"""Stream synthetic JPEG frames to the shell app over the MPNL TCP protocol.

The app is the TCP server: 1P listens on 24870 and 2P on 24880. Point this
script at whatever address reaches the tablet: 127.0.0.1 when a USB forward is
in place, or the tablet's LAN address when both devices are on the same Wi-Fi.

  python tools/demo_sender.py 127.0.0.1 --slot 1 --fps 12
  python tools/demo_sender.py 192.168.1.23 --slot 2
"""
import argparse
import itertools
import socket
import struct
import time
from pathlib import Path

MAGIC = b"MPNL"
VERSION = 1
TYPE_CONTROL = 0x07
TYPE_VIDEO = 0x10


def frame(kind, payload):
    if len(payload) > 65000:
        raise ValueError(f"frame {kind:#04x} is {len(payload)} bytes, limit is 65000")
    return MAGIC + bytes([VERSION, kind]) + struct.pack("<H", len(payload)) + payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", help="tablet / forwarder address")
    parser.add_argument("--port", type=int, default=None,
                        help="default: 24870 for 1P, 24880 for 2P")
    parser.add_argument("--slot", type=int, choices=(1, 2), default=1)
    parser.add_argument("--fps", type=float, default=12.0)
    parser.add_argument("--frames", type=Path,
                        default=Path(__file__).parent / "frames",
                        help="directory of JPEG frames (default: tools/frames)")
    parser.add_argument("--once", action="store_true", help="stop after one loop")
    args = parser.parse_args()

    port = args.port or (24880 if args.slot == 2 else 24870)
    paths = sorted(args.frames.glob("*.jpg")) + sorted(args.frames.glob("*.jpeg"))
    if not paths:
        raise SystemExit(f"no JPEG frames in {args.frames}")
    payloads = [path.read_bytes() for path in paths]

    sock = socket.create_connection((args.host, port))
    print(f"connected to {args.host}:{port} (slot {args.slot}, {len(payloads)} frames)")
    sock.sendall(frame(TYPE_CONTROL, bytes([2, args.slot])))
    sock.sendall(frame(TYPE_CONTROL, bytes([1, 1])))

    interval = 1.0 / args.fps if args.fps > 0 else 0
    deadline = time.monotonic()
    source = payloads if args.once else itertools.cycle(payloads)
    try:
        for data in source:
            sock.sendall(frame(TYPE_VIDEO, data))
            deadline += interval
            delay = deadline - time.monotonic()
            if delay > 0:
                time.sleep(delay)
    except (KeyboardInterrupt, BrokenPipeError, ConnectionResetError):
        pass
    finally:
        sock.close()
        print("closed")


if __name__ == "__main__":
    main()
