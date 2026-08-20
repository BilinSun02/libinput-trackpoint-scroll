#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$repo_root/UPSTREAM"

tree="$repo_root/.work/libinput"
out="$repo_root/patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch"
sha_file="$repo_root/patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.sha256"
meson_fix="$repo_root/patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0-meson-fix.patch"
base_gz="$repo_root/patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.gz"

for cmd in git gzip sha256sum python3 meson ninja cmp; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "error: required command not found: $cmd" >&2
        exit 1
    }
done

if [ ! -d "$tree/.git" ]; then
    echo "error: managed upstream checkout not found: $tree" >&2
    echo "       run: sh ./tools/prepare-libinput-tree.sh" >&2
    exit 1
fi

if ! git -C "$tree" cat-file -e "$LIBINPUT_COMMIT^{commit}" 2>/dev/null; then
    echo "error: managed checkout does not contain pinned commit $LIBINPUT_COMMIT" >&2
    exit 1
fi

# The generated canonical artifact must be tied to the exact core gitlink in
# this integration commit, not an arbitrary newer checkout of the core repo.
core_expected=$(git -C "$repo_root" ls-tree HEAD core | awk '{print $3}')
if [ -z "$core_expected" ]; then
    echo "error: cannot read core gitlink from integration repository" >&2
    exit 1
fi
if [ ! -d "$repo_root/core" ]; then
    echo "error: core submodule is not initialized" >&2
    echo "       run: git submodule update --init --recursive" >&2
    exit 1
fi
core_actual=$(git -C "$repo_root/core" rev-parse HEAD)
if [ "$core_actual" != "$core_expected" ]; then
    echo "error: core checkout is at $core_actual, expected gitlink $core_expected" >&2
    echo "       run: git submodule update --init --recursive" >&2
    exit 1
fi

tmp_root=$(mktemp -d "$repo_root/.work/finalize-0.1.0.XXXXXX")
worktree="$tmp_root/libinput"
base_patch="$tmp_root/base.patch"
verify_patch="$tmp_root/verify.patch"
cleanup() {
    if [ -d "$worktree" ]; then
        git -C "$tree" worktree remove --force "$worktree" >/dev/null 2>&1 || true
    fi
    rm -rf "$tmp_root"
}
trap cleanup EXIT HUP INT TERM

git -C "$tree" worktree add --detach "$worktree" "$LIBINPUT_COMMIT" >/dev/null
actual=$(git -C "$worktree" rev-parse HEAD)
if [ "$actual" != "$LIBINPUT_COMMIT" ]; then
    echo "error: temporary worktree is at $actual, expected $LIBINPUT_COMMIT" >&2
    exit 1
fi

# Reconstruct the exact corrected candidate from repository-owned ingredients.
gzip -dc "$base_gz" > "$base_patch"
base_expected=8a2149667755545fa8ff7b378de839bfb90e0728ed01cddfcabf03e3fa17c016
base_actual=$(sha256sum "$base_patch" | awk '{print $1}')
if [ "$base_actual" != "$base_expected" ]; then
    echo "error: stored base patch checksum mismatch" >&2
    echo "       expected: $base_expected" >&2
    echo "       actual:   $base_actual" >&2
    exit 1
fi

git -C "$worktree" apply --check "$base_patch"
git -C "$worktree" apply "$base_patch"
git -C "$worktree" apply --check "$meson_fix"
git -C "$worktree" apply "$meson_fix"
python3 "$script_dir/fix-0.1.0-usec-boundary.py" "$worktree"
git -C "$worktree" diff --check

expected_files='meson.build
src/evdev-fallback.c
src/evdev.c
src/evdev.h'
# File-set membership must not depend on the user's locale/collation rules.
# The expected list above is in bytewise C-locale order; sort the actual list
# the same way before comparing it.
actual_files=$(git -C "$worktree" diff --name-only | LC_ALL=C sort)
if [ "$actual_files" != "$expected_files" ]; then
    echo "error: corrected candidate touches an unexpected file set:" >&2
    printf '%s\n' "$actual_files" >&2
    echo "expected:" >&2
    printf '%s\n' "$expected_files" >&2
    exit 1
fi

# Generate a single plain-text patch containing both former temporary fixes.
git -C "$worktree" diff --binary --no-ext-diff --no-renames \
    --src-prefix=a/ --dst-prefix=b/ > "$out"
canonical_sha=$(sha256sum "$out" | awk '{print $1}')
printf '%s  %s\n' "$canonical_sha" "$(basename "$out")" > "$sha_file"

# Prove the generated artifact independently against pristine pinned upstream.
git -C "$worktree" reset --hard "$LIBINPUT_COMMIT" >/dev/null
git -C "$worktree" clean -fdx >/dev/null
git -C "$worktree" apply --check "$out"
git -C "$worktree" apply "$out"
git -C "$worktree" diff --check

git -C "$worktree" diff --binary --no-ext-diff --no-renames \
    --src-prefix=a/ --dst-prefix=b/ > "$verify_patch"
cmp "$out" "$verify_patch"

# Validate the real Meson subproject boundary and compile the final artifact.
sh "$script_dir/link-core-subproject.sh" "$worktree"
meson setup "$worktree/builddir" "$worktree" \
    --prefix=/usr/local \
    --buildtype=release \
    -Dlibwacom=false \
    -Dtests=false \
    -Ddebug-gui=false \
    -Ddocumentation=false
ninja -C "$worktree/builddir"

printf '%s\n' \
    "canonical 0.1.0 patch generated and clean-built" \
    "patch:   $out" \
    "sha256:  $canonical_sha" \
    "upstream: $LIBINPUT_COMMIT" \
    "core:     $core_expected"

git -C "$worktree" diff --stat

echo
echo "Repository files now changed:"
git -C "$repo_root" status --short -- \
    patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch \
    patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.sha256
