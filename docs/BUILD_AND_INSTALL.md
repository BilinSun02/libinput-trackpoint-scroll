# Build and installation

## Pinned source

The authoritative current upstream libinput repository, version, and commit are recorded in the root-level `UPSTREAM` file. Automation sources that file directly. Do not duplicate the current pin in scripts or prose that is meant to track the active development line.

To inspect it:

```bash
cat UPSTREAM
```

Do not stack the current patch on top of 0.0.14 or another experimental patch.

## Clone with the shared core

This repository uses a submodule:

```bash
git clone --recurse-submodules git@github.com:BilinSun02/libinput-trackpoint-scroll.git
```

For an existing clone:

```bash
git submodule update --init --recursive
```

The integration patch/build glue consumes `core/` from the exact gitlink recorded by this repository, not an arbitrary neighboring checkout.

## Managed-source fast path

Users who do not already have a suitable libinput checkout can prepare one automatically:

```bash
sh ./tools/prepare-libinput-tree.sh
```

The script creates and manages:

```text
.work/libinput/
```

`.work/` is git-ignored by this repository.

The script performs these steps:

1. initializes the exact `core/` submodule revision recorded by this repository;
2. reads the canonical upstream URL/version/commit from `UPSTREAM`;
3. clones that upstream into `.work/libinput/` when absent;
4. checks out the pinned commit in detached-HEAD state;
5. exposes `core/` as `subprojects/trackpoint-scroll-core` in the managed checkout;
6. materializes and SHA-256-verifies the 0.1.0 patch into `.work/`;
7. checks and applies that patch;
8. runs `git diff --check`;
9. prints the Meson/Ninja commands for the prepared tree.

For testing a mirror or another transport without changing the project pin:

```bash
LIBINPUT_UPSTREAM_URL=<git-url> sh ./tools/prepare-libinput-tree.sh
```

That override changes only where Git fetches the pinned commit from; `UPSTREAM` remains authoritative for the expected version and commit.

The managed tree is deliberately disposable. Remove `.work/libinput/` to recreate it from scratch.

The script does **not** silently reset an unrecognized dirty checkout. Re-running it is supported when the tree contains the project patch and ordinary untracked build output; if tracked changes do not match the expected 0.1.0 patch, it exits and asks the user to preserve or remove them explicitly.

After preparation, the default build commands are:

```bash
meson setup .work/libinput/builddir .work/libinput \
  --prefix=/usr/local \
  --buildtype=release \
  -Dlibwacom=false \
  -Dtests=false \
  -Ddebug-gui=false \
  -Ddocumentation=false

ninja -C .work/libinput/builddir
```

## Manual workflow with an existing libinput tree

Users who already maintain a separate pristine libinput checkout can use it directly. First compare that checkout's HEAD with `LIBINPUT_COMMIT` in `UPSTREAM`.

Expose the pinned core checkout to that tree:

```bash
sh ./tools/link-core-subproject.sh /path/to/libinput-source
```

The resulting libinput path is:

```text
subprojects/trackpoint-scroll-core
```

Materialize the current compressed patch:

```bash
sh ./tools/materialize-0.1.0-patch.sh /tmp/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch
```

That helper verifies the uncompressed SHA-256:

```text
8a2149667755545fa8ff7b378de839bfb90e0728ed01cddfcabf03e3fa17c016
```

Then, from the pristine libinput checkout:

```bash
git rev-parse HEAD
git status --short
git apply --check /tmp/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch
git apply /tmp/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch
git diff --check
```

The expected HEAD is `LIBINPUT_COMMIT` from `UPSTREAM`.

## Recommended Meson options

Configure **after** the core subproject link exists and the patch has been applied:

```bash
meson setup builddir \
  --prefix=/usr/local \
  --buildtype=release \
  -Dlibwacom=false \
  -Dtests=false \
  -Ddebug-gui=false \
  -Ddocumentation=false
```

The pinned source enables libwacom by default for tablet identification. This TrackPoint integration does not require it, and leaving it enabled can introduce an otherwise irrelevant build dependency. Enable it deliberately only when the resulting build needs that tablet-identification support.

The pinned option is `-Dtests=false` (plural).

Build:

```bash
ninja -C builddir
```

The real checkout/compiler are authoritative. Earlier development exposed two reasons not to substitute synthetic patch validation for this step:

1. a malformed hunk could validate against a synthetic preimage that repeated the same mistake;
2. a custom helper collided with an existing symbol and only a real compile exposed it.

The current 0.1.0 candidate has passed algorithm/static checks but has **not** yet completed this real Meson/Ninja integration build in the environment where it was generated. Treat this build as mandatory release validation.

## Install

The established install prefix is `/usr/local`:

```bash
sudo ninja -C builddir install
sudo ldconfig
```

For the managed tree, use:

```bash
sudo ninja -C .work/libinput/builddir install
sudo ldconfig
```

Inspect which library is selected:

```bash
ldconfig -p | grep 'libinput\.so'
which libinput
libinput --version
ldd "$(command -v libinput)" | grep libinput
```

A running GNOME/Mutter process keeps the shared object it mapped at session start. After installing a rebuilt library, log out and back in (or reboot). For GNOME Shell, mapped libraries can be inspected with:

```bash
grep -F libinput "/proc/$(pgrep -n gnome-shell)/maps" | sort -u
```

When debugging, a build-tree executable is preferable because its RPATH reduces ambiguity about which library it loads.

## Runtime configuration reload

The runtime file is parsed once per TrackPoint device initialization.

After config-only changes:

- replug a removable device; or
- restart the graphical session for a built-in device.

After library changes, restart the session so the compositor maps the new library. `udevadm trigger` alone does not reliably recreate the compositor-owned libinput device object.
