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
for option in json.load(sys.stdin):
    if option.get("name") == "prefix":
        print(option.get("value", ""))
        break
')
if [ -z "$prefix" ]; then
    echo "error: cannot determine Meson install prefix" >&2
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

paths_tmp=$(mktemp)
cache_tmp=$(mktemp)
trap 'rm -f "$paths_tmp" "$cache_tmp"' EXIT HUP INT TERM

# Inspect every Meson destination before installing. A custom build must not
# silently overwrite files owned by dpkg/apt; package-managed replacement
# requires an explicit packaging/diversion strategy outside this helper.
meson introspect "$builddir" --installed | python3 -c '
import json, sys
for value in json.load(sys.stdin).values():
    if isinstance(value, str):
        print(value)
' | sort -u > "$paths_tmp"

if command -v dpkg-query >/dev/null 2>&1; then
    owned=0
    while IFS= read -r dest; do
        [ -n "$dest" ] || continue
        owner=$(dpkg-query -S "$dest" 2>/dev/null | head -n 1 || true)
        if [ -z "$owner" ]; then
            case "$dest" in
                /usr/lib/*) alt=${dest#/usr}; owner=$(dpkg-query -S "$alt" 2>/dev/null | head -n 1 || true) ;;
                /usr/lib64/*) alt=${dest#/usr}; owner=$(dpkg-query -S "$alt" 2>/dev/null | head -n 1 || true) ;;
            esac
        fi
        if [ -n "$owner" ]; then
            if [ "$owned" -eq 0 ]; then
                echo "error: this install would overwrite dpkg-owned paths:" >&2
            fi
            echo "       $owner" >&2
            owned=1
        fi
    done < "$paths_tmp"

    if [ "$owned" -ne 0 ]; then
        echo "       refusing to modify package-managed files." >&2
        echo "       Use a non-package prefix (the managed default is /usr/local)" >&2
        echo "       or use an explicit Debian packaging/diversion workflow." >&2
        exit 1
    fi
fi

echo "build prefix:  $prefix"
echo "build library: $buildlib"
echo "build SONAME:  $soname"
echo "build ID:      $build_id"

before=$(ldconfig -p 2>/dev/null | awk -v soname="$soname" '$1 == soname {print $NF; exit}')
if [ -n "$before" ]; then
    echo "before install cache selects: $before"
fi

echo "installing libinput from: $builddir"
# Do not uninstall another custom libinput first. Installing into this build's
# own prefix is non-destructive to custom copies elsewhere; after ldconfig the
# Build-ID check below determines which copy is first in the loader cache.
ninja -C "$builddir" install

echo "refreshing dynamic-loader cache"
ldconfig

ldconfig -p | awk '$1 ~ /^libinput\.so(\.|$)/ {print $NF}' | sort -u > "$cache_tmp"
if [ ! -s "$cache_tmp" ]; then
    echo "error: ldconfig reports no libinput shared library after install" >&2
    exit 1
fi

echo "cache-visible libinput libraries:"
bad=0
while IFS= read -r path; do
    if [ ! -e "$path" ]; then
        echo "  BROKEN: $path" >&2
        bad=1
        continue
    fi
    resolved=$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")
    echo "  $path -> $resolved"
done < "$cache_tmp"
if [ "$bad" -ne 0 ]; then
    echo "error: at least one cache-visible libinput path is missing" >&2
    exit 1
fi

cache_selected=$(ldconfig -p | awk -v soname="$soname" '$1 == soname {print $NF; exit}')
if [ -z "$cache_selected" ]; then
    echo "error: dynamic-loader cache does not resolve required SONAME $soname" >&2
    exit 1
fi
if [ ! -e "$cache_selected" ]; then
    echo "error: cache-selected $soname path is missing: $cache_selected" >&2
    exit 1
fi
cache_selected=$(readlink -f "$cache_selected" 2>/dev/null || printf '%s' "$cache_selected")
cache_id=$(readelf -n "$cache_selected" 2>/dev/null | awk '/Build ID:/ {print $3; exit}')
if [ -z "$cache_id" ]; then
    echo "error: cannot read Build ID from cache-selected library: $cache_selected" >&2
    exit 1
fi

echo "cache selects: $cache_selected"
echo "cache ID:      $cache_id"

if [ "$cache_id" != "$build_id" ]; then
    echo "error: another libinput installation is first in the ldconfig cache" >&2
    echo "       cache path: $cache_selected" >&2
    echo "       build ID:   $build_id" >&2
    echo "       cache ID:   $cache_id" >&2
    echo "       Do not uninstall it blindly; identify that installation first." >&2
    echo "       DO NOT restart the graphical session or reboot." >&2
    exit 1
fi

if command -v libinput >/dev/null 2>&1; then
    echo "libinput CLI: $(command -v libinput)"
    libinput --version || true
fi

echo "install verification passed: cache-selected $soname matches the build ID"
echo "safe to restart the graphical session or reboot"
echo "after restart, verify actual process mappings with:"
echo "  sh '$script_dir/verify-runtime-libinput.sh' '$builddir'"
