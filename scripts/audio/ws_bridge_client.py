#!/usr/bin/env python3
"""
Minimal stdlib-only WebSocket line relay, used by services/Dx5iiBridge.qml
and services/WampBridge.qml to talk to their respective bridge daemon's
local control-plane WebSocket API (dx5iibridge, wamp-bridge -- both
external C apps, see /mnt/github/dx5ii-bridge and /mnt/github/wamp-bridge).

This is a transport adapter, not a client for either device's protocol --
it doesn't know or care what JSON goes over the wire. Quickshell's Process
type can't speak WebSocket directly, so this exists purely to turn "write a
JSON line to stdin" / "read a JSON line from stdout" into real masked
RFC 6455 frames, one per line in each direction:

  stdin line   -> one WS text frame sent to the server
  WS text frame received -> one line printed to stdout, flushed immediately

Control lines printed to stdout, distinguishable from server JSON (which is
always a JSON object) by their own "type" field:
  {"type": "bridge_connected"}
  {"type": "bridge_disconnected", "reason": "..."}

Exits non-zero if the initial connection/handshake fails, so the caller can
tell "never connected" apart from "connected, then dropped".
"""

import base64
import hashlib
import json
import os
import selectors
import socket
import struct
import sys

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def log_control(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def connect(host, port, path, timeout_s):
    sock = socket.create_connection((host, port), timeout=timeout_s)
    sock.settimeout(timeout_s)

    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    sock.sendall(request.encode("ascii"))

    # Read headers up to the blank line terminator. The response is small
    # (just headers, no body precedes frame data), so an unbounded-looking
    # read loop is fine -- it always stops at the terminator or a timeout.
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("connection closed during handshake")
        buf += chunk
        if len(buf) > 65536:
            raise ConnectionError("handshake response too large")

    header_data, _, leftover = buf.partition(b"\r\n\r\n")
    status_line = header_data.split(b"\r\n", 1)[0]
    if b"101" not in status_line:
        raise ConnectionError(f"handshake rejected: {status_line!r}")

    expected_accept = base64.b64encode(
        hashlib.sha1((key + WS_GUID).encode("ascii")).digest()
    ).decode("ascii")
    if expected_accept.encode("ascii") not in header_data:
        raise ConnectionError("Sec-WebSocket-Accept mismatch")

    sock.settimeout(None)
    return sock, leftover


def send_text_frame(sock, payload: str):
    data = payload.encode("utf-8")
    header = bytearray()
    header.append(0x81)  # FIN=1, opcode=1 (text)

    mask_bit = 0x80
    length = len(data)
    if length < 126:
        header.append(mask_bit | length)
    elif length < 65536:
        header.append(mask_bit | 126)
        header += struct.pack(">H", length)
    else:
        header.append(mask_bit | 127)
        header += struct.pack(">Q", length)

    mask_key = os.urandom(4)
    header += mask_key
    masked = bytes(b ^ mask_key[i % 4] for i, b in enumerate(data))
    sock.sendall(bytes(header) + masked)


class FrameReader:
    """Buffers raw bytes from the socket and yields decoded frames.

    Server-to-client frames are never masked per RFC 6455, so no unmasking
    is done here -- this only ever talks to dx5iibridge/wamp-bridge, both of
    which are confirmed-compliant servers.
    """

    def __init__(self, initial: bytes = b""):
        self._buf = bytearray(initial)

    def feed(self, data: bytes):
        self._buf += data

    def pop_frame(self):
        buf = self._buf
        if len(buf) < 2:
            return None

        b0, b1 = buf[0], buf[1]
        opcode = b0 & 0x0F
        length = b1 & 0x7F
        offset = 2

        if length == 126:
            if len(buf) < offset + 2:
                return None
            length = struct.unpack(">H", buf[offset:offset + 2])[0]
            offset += 2
        elif length == 127:
            if len(buf) < offset + 8:
                return None
            length = struct.unpack(">Q", buf[offset:offset + 8])[0]
            offset += 8

        if len(buf) < offset + length:
            return None

        payload = bytes(buf[offset:offset + length])
        del buf[:offset + length]
        return opcode, payload


def send_pong(sock, payload: bytes):
    header = bytearray([0x8A])  # FIN=1, opcode=0xA (pong)
    mask_key = os.urandom(4)
    length = len(payload)
    if length < 126:
        header.append(0x80 | length)
    else:
        header.append(0x80 | 126)
        header += struct.pack(">H", length)
    header += mask_key
    masked = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
    sock.sendall(bytes(header) + masked)


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("usage: ws_bridge_client.py <host> <port> <path>\n")
        return 2

    host = sys.argv[1]
    port = int(sys.argv[2])
    path = sys.argv[3]

    try:
        sock, leftover = connect(host, port, path, timeout_s=5)
    except OSError as e:
        log_control({"type": "bridge_disconnected", "reason": str(e)})
        return 1

    log_control({"type": "bridge_connected"})
    reader = FrameReader(leftover)
    sock.setblocking(False)

    sel = selectors.DefaultSelector()
    sel.register(sock, selectors.EVENT_READ, data="socket")
    sel.register(sys.stdin, selectors.EVENT_READ, data="stdin")

    exit_code = 0
    stdin_open = True
    try:
        while True:
            for key, _ in sel.select():
                if key.data == "stdin":
                    line = sys.stdin.readline()
                    if line == "":
                        # No more commands coming, but the socket may still
                        # have replies in flight -- stop watching stdin
                        # rather than tearing down the connection, and keep
                        # relaying whatever the server still sends.
                        sel.unregister(sys.stdin)
                        stdin_open = False
                        continue
                    line = line.strip()
                    if line:
                        try:
                            send_text_frame(sock, line)
                        except OSError as e:
                            log_control({"type": "bridge_disconnected", "reason": str(e)})
                            return 1
                else:
                    try:
                        chunk = sock.recv(65536)
                    except OSError as e:
                        log_control({"type": "bridge_disconnected", "reason": str(e)})
                        return 1
                    if not chunk:
                        log_control({"type": "bridge_disconnected", "reason": "connection closed"})
                        return 1
                    reader.feed(chunk)
                    while True:
                        frame = reader.pop_frame()
                        if frame is None:
                            break
                        opcode, payload = frame
                        if opcode == 0x1:  # text
                            try:
                                text = payload.decode("utf-8")
                            except UnicodeDecodeError:
                                continue
                            sys.stdout.write(text + "\n")
                            sys.stdout.flush()
                        elif opcode == 0x9:  # ping
                            send_pong(sock, payload)
                        elif opcode == 0x8:  # close
                            log_control({"type": "bridge_disconnected", "reason": "server closed"})
                            return 0
                        # pong (0xA) and anything else: ignore
    finally:
        sel.close()
        try:
            sock.close()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
