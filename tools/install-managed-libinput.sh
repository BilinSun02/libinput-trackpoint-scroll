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

command -v ninja >/dev/null 2>&1 || {
    echo "error: ninja not found" >&2
    exit 1
}
command -v ldconfig >/dev/null 2>&1 || {
    echo "error: ldconfig not found" >&2
    exit 1
}

echo "installing replacement libinput from: $builddir"
# Deliberately do not uninstall the previous /usr/local build first. Installing
# a replacement with the same prefix/SONAME avoids creating an unnecessary
# interval in which the graphical stack has no custom libinput installed.
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

if command -v libinput >/dev/null 2>&1; then
    echo "libinput CLI: $(command -v libinput)"
    libinput --version || true
    resolved_cli=$(ldd "$(command -v libinput)" 2>/dev/null | awk '/libinput\.so/ {print $3; exit}')
    if [ -n "$resolved_cli" ]; then
        if [ ! -e "$resolved_cli" ]; then
            echo "error: libinput CLI resolves libinput to missing path: $resolved_cli" >&2
            exit 1
        fi
        echo "libinput CLI resolves shared library to: $resolved_cli"
    fi
fi

echo "install verification passed"
echo "safe to restart the graphical session or reboot"
