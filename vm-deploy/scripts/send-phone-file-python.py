#!/usr/bin/env python3
import argparse
import base64
import hashlib
import os
import shlex
import socket
import sys
import time


MARKER = "__CODEX_PHONE_FILE_DONE__"


def receive_until(sock, marker, timeout):
    deadline = time.monotonic() + timeout
    output = bytearray()
    while time.monotonic() < deadline:
        try:
            chunk = sock.recv(4096)
        except BlockingIOError:
            chunk = b""
        if chunk:
            output.extend(chunk)
            if marker in output:
                return output
        else:
            time.sleep(0.05)
    raise TimeoutError(f"timed out waiting for {marker.decode('ascii')}")


def send_payload(
    sock,
    prefix,
    payload,
    suffix,
    line_length=76,
    line_delay=0.002,
    suffix_delay=0.05,
):
    sock.setblocking(True)
    sock.sendall(prefix)
    for offset in range(0, len(payload), line_length):
        sock.sendall(payload[offset : offset + line_length].encode("ascii") + b"\n")
        time.sleep(line_delay)
    time.sleep(suffix_delay)
    sock.sendall(suffix)
    sock.setblocking(False)


def main():
    parser = argparse.ArgumentParser(
        description="Send a file to the Sailfish debug telnet shell."
    )
    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--mode", default="0644")
    parser.add_argument("--host", default=os.environ.get("PHONE_IP", "192.168.2.15"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PHONE_PORT", "2323")))
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument(
        "--line-delay",
        type=float,
        default=float(os.environ.get("PHONE_FILE_LINE_DELAY", "0.002")),
    )
    parser.add_argument(
        "--suffix-delay",
        type=float,
        default=float(os.environ.get("PHONE_FILE_SUFFIX_DELAY", "0.05")),
    )
    args = parser.parse_args()

    with open(args.source, "rb") as source_file:
        data = source_file.read()
    payload = base64.b64encode(data).decode("ascii")
    expected_sha = hashlib.sha256(data).hexdigest()
    destination = shlex.quote(args.destination)
    remote_b64 = shlex.quote(f"{args.destination}.b64")

    prefix = f"""
stty -echo
rm -f {remote_b64}
cat >{remote_b64} <<'EOF_CODEX_PHONE_FILE'
""".encode("ascii")
    suffix = f"""
EOF_CODEX_PHONE_FILE
base64 -d {remote_b64} >{destination}
chmod {shlex.quote(args.mode)} {destination}
actual_sha=$(sha256sum {destination} | awk '{{print $1}}')
rm -f {remote_b64}
stty echo
echo {MARKER}:$actual_sha
""".encode("ascii")

    marker = f"{MARKER}:{expected_sha}".encode("ascii")
    with socket.create_connection((args.host, args.port), timeout=10) as sock:
        time.sleep(1)
        send_payload(
            sock,
            prefix,
            payload,
            suffix,
            line_delay=args.line_delay,
            suffix_delay=args.suffix_delay,
        )
        output = receive_until(sock, marker, args.timeout)

    text = output.decode("utf-8", errors="replace")
    if marker.decode("ascii") not in text:
        print(text, file=sys.stderr)
        return 1
    print(
        f"phone file transfer passed: bytes={len(data)} sha256={expected_sha} "
        f"destination={args.destination}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
