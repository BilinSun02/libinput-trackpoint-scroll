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

The script creates and manages `.work/libinput/`, checks out the exact upstream commit from `UPSTREAM`, initializes the pinned core submodule, links it into the libinput Meson tree, materializes and applies the current patch/fixups, validates commit-specific compatibility expectations, and runs `git diff --check`.

After preparation, configure and build with the system replacement prefix:

```bash
meson setup .work/libinput/builddir .work/libinput \
  --prefix=/usr \
  --buildtype=release \
  -Dlibwacom=false \
  -Dtests=false \
  -Ddebug-gui=false \
  -Ddocumentation=false

ninja -C .work/libinput/builddir
```

`/usr` is deliberate. On the tested Ubuntu system the desktop loader-selected `libinput.so.10` lives in the system multiarch libdir (`/lib/x86_64-linux-gnu`, merged with `/usr/lib/x86_64-linux-gnu`). A build installed under `/usr/local/lib/x86_64-linux-gnu` was present and listed in `ld.so.conf`, but the loader still selected the system copy with the same SONAME. Therefore `/usr/local` is not a reliable replacement location for this project.

For testing a mirror or another transport without changing the project pin:

```bash
LIBINPUT_UPSTREAM_URL=<git-url> sh ./tools/prepare-libinput-tree.sh
```

That override changes only where Git fetches the pinned commit from; `UPSTREAM` remains authoritative.

The managed tree is deliberately disposable. The preparation script does **not** silently reset an unrecognized dirty checkout.

## Manual workflow with an existing libinput tree

Users who maintain a separate pristine libinput checkout can use it directly. First compare its HEAD with `LIBINPUT_COMMIT` in `UPSTREAM`, expose the pinned core checkout with `tools/link-core-subproject.sh`, apply the current patch/fixups, and configure the build with `--prefix=/usr`.

The real checkout/compiler are authoritative. Development has already exposed malformed generated Meson syntax, a symbol collision, and `usec_t` adapter errors that synthetic validation alone did not catch.

## Install and replace safely

This project intentionally replaces the system libinput used by GNOME/Mutter. Package-manager upgrades may overwrite it; conversely, installing this project overwrites the package-managed library contents at the same ABI path. Keep a known-working fallback available.

When replacing one project build with another compatible build, **do not uninstall the loader-selected build first**. Installing the replacement directly avoids an interval where GNOME and Xorg cannot resolve `libinput.so.10`.

For the managed tree use:

```bash
sudo sh ./tools/install-managed-libinput.sh
```

The installer requires a Meson prefix of `/usr`, performs `ninja install`, runs `ldconfig`, finds the loader-selected SONAME, and compares its ELF Build ID with the build artifact. It prints a hard error and `DO NOT ... reboot` if the selected library is not exactly the one just built.

### One-time migration from the earlier `/usr/local` build

If a build directory was previously configured with `--prefix=/usr/local` and that version is already installed while a known-working system/v14 libinput is still loader-selected, clean only that `/usr/local` installation before changing the prefix:

```bash
sudo ninja -C .work/libinput/builddir uninstall
```

At this point the system/v14 copy remains the loader-selected fallback. Then reconfigure the same build directory and rebuild:

```bash
meson setup --reconfigure .work/libinput/builddir .work/libinput \
  --prefix=/usr
ninja -C .work/libinput/builddir
```

Do **not** uninstall the system/v14 copy. Install the new build directly over it:

```bash
sudo sh ./tools/install-managed-libinput.sh
```

Only restart the graphical session or reboot after the installer reports that the loader-selected Build ID matches the build artifact.

## Loader diagnostics

Useful checks are:

```bash
ldconfig -p | grep 'libinput\.so.10'
readelf -n .work/libinput/builddir/libinput.so.10.13.0 | grep 'Build ID'
```

A running process keeps the library it mapped at session start, so after a successful verified install start a fresh graphical session before judging runtime behavior.

If the graphical session fails after an install, preserve the failed boot's journal. An error such as:

```text
libinput.so.10: cannot open shared object file: No such file or directory
```

is an installation/loader failure. An `undefined symbol` or compositor crash after the correct Build ID has been loaded points instead toward ABI/runtime behavior.

## Runtime configuration reload

The runtime file is parsed once per TrackPoint device initialization. After config-only changes, replug a removable device or restart the graphical session for a built-in device. After library changes, start a fresh graphical session so the compositor maps the replacement library.
