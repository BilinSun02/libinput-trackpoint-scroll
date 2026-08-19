#!/bin/sh
set -eu

UPSTREAM_COMMIT=659967488e1e66d7fb7210c6b86860c8e1e5bed4
UPSTREAM_URL=${LIBINPUT_UPSTREAM_URL:-https://gitlab.freedesktop.org/libinput/libinput.git}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
work_root="$repo_root/.work"
tree="$work_root/libinput"
patch="$work_root/libinput-trackpoint-scroll-v0.1.0.patch"

mkdir -p "$work_root"

# Ensure the exact shared revision recorded by this repository is available.
git -C "$repo_root" submodule update --init --recursive

if [ ! -d "$tree/.git" ]; then
    if [ -e "$tree" ]; then
        echo "error: $tree exists but is not a git checkout" >&2
        exit 1
    fi

    echo "cloning libinput into $tree"
    git clone --filter=blob:none "$UPSTREAM_URL" "$tree"
fi

if [ -n "$(git -C "$tree" status --porcelain)" ]; then
    # A previously applied project patch is allowed; arbitrary local edits are not.
    "$script_dir/materialize-0.1.0-patch.sh" "$patch" >/dev/null
    if git -C "$tree" apply --reverse --check "$patch" >/dev/null 2>&1; then
        echo "existing patched tree detected"
    else
        echo "error: managed libinput tree contains local changes not recognized as the 0.1.0 patch" >&2
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

"$script_dir/link-core-subproject.sh" "$tree"
"$script_dir/materialize-0.1.0-patch.sh" "$patch"

if git -C "$tree" apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "0.1.0 patch already applied"
else
    git -C "$tree" apply --check "$patch"
    git -C "$tree" apply "$patch"
    git -C "$tree" diff --check
    echo "applied 0.1.0 patch"
fi

cat <<EOF
ready: $tree

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
