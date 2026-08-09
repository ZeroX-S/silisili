#!/usr/bin/env python3
import argparse
import base64
import os
import socket
import sys
import time


MARKER = "__CODEX_PHONE_SCRIPT_DONE__"


def main() -> int:
    parser = argparse.ArgumentParser(description="Send and run a shell script on the Sailfish debug telnet shell.")
    parser.add_argument("script")
    parser.add_argument("--host", default=os.environ.get("PHONE_IP", "192.168.2.15"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PHONE_PORT", "2323")))
    parser.add_argument("--wait-before-send", type=float, default=float(os.environ.get("WAIT_BEFORE_SEND", "1")))
    parser.add_argument("--idle-timeout", type=float, default=float(os.environ.get("IDLE_TIMEOUT", "5")))
    parser.add_argument("--total-timeout", type=float, default=float(os.environ.get("TOTAL_TIMEOUT", "240")))
    args = parser.parse_args()

    with open(args.script, "rb") as f:
        payload = base64.b64encode(f.read()).decode("ascii")

    remote_b64 = "/tmp/bonito-phone-script.b64"
    remote_script = "/tmp/bonito-phone-script.sh"
    lines = [payload[i : i + 76] for i in range(0, len(payload), 76)]
    command = "\n".join(
        [
            "",
            f"cat >{remote_b64} <<'EOF_BONITO_PHONE_SCRIPT'",
            *lines,
            "EOF_BONITO_PHONE_SCRIPT",
            f"base64 -d {remote_b64} >{remote_script}",
            f"chmod +x {remote_script}",
            f"/bin/sh {remote_script}",
            "rc=$?",
            f"echo {MARKER}:$rc",
            "",
        ]
    )

    deadline = time.monotonic() + args.total_timeout
    last_data = time.monotonic()
    output = bytearray()

    with socket.create_connection((args.host, args.port), timeout=10) as sock:
        sock.setblocking(False)
        time.sleep(args.wait_before_send)
        sock.sendall(command.encode("utf-8"))

        while time.monotonic() < deadline:
            try:
                chunk = sock.recv(4096)
            except BlockingIOError:
                chunk = b""
            except socket.timeout:
                chunk = b""

            if chunk:
                output.extend(chunk)
                last_data = time.monotonic()
                print(chunk.decode("utf-8", errors="replace"), end="", flush=True)
                if MARKER.encode("ascii") in output:
                    break
            else:
                if time.monotonic() - last_data > args.idle_timeout and MARKER.encode("ascii") in output:
                    break
                time.sleep(0.1)
        else:
            print(f"\nTimed out waiting for {MARKER}", file=sys.stderr)
            return 124

    text = output.decode("utf-8", errors="replace")
    for line in reversed(text.splitlines()):
        if line.startswith(f"{MARKER}:"):
            try:
                return int(line.rsplit(":", 1)[1])
            except ValueError:
                return 1

    print(f"\nDid not see {MARKER}", file=sys.stderr)
    return 125


if __name__ == "__main__":
    sys.exit(main())
