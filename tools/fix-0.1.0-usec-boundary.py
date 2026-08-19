#!/usr/bin/env python3
from pathlib import Path
import re
import sys


def replace_expected(text, label, pattern, replacement, expected):
    regex = re.compile(pattern, re.MULTILINE | re.DOTALL)
    matches = list(regex.finditer(text))
    count = len(matches)
    if count == 0:
        return text, 0
    if count != expected:
        raise RuntimeError(
            f"{label}: expected either 0 (already fixed) or {expected} unfixed occurrence(s), found {count}"
        )
    return regex.sub(replacement, text), count


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} /path/to/libinput-source", file=sys.stderr)
        return 2

    tree = Path(sys.argv[1])
    path = tree / "src" / "evdev.c"
    if not path.is_file():
        print(f"error: missing {path}", file=sys.stderr)
        return 1

    text = path.read_text()
    changed = 0

    fixes = [
        (
            "adaptive filter_dispatch timestamp",
            r"(filter_dispatch\(state->adaptive\.filter,\s*state->device,\s*[^,]+,\s*)time_us(\s*\))",
            r"\1usec_from_uint64_t(time_us)\2",
            1,
        ),
        (
            "adaptive filter_restart timestamp",
            r"filter_restart\(state->adaptive\.filter,\s*state->device,\s*time_us\s*\)",
            r"filter_restart(state->adaptive.filter, state->device, usec_from_uint64_t(time_us))",
            1,
        ),
        (
            "core restart timestamp",
            r"(tpsc_engine_restart\(\s*state->engine,\s*)time(\s*,\s*TPSC_RESTART_BYPASS_STARTUP\s*\))",
            r"\1usec_as_uint64_t(time)\2",
            1,
        ),
        (
            "core begin timestamps",
            r"tpsc_engine_begin\(state->engine,\s*time\s*\)",
            r"tpsc_engine_begin(state->engine, usec_as_uint64_t(time))",
            2,
        ),
        (
            "core feed timestamp",
            r"tpsc_engine_feed\(state->engine,\s*time,\s*input\s*\)",
            r"tpsc_engine_feed(state->engine, usec_as_uint64_t(time), input)",
            1,
        ),
        (
            "core tick timestamp",
            r"tpsc_engine_tick\(state->engine,\s*time,\s*&output\s*\)",
            r"tpsc_engine_tick(state->engine, usec_as_uint64_t(time), &output)",
            1,
        ),
        (
            "core end timestamp",
            r"tpsc_engine_end\(state->engine,\s*time\s*\)",
            r"tpsc_engine_end(state->engine, usec_as_uint64_t(time))",
            1,
        ),
        (
            "logical tick interval newtype",
            r"usec_add\(time,\s*tpsc_engine_tick_us\(state->engine\)\s*\)",
            r"usec_add(time, usec_from_uint64_t(tpsc_engine_tick_us(state->engine)))",
            2,
        ),
    ]

    for label, pattern, replacement, expected in fixes:
        text, n = replace_expected(text, label, pattern, replacement, expected)
        changed += n

    # The original compiler failure contains ten bad boundary crossings. If we
    # changed anything, require all ten to have been present so a drifted patch
    # cannot be silently half-fixed.
    if changed not in (0, 10):
        raise RuntimeError(f"expected 0 or 10 total timestamp-boundary fixes, applied {changed}")

    # Verify the corrected forms are present in the expected quantities.
    checks = [
        (r"usec_from_uint64_t\(time_us\)", 2, "uint64_t -> usec_t conversions"),
        (r"usec_as_uint64_t\(time\)", 6, "usec_t -> uint64_t timestamp conversions"),
        (r"usec_from_uint64_t\(tpsc_engine_tick_us\(state->engine\)\)", 2, "tick-period conversions"),
    ]
    for pattern, minimum, label in checks:
        count = len(re.findall(pattern, text))
        if count < minimum:
            raise RuntimeError(f"{label}: expected at least {minimum}, found {count}")

    if changed:
        path.write_text(text)
        print(f"applied {changed} libinput/core timestamp-boundary fixes")
    else:
        print("libinput/core timestamp boundary already fixed")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr)
        raise SystemExit(1)
