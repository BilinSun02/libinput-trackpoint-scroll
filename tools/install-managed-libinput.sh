#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
builddir=${1:-"$repo_root/.work/libinput/builddir"}

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run this installer as root, e.g.:" >&2
    echo "       sudo sh ./tools/install-managed-libinput.sh" >&2
    exit 1
fi

if [ ! -f "$builddir/build.ninja" ]; then
    echo "error: $builddir is not a configured Ninja build directory" >&2
    exit 1
fi

for cmd in ninja ldconfig readelf meson python3; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "error: $cmd not found" >&2
        exit 1
    }
done

prefix=$(meson introspect "$builddir" --buildoptions | python3 -c '
import json, sys
options = json.load(sys.stdin)
for option in options:
    if option.get("name") == "prefix":
        print(option.get("value", ""))
        break
')
if [ "$prefix" != "/usr" ]; then
    echo "error: build directory prefix is '$prefix', expected '/usr'" >&2
    echo "       this project replaces the loader-selected system libinput; a" >&2
    echo "       /usr/local build may install successfully without being selected." >&2
    echo "       Reconfigure before installing:" >&2
    echo "       meson setup --reconfigure '$builddir' '$repo_root/.work/libinput' --prefix=/usr" >&2
    exit 1
fi

buildlib=$(find "$builddir" -maxdepth 1 -type f -name 'libinput.so.*.*.*' -print | head -n 1)
if [ -z "$buildlib" ] || [ ! -f "$buildlib" ]; then
    echo "error: cannot find versioned libinput shared library in $builddir" >&2
    exit 1
fi

build_id=$(readelf -n "$buildlib" 2>/dev/null | awk '/Build ID:/ {print $3; exit}')
soname=$(readelf -d "$buildlib" 2>/dev/null | sed -n 's/.*Library soname: \[\(.*\)\]/\1/p' | head -n 1)
if [ -z "$build_id" ]; then
    echo "error: cannot read Build ID from $buildlib" >&2
    exit 1
fi
if [ -z "$soname" ]; then
    echo "error: cannot read SONAME from $buildlib" >&2
    exit 1
fi

echo "build prefix:  $prefix"
echo "build library: $buildlib"
echo "build SONAME:  $soname"
echo "build ID:      $build_id"

echo "installing replacement libinput from: $builddir"
# Deliberately do not uninstall the loader-selected system build first.
# Installing the replacement directly avoids a period in which GNOME/Xorg
# cannot resolve libinput.so.10 at all.
ninja -C "$builddir" install

echo "refreshing dynamic-loader cache"
ldconfig

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM
ldconfig -p | awk '$1 ~ /^libinput\.so(\.|$)/ {print $NF}' | sort -u > "$tmp"

if [ ! -s "$tmp" ]; then
    echo "error: ldconfig reports no libinput shared library after install" >&2
    exit 1
fi

bad=0
echo "loader-visible libinput libraries:"
while IFS= read -r path; do
    if [ ! -e "$path" ]; then
        echo "  BROKEN: $path" >&2
        bad=1
        continue
    fi
    resolved=$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")
    echo "  $path -> $resolved"
done < "$tmp"

if [ "$bad" -ne 0 ]; then
    echo "error: at least one loader-visible libinput path is missing" >&2
    exit 1
fi

selected=$(ldconfig -p | awk -v soname="$soname" '$1 == soname {print $NF; exit}')
if [ -z "$selected" ]; then
    echo "error: dynamic-loader cache does not resolve required SONAME $soname" >&2
    exit 1
fi
if [ ! -e "$selected" ]; then
    echo "error: loader-selected $soname path is missing: $selected" >&2
    exit 1
fi
selected=$(readlink -f "$selected" 2>/dev/null || printf '%s' "$selected")
selected_id=$(readelf -n "$selected" 2>/dev/null | awk '/Build ID:/ {print $3; exit}')
if [ -z "$selected_id" ]; then
    echo "error: cannot read Build ID from loader-selected library: $selected" >&2
    exit 1
fi

echo "loader selects: $selected"
echo "selected ID:    $selected_id"

if [ "$selected_id" != "$build_id" ]; then
    echo "error: loader-selected $soname does not match the library just built" >&2
    echo "       build ID:    $build_id" >&2
    echo "       selected ID: $selected_id" >&2
    echo "       DO NOT restart the graphical session or reboot." >&2
    exit 1
fi

if command -v libinput >/dev/null 2>&1; then
    echo "libinput CLI: $(command -v libinput)"
    libinput --version || true
fi

echo "install verification passed: loader-selected $soname matches the build ID"
echo "safe to restart the graphical session or reboot"
