#!/usr/bin/env python3
"""Publish one architecture report through an isolated temporary HTTP site."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen


def process_matches(pid: int, site_dir: Path) -> bool:
    """Only identify a prior server started for this exact report site."""
    cmdline_path = Path(f"/proc/{pid}/cmdline")
    try:
        cmdline = cmdline_path.read_bytes().replace(b"\0", b" ").decode(
            errors="replace"
        )
    except OSError:
        return False
    return "http.server" in cmdline and str(site_dir) in cmdline


def stop_prior_server(pid_file: Path, site_dir: Path) -> None:
    try:
        pid = int(pid_file.read_text().strip())
    except (OSError, ValueError):
        return

    if not process_matches(pid, site_dir):
        return

    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return

    for _ in range(20):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)


def verify(port: int, process: subprocess.Popen[bytes]) -> bool:
    for _ in range(20):
        if process.poll() is not None:
            return False
        try:
            with urlopen(f"http://127.0.0.1:{port}/", timeout=1) as response:
                return response.status == 200 and process.poll() is None
        except OSError:
            time.sleep(0.1)
    return False


def reachable_host() -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        host = sock.getsockname()[0]
        if host and not host.startswith("127."):
            return host
    except OSError:
        pass
    finally:
        sock.close()

    try:
        host = socket.gethostbyname(socket.gethostname())
        if host:
            return host
    except OSError:
        pass
    return "127.0.0.1"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--attempts", type=int, default=30)
    args = parser.parse_args()

    report = args.report.expanduser().resolve()
    if not report.is_file():
        parser.error(f"report does not exist: {report}")

    temp_dir = Path(tempfile.gettempdir())
    site_dir = temp_dir / "architecture-review-site"
    state_dir = temp_dir / "architecture-review-server-state"
    site_dir.mkdir(parents=True, exist_ok=True)
    state_dir.mkdir(parents=True, exist_ok=True)

    pid_file = state_dir / "server.pid"
    port_file = state_dir / "server.port"
    log_file = state_dir / "server.log"
    source_file = state_dir / "report.path"

    stop_prior_server(pid_file, site_dir)
    shutil.copyfile(report, site_dir / "index.html")
    source_file.write_text(f"{report}\n")

    selected_port: int | None = None
    server: subprocess.Popen[bytes] | None = None

    with log_file.open("ab", buffering=0) as log:
        for port in range(args.port, args.port + args.attempts):
            candidate = subprocess.Popen(
                [
                    sys.executable,
                    "-m",
                    "http.server",
                    str(port),
                    "--bind",
                    "0.0.0.0",
                    "--directory",
                    str(site_dir),
                ],
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=log,
                start_new_session=True,
            )
            if verify(port, candidate):
                selected_port = port
                server = candidate
                break
            candidate.terminate()
            try:
                candidate.wait(timeout=2)
            except subprocess.TimeoutExpired:
                candidate.kill()
                candidate.wait(timeout=2)

    if selected_port is None or server is None:
        print(f"Failed to serve report; inspect {log_file}", file=sys.stderr)
        return 1

    pid_file.write_text(f"{server.pid}\n")
    port_file.write_text(f"{selected_port}\n")
    host = reachable_host()

    print(f"REPORT_PATH={report}")
    print(f"REPORT_URL=http://{host}:{selected_port}/")
    print(f"REPORT_LOCAL_URL=http://127.0.0.1:{selected_port}/")
    print(f"REPORT_PID={server.pid}")
    print(f"REPORT_LOG={log_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
