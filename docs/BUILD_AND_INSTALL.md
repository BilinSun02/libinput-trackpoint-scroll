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

Prepare the managed source tree with:

```bash
sh ./tools/prepare-libinput-tree.sh
```

The script creates and manages `.work/libinput/`, checks out the exact upstream commit from `UPSTREAM`, initializes the pinned core submodule, links it into the libinput Meson tree, materializes and applies the current patch/fixups, validates commit-specific compatibility expectations, and runs `git diff --check`.

The managed default is deliberately non-package-managed:

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

`/usr/local` is a default, not a statement about where every existing libinput must live. The installer discovers the configured prefix from Meson and verifies the actual loader-selected library after installation.

Do not configure the managed helper to overwrite `/usr` merely to force precedence over a distro library. On Debian/Ubuntu, `/usr` library/tool paths are commonly owned by dpkg packages; silently replacing them makes package upgrades/reinstalls able to overwrite the custom build and makes custom uninstall operations able to damage package-managed files.

## Manual workflow

A manually maintained libinput checkout may use another prefix. The verified installer accepts an explicit build directory:

```bash
sudo sh ./tools/install-managed-libinput.sh /path/to/builddir
```

The helper is prefix-agnostic but package-aware. Before installing, it inspects Meson's complete installed-file map and, when `dpkg-query` is available, refuses the operation if any destination is owned by a Debian package.

If direct replacement of package-managed files is intentionally required, use an explicit Debian packaging or `dpkg-divert` design instead of bypassing that refusal. Debian provides diversions specifically for controlled local/package overrides; arbitrary writes over dpkg-owned files are not the managed workflow.

## Install and activate safely

For the managed tree:

```bash
sudo sh ./tools/install-managed-libinput.sh
```

The installer performs these checks/actions in order:

1. reads the Meson prefix and complete installed-file map;
2. refuses to overwrite dpkg-owned destinations;
3. records the currently loader-selected `libinput.so.10`, if any;
4. installs into the build's configured prefix without first uninstalling another libinput elsewhere;
5. runs `ldconfig`;
6. verifies loader-visible `libinput.so*` paths exist;
7. compares the ELF Build ID of the loader-selected SONAME with the build artifact.

Only an exact Build-ID match produces:

```text
install verification passed
safe to restart the graphical session or reboot
```

### Existing self-compiled libinput elsewhere

Do not guess or hardcode where the previous custom build lives.

If another self-compiled libinput in a different prefix still wins dynamic linking after `ldconfig`, the installer stops with the selected path and Build-ID mismatch. It does **not** uninstall that installation automatically. Identify its provenance/build tree first, then decide whether to uninstall it, change loader configuration, or intentionally keep it.

If the previous custom build uses the same non-package prefix and destinations, installing the replacement normally replaces those files directly; there is no need for an uninstall-first gap.

### Existing dpkg/apt-managed libinput

A normal Ubuntu/Debian libinput installation should remain owned and maintained by dpkg/apt. The managed default under `/usr/local` does not intentionally overwrite it.

After installing the custom build, `ldconfig` determines the cache seen by new processes. The Build-ID check is authoritative for this workflow: if the distro library still wins, the installer fails and says not to reboot. Do not solve that mismatch by blindly writing the custom library over `/usr`.

Package upgrades can rebuild the loader cache or change the distro library later. Re-run the verification installer (or at minimum repeat the loader/Build-ID checks) after relevant package upgrades before assuming the custom library is still selected.

## Loader diagnostics

Useful checks are:

```bash
ldconfig -p | grep 'libinput\.so.10'
readelf -n .work/libinput/builddir/libinput.so.10.13.0 | grep 'Build ID'
```

A running process keeps the library it mapped at session start, so after a verified install start a fresh graphical session before judging runtime behavior.

If the graphical session fails after an install, preserve the failed boot's journal. An error such as:

```text
libinput.so.10: cannot open shared object file: No such file or directory
```

is an installation/loader failure. An `undefined symbol` or compositor crash after the correct Build ID has been loaded points instead toward ABI/runtime behavior.

## Lesson from the 0.1.0 validation incident

The first 0.1.0 installation was placed under `/usr/local`, but the old v14 system-path installation was uninstalled first and `ldconfig` was not run after installing the new build. The next boot could not resolve `libinput.so.10`. Recovery then restored v14, and a later successful desktop boot was shown by Build-ID comparison to still be using v14.

The evidence does **not** establish that `/usr/local` itself is unusable. At the time of inspection, the custom `/usr/local` library existed and its directory was configured in `ld.so.conf`, but the current cache still selected the system/v14 copy. The correct lesson is to make cache refresh and exact loader verification mandatory, not to hardcode `/usr`.

## Runtime configuration reload

The runtime file is parsed once per TrackPoint device initialization. After config-only changes, replug a removable device or restart the graphical session for a built-in device. After library changes, start a fresh graphical session so the compositor maps the replacement library.
