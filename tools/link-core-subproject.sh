#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /path/to/libinput-source" >&2
    exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
core="$repo_root/core"
target=$(CDPATH= cd -- "$1" && pwd)
subprojects="$target/subprojects"
dest="$subprojects/trackpoint-scroll-core"

if [ ! -f "$target/meson.build" ] || [ ! -d "$target/src" ]; then
    echo "error: target does not look like a libinput source tree: $target" >&2
    exit 1
fi

if [ ! -f "$core/meson.build" ] || [ ! -f "$core/include/trackpoint_scroll/engine.h" ]; then
    echo "error: core submodule is missing; run git submodule update --init --recursive" >&2
    exit 1
fi

mkdir -p "$subprojects"

if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ -L "$dest" ] && [ "$(readlink -f -- "$dest")" = "$(readlink -f -- "$core")" ]; then
        echo "core subproject already linked: $dest"
        exit 0
    fi

    echo "error: refusing to replace existing path: $dest" >&2
    exit 1
fi

relative_core=$(realpath --relative-to="$subprojects" "$core")
ln -s -- "$relative_core" "$dest"
echo "linked $dest -> $relative_core"
