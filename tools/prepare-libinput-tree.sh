#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

# Single source of truth for the current upstream pin.
# LIBINPUT_UPSTREAM_URL remains an optional per-invocation mirror override.
. "$repo_root/UPSTREAM"
UPSTREAM_COMMIT=$LIBINPUT_COMMIT
UPSTREAM_URL=${LIBINPUT_UPSTREAM_URL:-$LIBINPUT_REPO}

work_root="$repo_root/.work"
tree="$work_root/libinput"
patch="$work_root/libinput-trackpoint-scroll-v0.1.0.patch"
meson_fix="$repo_root/patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0-meson-fix.patch"

mkdir -p "$work_root"

# Ensure the exact shared revision recorded by this repository is available.
git -C "$repo_root" submodule update --init --recursive

if [ ! -d "$tree/.git" ]; then
    if [ -e "$tree" ]; then
        echo "error: $tree exists but is not a git checkout" >&2
        exit 1
    fi

    echo "cloning libinput $LIBINPUT_VERSION into $tree"
    git clone --filter=blob:none "$UPSTREAM_URL" "$tree"
fi

sh "$script_dir/materialize-0.1.0-patch.sh" "$patch" >/dev/null

if [ -n "$(git -C "$tree" status --porcelain)" ]; then
    # Recognize either the original 0.1.0 candidate or that candidate plus
    # the Meson syntax correction. Arbitrary local edits are still rejected.
    if git -C "$tree" apply --reverse --check "$meson_fix" >/dev/null 2>&1; then
        echo "existing corrected 0.1.0 tree detected"
    elif git -C "$tree" apply --reverse --check "$patch" >/dev/null 2>&1; then
        echo "existing pre-fix 0.1.0 tree detected"
    else
        echo "error: managed libinput tree contains local changes not recognized as the 0.1.0 patch set" >&2
        echo "       remove $tree to recreate it, or preserve your edits elsewhere first" >&2
        exit 1
    fi
else
    if ! git -C "$tree" cat-file -e "$UPSTREAM_COMMIT^{commit}" 2>/dev/null; then
        echo "fetching pinned libinput commit $UPSTREAM_COMMIT"
        git -C "$tree" fetch origin "$UPSTREAM_COMMIT"
    fi

    git -C "$tree" checkout --detach "$UPSTREAM_COMMIT"
fi

actual=$(git -C "$tree" rev-parse HEAD)
if [ "$actual" != "$UPSTREAM_COMMIT" ]; then
    echo "error: managed tree is at $actual, expected $UPSTREAM_COMMIT" >&2
    exit 1
fi

sh "$script_dir/link-core-subproject.sh" "$tree"

if git -C "$tree" apply --reverse --check "$meson_fix" >/dev/null 2>&1; then
    echo "0.1.0 patch and Meson fix already applied"
elif git -C "$tree" apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "0.1.0 patch already applied"
else
    git -C "$tree" apply --check "$patch"
    git -C "$tree" apply "$patch"
    echo "applied 0.1.0 patch"
fi

if git -C "$tree" apply --reverse --check "$meson_fix" >/dev/null 2>&1; then
    echo "Meson syntax fix already applied"
else
    git -C "$tree" apply --check "$meson_fix"
    git -C "$tree" apply "$meson_fix"
    echo "applied Meson syntax fix"
fi

git -C "$tree" diff --check

cat <<EOF
ready: $tree
upstream: libinput $LIBINPUT_VERSION @ $UPSTREAM_COMMIT

Next step:
  meson setup '$tree/builddir' '$tree' \\
    --prefix=/usr/local \\
    --buildtype=release \\
    -Dlibwacom=false \\
    -Dtests=false \\
    -Ddebug-gui=false \\
    -Ddocumentation=false
  ninja -C '$tree/builddir'
EOF
