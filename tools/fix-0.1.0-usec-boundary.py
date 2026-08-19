#!/usr/bin/env python3
from pathlib import Path
import json
import re
import subprocess
import sys


FLAGS = re.MULTILINE | re.DOTALL


def load_upstream(repo_root):
    values = {}
    for raw in (repo_root / "UPSTREAM").read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep:
            raise RuntimeError(f"invalid UPSTREAM line: {raw}")
        values[key] = value

    commit = values.get("LIBINPUT_COMMIT")
    if not commit:
        raise RuntimeError("UPSTREAM does not define LIBINPUT_COMMIT")
    return commit


def load_expectations(repo_root, commit):
    path = repo_root / "compat" / "libinput" / commit / "usec-boundary.json"
    if not path.is_file():
        raise RuntimeError(
            f"no usec-boundary expectations for pinned libinput commit {commit}: {path}"
        )

    data = json.loads(path.read_text())
    if data.get("schema") != 1:
        raise RuntimeError(f"unsupported expectations schema in {path}")
    if data.get("libinput_commit") != commit:
        raise RuntimeError(
            f"expectations manifest commit {data.get('libinput_commit')} does not match UPSTREAM {commit}"
        )

    families = data.get("families")
    if not isinstance(families, dict):
        raise RuntimeError(f"missing families table in {path}")
    return families, path


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

    script = Path(__file__).resolve()
    repo_root = script.parent.parent
    pinned_commit = load_upstream(repo_root)
    expectations, expectations_path = load_expectations(repo_root, pinned_commit)

    tree = Path(sys.argv[1]).resolve()
    path = tree / "src" / "evdev.c"
    if not path.is_file():
        print(f"error: missing {path}", file=sys.stderr)
        return 1

    try:
        tree_commit = subprocess.run(
            ["git", "-C", str(tree), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"cannot determine libinput checkout commit: {e}") from e

    if tree_commit != pinned_commit:
        raise RuntimeError(
            f"libinput checkout is at {tree_commit}, but UPSTREAM pins {pinned_commit}"
        )

    text = path.read_text()
    changed = 0

    # Regexes describe the adapter forms; expected multiplicities do not live
    # here. They are commit-specific data in compat/libinput/<commit>/ so a
    # libinput re-pin cannot silently inherit assumptions from another source
    # revision.
    fixes = [
        (
            "adaptive_filter_dispatch_timestamp",
            "adaptive filter_dispatch timestamp",
            r"(filter_dispatch\(state->adaptive\.filter,\s*state->device,\s*[^,]+,\s*)time_us(\s*\))",
            r"filter_dispatch\(state->adaptive\.filter,\s*state->device,\s*[^,]+,\s*usec_from_uint64_t\(time_us\)\s*\)",
            r"\1usec_from_uint64_t(time_us)\2",
        ),
        (
            "adaptive_filter_restart_timestamp",
            "adaptive filter_restart timestamp",
            r"filter_restart\(state->adaptive\.filter,\s*state->device,\s*time_us\s*\)",
            r"filter_restart\(state->adaptive\.filter,\s*state->device,\s*usec_from_uint64_t\(time_us\)\s*\)",
            r"filter_restart(state->adaptive.filter, state->device, usec_from_uint64_t(time_us))",
        ),
        (
            "core_restart_timestamp",
            "core restart timestamp",
            r"(tpsc_engine_restart\(\s*state->engine,\s*)time(\s*,\s*TPSC_RESTART_BYPASS_STARTUP\s*\))",
            r"tpsc_engine_restart\(\s*state->engine,\s*usec_as_uint64_t\(time\)\s*,\s*TPSC_RESTART_BYPASS_STARTUP\s*\)",
            r"\1usec_as_uint64_t(time)\2",
        ),
        (
            "core_begin_timestamps",
            "core begin timestamps",
            r"tpsc_engine_begin\(state->engine,\s*time\s*\)",
            r"tpsc_engine_begin\(state->engine,\s*usec_as_uint64_t\(time\)\s*\)",
            r"tpsc_engine_begin(state->engine, usec_as_uint64_t(time))",
        ),
        (
            "core_feed_timestamp",
            "core feed timestamp",
            r"tpsc_engine_feed\(state->engine,\s*time,\s*input\s*\)",
            r"tpsc_engine_feed\(state->engine,\s*usec_as_uint64_t\(time\),\s*input\s*\)",
            r"tpsc_engine_feed(state->engine, usec_as_uint64_t(time), input)",
        ),
        (
            "core_tick_timestamp",
            "core tick timestamp",
            r"tpsc_engine_tick\(state->engine,\s*time,\s*&output\s*\)",
            r"tpsc_engine_tick\(state->engine,\s*usec_as_uint64_t\(time\),\s*&output\s*\)",
            r"tpsc_engine_tick(state->engine, usec_as_uint64_t(time), &output)",
        ),
        (
            "core_end_timestamp",
            "core end timestamp",
            r"tpsc_engine_end\(state->engine,\s*time\s*\)",
            r"tpsc_engine_end\(state->engine,\s*usec_as_uint64_t\(time\)\s*\)",
            r"tpsc_engine_end(state->engine, usec_as_uint64_t(time))",
        ),
        (
            "logical_tick_interval_newtype",
            "logical tick interval newtype",
            r"usec_add\(time,\s*tpsc_engine_tick_us\(state->engine\)\s*\)",
            r"usec_add\(time,\s*usec_from_uint64_t\(tpsc_engine_tick_us\(state->engine\)\)\s*\)",
            r"usec_add(time, usec_from_uint64_t(tpsc_engine_tick_us(state->engine)))",
        ),
    ]

    keys = {item[0] for item in fixes}
    manifest_keys = set(expectations)
    if keys != manifest_keys:
        missing = sorted(keys - manifest_keys)
        extra = sorted(manifest_keys - keys)
        raise RuntimeError(
            f"expectations/fixer family mismatch; missing={missing}, extra={extra}"
        )

    expected_total = 0
    for key, label, unfixed, fixed, replacement in fixes:
        expected = expectations[key]
        if not isinstance(expected, int) or expected < 0:
            raise RuntimeError(f"invalid expected count for {key}: {expected!r}")
        expected_total += expected
        text, n = fix_family(
            text, label, unfixed, fixed, replacement, expected
        )
        changed += n

    if changed:
        path.write_text(text)
        print(
            f"applied {changed} remaining libinput/core timestamp-boundary fix(es) "
            f"of {expected_total} sites pinned for {pinned_commit}"
        )
    else:
        print(
            f"libinput/core timestamp boundary already fixed "
            f"({expected_total} sites pinned for {pinned_commit})"
        )

    print(f"validated expectations: {expectations_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, json.JSONDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        raise SystemExit(1)
