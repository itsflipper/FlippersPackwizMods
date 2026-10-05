#!/usr/bin/env python3
"""Copy binary stdin to stdout while showing a conservative transfer estimate."""

from __future__ import annotations

import sys
import time


def human_size(value: float) -> str:
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{value:.1f} TiB"


def main() -> int:
    expected = int(sys.argv[1])
    label = sys.argv[2] if len(sys.argv) > 2 else "Download"
    copied = 0
    started = last_report = time.monotonic()
    source = sys.stdin.buffer
    destination = sys.stdout.buffer

    while chunk := source.read(1024 * 1024):
        destination.write(chunk)
        copied += len(chunk)
        now = time.monotonic()
        if now - last_report >= 0.5:
            elapsed = max(now - started, 0.001)
            rate = copied / elapsed
            remaining = max(expected - copied, 0)
            eta = remaining / rate if rate else 0
            print(
                f"\r{label}: {human_size(copied)} / etwa {human_size(expected)} "
                f"({human_size(rate)}/s, noch etwa {eta:.0f}s)",
                end="",
                file=sys.stderr,
                flush=True,
            )
            last_report = now

    destination.flush()
    print(
        f"\r{label} abgeschlossen: {human_size(copied)} "
        f"(Archivgröße: {human_size(expected)}){' ' * 24}",
        file=sys.stderr,
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
