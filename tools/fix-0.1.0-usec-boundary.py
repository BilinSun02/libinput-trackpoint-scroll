#!/usr/bin/env python3
from pathlib import Path
import re
import sys


FLAGS = re.MULTILINE | re.DOTALL


def fix_family(text, label, unfixed_pattern, fixed_pattern, replacement, expected):
    unfixed = re.compile(unfixed_pattern, FLAGS)
    fixed = re.compile(fixed_pattern, FLAGS)

    unfixed_count = len(list(unfixed.finditer(text)))
    fixed_count = len(list(fixed.finditer(text)))
    total = unfixed_count + fixed_count

    if total != expected:
        raise RuntimeError(
            f"{label}: expected {expected} total site(s), found "
            f"{unfixed_count} unfixed + {fixed_count} fixed"
        )

    if unfixed_count:
        text = unfixed.sub(replacement, text)

    return text, unfixed_count


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

    # Each family describes one or more exact adapter boundary crossings.
    # Validate both forms: a site may already be fixed, but a regex miss must
    # never be mistaken for an already-fixed site.
    fixes = [
        (
            "adaptive filter_dispatch timestamp",
            r"(filter_dispatch\(state->adaptive\.filter,\s*state->device,\s*[^,]+,\s*)time_us(\s*\))",
            r"filter_dispatch\(state->adaptive\.filter,\s*state->device,\s*[^,]+,\s*usec_from_uint64_t\(time_us\)\s*\)",
            r"\1usec_from_uint64_t(time_us)\2",
            1,
        ),
        (
            "adaptive filter_restart timestamp",
            r"filter_restart\(state->adaptive\.filter,\s*state->device,\s*time_us\s*\)",
            r"filter_restart\(state->adaptive\.filter,\s*state->device,\s*usec_from_uint64_t\(time_us\)\s*\)",
            r"filter_restart(state->adaptive.filter, state->device, usec_from_uint64_t(time_us))",
            1,
        ),
        (
            "core restart timestamp",
            r"(tpsc_engine_restart\(\s*state->engine,\s*)time(\s*,\s*TPSC_RESTART_BYPASS_STARTUP\s*\))",
            r"tpsc_engine_restart\(\s*state->engine,\s*usec_as_uint64_t\(time\)\s*,\s*TPSC_RESTART_BYPASS_STARTUP\s*\)",
            r"\1usec_as_uint64_t(time)\2",
            1,
        ),
        (
            "core begin timestamps",
            r"tpsc_engine_begin\(state->engine,\s*time\s*\)",
            r"tpsc_engine_begin\(state->engine,\s*usec_as_uint64_t\(time\)\s*\)",
            r"tpsc_engine_begin(state->engine, usec_as_uint64_t(time))",
            2,
        ),
        (
            "core feed timestamp",
            r"tpsc_engine_feed\(state->engine,\s*time,\s*input\s*\)",
            r"tpsc_engine_feed\(state->engine,\s*usec_as_uint64_t\(time\),\s*input\s*\)",
            r"tpsc_engine_feed(state->engine, usec_as_uint64_t(time), input)",
            1,
        ),
        (
            "core tick timestamp",
            r"tpsc_engine_tick\(state->engine,\s*time,\s*&output\s*\)",
            r"tpsc_engine_tick\(state->engine,\s*usec_as_uint64_t\(time\),\s*&output\s*\)",
            r"tpsc_engine_tick(state->engine, usec_as_uint64_t(time), &output)",
            1,
        ),
        (
            "core end timestamp",
            r"tpsc_engine_end\(state->engine,\s*time\s*\)",
            r"tpsc_engine_end\(state->engine,\s*usec_as_uint64_t\(time\)\s*\)",
            r"tpsc_engine_end(state->engine, usec_as_uint64_t(time))",
            1,
        ),
        (
            "logical tick interval newtype",
            r"usec_add\(time,\s*tpsc_engine_tick_us\(state->engine\)\s*\)",
            r"usec_add\(time,\s*usec_from_uint64_t\(tpsc_engine_tick_us\(state->engine\)\)\s*\)",
            r"usec_add(time, usec_from_uint64_t(tpsc_engine_tick_us(state->engine)))",
            2,
        ),
    ]

    for label, unfixed, fixed, replacement, expected in fixes:
        text, n = fix_family(
            text, label, unfixed, fixed, replacement, expected
        )
        changed += n

    # All ten boundary crossings must now be in their corrected form. The
    # per-family checks above prove that none disappeared because of source
    # drift or a regex miss, while allowing partially-fixed trees to resume.
    expected_total = sum(item[-1] for item in fixes)
    if expected_total != 10:
        raise RuntimeError(
            f"internal error: timestamp-boundary table describes {expected_total} sites, expected 10"
        )

    if changed:
        path.write_text(text)
        print(f"applied {changed} remaining libinput/core timestamp-boundary fix(es)")
    else:
        print("libinput/core timestamp boundary already fixed")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr)
        raise SystemExit(1)
