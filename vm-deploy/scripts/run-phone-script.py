#!/usr/bin/env python3
import argparse
import base64
import os
import re
import shlex
import socket
import sys
import time


MARKER = b"__BONITO_PHONE_RC__" + bytes([58])


def receive_result(sock, timeout):
    deadline = time.monotonic() + timeout
    output = bytearray()
    pattern = re.compile(re.escape(MARKER) + rb"([0-9]+)")
    while time.monotonic() < deadline:
        try:
            chunk = sock.recv(4096)
        except BlockingIOError:
            chunk = b""
        if chunk:
            output.extend(chunk)
            match = pattern.search(output)
            if match:
                return bytes(output), int(match.group(1))
        else:
            time.sleep(0.05)
    raise TimeoutError("timed out waiting for phone script result")


def main():
    parser = argparse.ArgumentParser(description="Run a script through the Sailfish debug shell.")
    parser.add_argument("script")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    parser.add_argument("--host", default=os.environ.get("PHONE_IP", "192.168.2.15"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PHONE_PORT", "2323")))
    parser.add_argument("--timeout", type=float, default=float(os.environ.get("NC_TIMEOUT", "220")))
    args = parser.parse_args()

    with open(args.script, "rb") as script_file:
        payload = base64.b64encode(script_file.read()).decode("ascii")

    remote_b64 = "/tmp/bonito-phone-script.b64"
    remote_script = "/tmp/bonito-phone-script.sh"
    command = " ".join(["/bin/sh", remote_script, *(shlex.quote(value) for value in args.arguments)])
    request = f"""stty -echo
cat >{remote_b64} <<'EOF_BONITO_PHONE_SCRIPT'
{payload}
EOF_BONITO_PHONE_SCRIPT
base64 -d {remote_b64} >{remote_script}
chmod +x {remote_script}
{command}
bonito_phone_rc=$?
rm -f {remote_b64} {remote_script}
stty echo
printf '{MARKER.decode("utf-8")}%s\\n' "$bonito_phone_rc"
""".encode("ascii", errors="strict")

    with socket.create_connection((args.host, args.port), timeout=10) as sock:
        time.sleep(1)
        sock.sendall(request)
        sock.setblocking(False)
        output, remote_rc = receive_result(sock, args.timeout)

    text = output.decode("utf-8", errors="replace")
    marker_at = text.rfind(MARKER.decode("utf-8"))
    if marker_at >= 0:
        text = text[:marker_at]
    if text.strip():
        print(text.rstrip())
    return remote_rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, TimeoutError) as error:
        print(f"phone script transport failed: {error}", file=sys.stderr)
        sys.exit(1)
