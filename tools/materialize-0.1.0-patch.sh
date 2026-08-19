#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
src="$repo_dir/patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.gz"
out=${1:-"$repo_dir/patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch"}
expected=8a2149667755545fa8ff7b378de839bfb90e0728ed01cddfcabf03e3fa17c016

gzip -dc "$src" > "$out"
actual=$(sha256sum "$out" | awk '{print $1}')
if [ "$actual" != "$expected" ]; then
    printf '%s\n' "checksum mismatch: expected $expected, got $actual" >&2
    rm -f "$out"
    exit 1
fi

printf '%s\n' "wrote $out"
