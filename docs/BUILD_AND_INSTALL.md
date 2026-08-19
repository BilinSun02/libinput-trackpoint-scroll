# Build and installation

## Pinned source

This integration targets libinput 1.31.0 at exactly:

```text
659967488e1e66d7fb7210c6b86860c8e1e5bed4
```

Use a pristine checkout or a dedicated worktree. Do not stack the current patch on top of 0.0.14 or another experimental patch.

## Clone with the shared core

This repository uses a submodule:

```bash
git clone --recurse-submodules <this-repository>
```

For an existing clone:

```bash
git submodule update --init --recursive
```

The integration patch/build glue consumes `core/` from the exact gitlink recorded by this repository, not an arbitrary neighboring checkout.

## Prepare a pristine libinput tree for 0.1.0

In the integration repository, expose the pinned core checkout to the pristine libinput tree as the Meson subproject expected by the patch:

```bash
sh ./tools/link-core-subproject.sh /path/to/libinput-source
```

The resulting libinput path is:

```text
subprojects/trackpoint-scroll-core
```

Materialize the current compressed patch:

```bash
gzip -dc patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.gz \
  > /tmp/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch
```

Check the uncompressed SHA-256:

```bash
printf '%s  %s\n' \
  8a2149667755545fa8ff7b378de839bfb90e0728ed01cddfcabf03e3fa17c016 \
  /tmp/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch | sha256sum -c -
```

Then, from the pristine libinput checkout:

```bash
git rev-parse HEAD
git status --short
git apply --check /tmp/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch
git apply /tmp/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch
git diff --check
```

The expected HEAD is the pinned commit above.

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
