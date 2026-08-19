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
    parser.add_argument(
        "--output",
        help="Write the captured device output to this file before returning.",
    )
    parser.add_argument(
        "--line-delay",
        type=float,
        default=float(os.environ.get("PHONE_SCRIPT_LINE_DELAY", "0.001")),
    )
    parser.add_argument(
        "--suffix-delay",
        type=float,
        default=float(os.environ.get("PHONE_SCRIPT_SUFFIX_DELAY", "0.1")),
    )
    args = parser.parse_args()

    with open(args.script, "rb") as script_file:
        payload = base64.b64encode(script_file.read()).decode("ascii")
    payload_lines = [
        payload[offset : offset + 76] for offset in range(0, len(payload), 76)
    ]

    remote_b64 = "/tmp/bonito-phone-script.b64"
    remote_script = "/tmp/bonito-phone-script.sh"
    command = " ".join(["/bin/sh", remote_script, *(shlex.quote(value) for value in args.arguments)])
    prefix = f"""stty -echo
cat >{remote_b64} <<'EOF_BONITO_PHONE_SCRIPT'
""".encode("ascii", errors="strict")
    suffix = f"""EOF_BONITO_PHONE_SCRIPT
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
        sock.setblocking(True)
        sock.sendall(prefix)
        time.sleep(args.suffix_delay)
        for line in payload_lines:
            sock.sendall(line.encode("ascii") + b"\n")
            time.sleep(args.line_delay)
        time.sleep(args.suffix_delay)
        sock.sendall(suffix)
        sock.setblocking(False)
        output, remote_rc = receive_result(sock, args.timeout)

    text = output.decode("utf-8", errors="replace")
    marker_at = text.rfind(MARKER.decode("utf-8"))
    if marker_at >= 0:
        text = text[:marker_at]
    if args.output:
        temporary_output = f"{args.output}.tmp.{os.getpid()}"
        with open(temporary_output, "w", encoding="utf-8") as output_file:
            output_file.write(text.rstrip())
            output_file.write("\n")
            output_file.write(f"phone_script_transport_rc={remote_rc}\n")
        os.replace(temporary_output, args.output)
    if text.strip():
        print(text.rstrip())
    return remote_rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, TimeoutError) as error:
        print(f"phone script transport failed: {error}", file=sys.stderr)
        sys.exit(1)
