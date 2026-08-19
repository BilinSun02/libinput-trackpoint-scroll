#!/usr/bin/env python3
from pathlib import Path
import json
import re
import subprocess
import sys


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


def skip_quoted_or_comment(text, i):
    n = len(text)
    if text.startswith("//", i):
        j = text.find("\n", i + 2)
        return n if j < 0 else j + 1
    if text.startswith("/*", i):
        j = text.find("*/", i + 2)
        if j < 0:
            raise RuntimeError("unterminated block comment while parsing evdev.c")
        return j + 2
    if text[i] not in ('\"', "'"):
        return i

    quote = text[i]
    j = i + 1
    while j < n:
        if text[j] == "\\":
            j += 2
            continue
        if text[j] == quote:
            return j + 1
        j += 1
    raise RuntimeError("unterminated quoted literal while parsing evdev.c")


def find_matching_paren(text, open_pos):
    depth = 0
    i = open_pos
    while i < len(text):
        skipped = skip_quoted_or_comment(text, i)
        if skipped != i:
            i = skipped
            continue
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
            if depth < 0:
                break
        i += 1
    raise RuntimeError(f"unbalanced parentheses near byte {open_pos} in evdev.c")


def trim_span(text, start, end):
    while start < end and text[start].isspace():
        start += 1
    while end > start and text[end - 1].isspace():
        end -= 1
    return start, end


def split_arguments(text, start, end):
    spans = []
    arg_start = start
    paren = bracket = brace = 0
    i = start
    while i < end:
        skipped = skip_quoted_or_comment(text, i)
        if skipped != i:
            i = skipped
            continue
        c = text[i]
        if c == "(":
            paren += 1
        elif c == ")":
            paren -= 1
        elif c == "[":
            bracket += 1
        elif c == "]":
            bracket -= 1
        elif c == "{":
            brace += 1
        elif c == "}":
            brace -= 1
        elif c == "," and paren == 0 and bracket == 0 and brace == 0:
            spans.append(trim_span(text, arg_start, i))
            arg_start = i + 1
        i += 1

    if arg_start < end or text[start:end].strip():
        spans.append(trim_span(text, arg_start, end))
    return spans


def find_calls(text, function_name):
    pattern = re.compile(rf"\b{re.escape(function_name)}\s*\(")
    calls = []
    for match in pattern.finditer(text):
        open_pos = text.find("(", match.start(), match.end())
        close_pos = find_matching_paren(text, open_pos)
        args = split_arguments(text, open_pos + 1, close_pos)
        calls.append(args)
    return calls


def compact(expr):
    return re.sub(r"\s+", "", expr)


def arg_is(text, span, expected):
    return compact(text[span[0]:span[1]]) == compact(expected)


def fix_call_family(text, *, key, label, function_name, target_index,
                    unfixed_expr, fixed_expr, expected, predicate):
    sites = []
    for args in find_calls(text, function_name):
        if target_index >= len(args) or not predicate(text, args):
            continue
        target = args[target_index]
        if arg_is(text, target, unfixed_expr):
            sites.append((target[0], target[1], "unfixed"))
        elif arg_is(text, target, fixed_expr):
            sites.append((target[0], target[1], "fixed"))

    unfixed_count = sum(state == "unfixed" for _, _, state in sites)
    fixed_count = sum(state == "fixed" for _, _, state in sites)
    if len(sites) != expected:
        raise RuntimeError(
            f"{label}: expected {expected} total site(s) for {key}, found "
            f"{unfixed_count} unfixed + {fixed_count} fixed"
        )

    for start, end, state in sorted(sites, reverse=True):
        if state == "unfixed":
            text = text[:start] + fixed_expr + text[end:]

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

    families = [
        dict(
            key="adaptive_filter_dispatch_timestamp",
            label="adaptive filter_dispatch timestamp",
            function_name="filter_dispatch",
            target_index=3,
            unfixed_expr="time_us",
            fixed_expr="usec_from_uint64_t(time_us)",
            predicate=lambda t, a: len(a) == 4 and arg_is(t, a[0], "state->adaptive.filter"),
        ),
        dict(
            key="adaptive_filter_restart_timestamp",
            label="adaptive filter_restart timestamp",
            function_name="filter_restart",
            target_index=2,
            unfixed_expr="time_us",
            fixed_expr="usec_from_uint64_t(time_us)",
            predicate=lambda t, a: len(a) == 3 and arg_is(t, a[0], "state->adaptive.filter") and arg_is(t, a[1], "state->device"),
        ),
        dict(
            key="core_restart_timestamp",
            label="core restart timestamp",
            function_name="tpsc_engine_restart",
            target_index=1,
            unfixed_expr="time",
            fixed_expr="usec_as_uint64_t(time)",
            predicate=lambda t, a: len(a) == 3 and arg_is(t, a[0], "state->engine") and arg_is(t, a[2], "TPSC_RESTART_BYPASS_STARTUP"),
        ),
        dict(
            key="core_begin_timestamps",
            label="core begin timestamps",
            function_name="tpsc_engine_begin",
            target_index=1,
            unfixed_expr="time",
            fixed_expr="usec_as_uint64_t(time)",
            predicate=lambda t, a: len(a) == 2 and arg_is(t, a[0], "state->engine"),
        ),
        dict(
            key="core_feed_timestamp",
            label="core feed timestamp",
            function_name="tpsc_engine_feed",
            target_index=1,
            unfixed_expr="time",
            fixed_expr="usec_as_uint64_t(time)",
            predicate=lambda t, a: len(a) == 3 and arg_is(t, a[0], "state->engine") and arg_is(t, a[2], "input"),
        ),
        dict(
            key="core_tick_timestamp",
            label="core tick timestamp",
            function_name="tpsc_engine_tick",
            target_index=1,
            unfixed_expr="time",
            fixed_expr="usec_as_uint64_t(time)",
            predicate=lambda t, a: len(a) == 3 and arg_is(t, a[0], "state->engine") and arg_is(t, a[2], "&output"),
        ),
        dict(
            key="core_end_timestamp",
            label="core end timestamp",
            function_name="tpsc_engine_end",
            target_index=1,
            unfixed_expr="time",
            fixed_expr="usec_as_uint64_t(time)",
            predicate=lambda t, a: len(a) == 2 and arg_is(t, a[0], "state->engine"),
        ),
        dict(
            key="logical_tick_interval_newtype",
            label="logical tick interval newtype",
            function_name="usec_add",
            target_index=1,
            unfixed_expr="tpsc_engine_tick_us(state->engine)",
            fixed_expr="usec_from_uint64_t(tpsc_engine_tick_us(state->engine))",
            predicate=lambda t, a: len(a) == 2 and arg_is(t, a[0], "time"),
        ),
    ]

    keys = {item["key"] for item in families}
    manifest_keys = set(expectations)
    if keys != manifest_keys:
        missing = sorted(keys - manifest_keys)
        extra = sorted(manifest_keys - keys)
        raise RuntimeError(
            f"expectations/fixer family mismatch; missing={missing}, extra={extra}"
        )

    expected_total = 0
    for family in families:
        expected = expectations[family["key"]]
        if not isinstance(expected, int) or expected < 0:
            raise RuntimeError(
                f"invalid expected count for {family['key']}: {expected!r}"
            )
        expected_total += expected
        text, n = fix_call_family(text, expected=expected, **family)
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
