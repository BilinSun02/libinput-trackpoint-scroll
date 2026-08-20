#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
builddir=${1:-"$repo_root/.work/libinput/builddir"}

for cmd in readelf ldconfig find awk cmp readlink python3; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "error: $cmd not found" >&2
        exit 1
    }
done

buildlib=$(find "$builddir" -maxdepth 1 -type f -name 'libinput.so.*.*.*' -print | head -n 1)
if [ -z "$buildlib" ] || [ ! -f "$buildlib" ]; then
    echo "error: cannot find versioned libinput shared library in $builddir" >&2
    exit 1
fi

build_id=$(readelf -n "$buildlib" 2>/dev/null | awk '/Build ID:/ {print $3; exit}')
soname=$(readelf -d "$buildlib" 2>/dev/null | sed -n 's/.*Library soname: \[\(.*\)\]/\1/p' | head -n 1)
if [ -z "$build_id" ] || [ -z "$soname" ]; then
    echo "error: cannot read Build ID/SONAME from $buildlib" >&2
    exit 1
fi

echo "build library: $buildlib"
echo "build SONAME:  $soname"
echo "expected ID:   $build_id"

cache_path=$(ldconfig -p 2>/dev/null | awk -v soname="$soname" '$1 == soname {print $NF; exit}')
if [ -z "$cache_path" ]; then
    echo "error: ldconfig cache has no entry for $soname" >&2
    exit 1
fi
cache_path=$(readlink -f "$cache_path" 2>/dev/null || printf '%s' "$cache_path")
cache_id=$(readelf -n "$cache_path" 2>/dev/null | awk '/Build ID:/ {print $3; exit}')

echo "cache path:    $cache_path"
echo "cache ID:      ${cache_id:-unknown}"

if [ "$cache_id" != "$build_id" ]; then
    echo "error: cache-selected $soname does not match the build artifact" >&2
    exit 1
fi

if cmp -s "$buildlib" "$cache_path"; then
    echo "cache file:    exact byte-for-byte match"
else
    echo "cache file:    Build ID matches (file bytes differ)"
fi

echo "runtime mappings:"
found=0
mismatch=0
unverified=0
for maps in /proc/[0-9]*/maps; do
    [ -r "$maps" ] || continue

    line=$(awk -v soname="$soname" 'index($0, soname) {print; exit}' "$maps" 2>/dev/null || true)
    [ -n "$line" ] || continue

    pid=${maps#/proc/}
    pid=${pid%/maps}
    map_dev=$(printf '%s\n' "$line" | awk '{print $4}')
    map_inode=$(printf '%s\n' "$line" | awk '{print $5}')
    mapped=$(printf '%s\n' "$line" | awk '{print $6}')
    comm=$(cat "/proc/$pid/comm" 2>/dev/null || printf '?')
    found=1

    # A maps pathname alone is insufficient proof: another install could have
    # replaced that pathname after this process mapped the old inode. Compare
    # the maps device/inode with the file currently at the path before reading
    # its Build ID. If they differ, fail closed rather than misidentifying the
    # mapped object.
    if [ ! -e "$mapped" ]; then
        printf '  %-10s pid=%-7s %-24s %s\n' "UNVERIFIED" "$pid" "$comm" "$mapped"
        unverified=1
        continue
    fi

    same_inode=$(python3 - "$mapped" "$map_dev" "$map_inode" 2>/dev/null <<'PY' || true
import os
import sys

path, map_dev, map_inode = sys.argv[1:]
st = os.stat(path)
major_hex, minor_hex = map_dev.split(":", 1)
map_major = int(major_hex, 16)
map_minor = int(minor_hex, 16)
match = (
    os.major(st.st_dev) == map_major
    and os.minor(st.st_dev) == map_minor
    and st.st_ino == int(map_inode)
)
print("yes" if match else "no")
PY
)

    if [ "$same_inode" != yes ]; then
        printf '  %-10s pid=%-7s %-24s mapped inode cannot be tied to current path: %s\n' \
            "UNVERIFIED" "$pid" "$comm" "$mapped"
        unverified=1
        continue
    fi

    resolved=$(readlink -f "$mapped" 2>/dev/null || printf '%s' "$mapped")
    id=$(readelf -n "$resolved" 2>/dev/null | awk '/Build ID:/ {print $3; exit}')

    if [ "$id" = "$build_id" ]; then
        status=MATCH
    else
        status=MISMATCH
        mismatch=1
    fi

    printf '  %-10s pid=%-7s %-24s id=%s  %s\n' "$status" "$pid" "$comm" "${id:-unknown}" "$resolved"
done

if [ "$found" -eq 0 ]; then
    echo "warning: no readable running process currently maps $soname" >&2
    echo "         cache verification passed, but runtime mapping was not observed." >&2
    exit 2
fi

if [ "$mismatch" -ne 0 ]; then
    echo "error: at least one readable running process maps a different $soname" >&2
    exit 1
fi

if [ "$unverified" -ne 0 ]; then
    echo "error: at least one runtime mapping could not be tied safely to the file currently at its path" >&2
    echo "       restart that process or inspect its /proc/<pid>/map_files entry with sufficient privileges." >&2
    exit 1
fi

echo "runtime verification passed: observed process mappings match the build ID"
