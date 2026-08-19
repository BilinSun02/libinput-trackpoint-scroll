# Build and installation

## Pinned source

This integration targets libinput 1.31.0 at exactly:

```text
659967488e1e66d7fb7210c6b86860c8e1e5bed4
```

Use a pristine checkout or a dedicated worktree. Do not stack the current patch on top of an older experimental patch.

## Clone with the shared core

This repository uses a submodule:

```bash
git clone --recurse-submodules <this-repository>
```

For an existing clone:

```bash
git submodule update --init --recursive
```

The integration patch/build glue should consume `core/` from the exact gitlink recorded by this repository, not an arbitrary neighboring checkout.

## Recommended Meson options

The default project build disables libwacom:

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

## Patch validation

Before applying:

```bash
git rev-parse HEAD
git status --short
git apply --check /path/to/current.patch
```

After applying:

```bash
git diff --check
ninja -C builddir
```

The real checkout/compiler are authoritative. Two earlier failures justify this rule:

1. a malformed hunk could validate against a synthetic preimage that repeated the same mistake;
2. a custom helper collided with an existing symbol and only a real compile exposed it.

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
