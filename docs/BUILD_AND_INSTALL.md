# Build and installation

## Pinned source

The authoritative current upstream libinput repository, version, and commit are recorded in the root-level `UPSTREAM` file. Automation sources that file directly. Do not duplicate the current pin in scripts or prose meant to track the active development line.

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

The integration patch/build glue consumes `core/` from the exact gitlink recorded by this repository.

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

`/usr/local` is a default, not an assumption about where every existing libinput lives. The installer reads the configured prefix and complete install map from Meson.

Do not configure the managed helper to overwrite `/usr` merely to force precedence over a distro library. On Debian/Ubuntu, `/usr` paths are commonly owned by dpkg packages; silently replacing them makes package upgrades/reinstalls able to overwrite the custom build and makes custom uninstall operations able to damage package-managed files.

## Manual workflow

A manually maintained libinput checkout may use another prefix. The verified installer accepts an explicit build directory:

```bash
sudo sh ./tools/install-managed-libinput.sh /path/to/builddir
```

The helper is prefix-agnostic but package-aware. Before installing, it inspects Meson's installed-file map and, when `dpkg-query` is available, refuses the operation if a destination is owned by a Debian package.

If direct replacement of package-managed files is intentionally required, use an explicit Debian packaging or `dpkg-divert` design rather than bypassing that refusal.

## Install and activate safely

For the managed tree:

```bash
sudo sh ./tools/install-managed-libinput.sh
```

The installer performs these checks/actions in order:

1. reads the Meson prefix and installed-file map;
2. refuses to overwrite dpkg-owned destinations;
3. records the current first `ldconfig` cache entry for the required SONAME, if any;
4. installs into the build's configured prefix without first uninstalling another libinput elsewhere;
5. runs `ldconfig`;
6. verifies cache-visible `libinput.so*` paths exist;
7. compares the ELF Build ID of the first `ldconfig` cache entry for the SONAME with the build artifact.

Only an exact cache Build-ID match produces:

```text
install verification passed
safe to restart the graphical session or reboot
```

### Cache selection is not runtime proof

`ldconfig -p` describes the loader cache. It does not prove what an already-running process has mapped, and process-specific RPATH/RUNPATH/environment can in principle affect resolution.

After a fresh graphical-session start or reboot, verify actual process mappings with:

```bash
sh ./tools/verify-runtime-libinput.sh
```

That helper compares the build artifact, first cache entry, and every readable running process mapping of the required libinput SONAME by ELF Build ID. Before trusting the pathname of a mapping, it also verifies that the mapping's device/inode still refers to the file currently at that path; this avoids falsely identifying an old mapped inode after an on-disk replacement.

Runtime validation is credited only when an actual process mapping is safely tied to a file with the build artifact's Build ID.

## Existing self-compiled libinput elsewhere

Do not guess or hardcode where a previous custom build lives.

If another self-compiled libinput in a different prefix is still first in the `ldconfig` cache after installation, the installer stops with the selected path and Build-ID mismatch. It does **not** uninstall that installation automatically. Identify its provenance/build tree first, then decide whether to uninstall it, change loader configuration, or intentionally keep it.

If the previous custom build uses the same non-package prefix and destinations, installing the replacement normally replaces those files directly; there is no need for an uninstall-first gap.

### Do not trust stale uninstall manifests

`ninja uninstall` uses the install manifest from the build tree that invokes it. It does not know whether another build subsequently replaced files at the same destinations.

Therefore an old build tree's uninstall can delete a newer build's files when their install paths overlap. Before uninstalling an old custom build after another build has been installed, inspect the old install manifest/destinations and confirm they are not now occupied by the replacement.

This is a second reason, beyond avoiding a temporary missing-SONAME state, not to use `uninstall -> install` as the normal upgrade sequence.

## Existing dpkg/apt-managed libinput

A normal Ubuntu/Debian libinput installation should remain owned and maintained by dpkg/apt. The managed default under `/usr/local` does not intentionally overwrite it.

The installer's dpkg ownership check is **prospective**: it prevents this helper from newly overwriting package-owned destinations. It does not prove that package-owned files were pristine before the helper ran. A historical manual/custom install may already have replaced bytes at a path that dpkg still considers its own.

If package cleanliness matters, first identify ownership with `dpkg-query -S <path>`, then use the package manager's verification/reinstall mechanisms deliberately. Do not make the custom installer silently repair or delete pre-existing package-path modifications because their provenance may be unrelated to this project.

After installing the custom build, `ldconfig` determines cache order for ordinary new processes. If the distro library remains first in the cache, the installer fails and says not to reboot. Do not solve that mismatch by blindly writing the custom library over `/usr`.

Package upgrades can rebuild the loader cache or change the distro library later. Re-run the install verification or at minimum repeat the cache/runtime Build-ID checks after relevant package upgrades before assuming the custom library is still active.

## Loader and runtime diagnostics

Cache/build checks:

```bash
ldconfig -p | grep 'libinput\.so.10'
readelf -n .work/libinput/builddir/libinput.so.10.13.0 | grep 'Build ID'
```

Actual runtime check:

```bash
sh ./tools/verify-runtime-libinput.sh
```

A running process keeps the library it mapped at session start. Installing a new library does not change that mapping retroactively.

If the graphical session fails after an install, preserve the failed boot's journal before recovery changes when practical. An error such as:

```text
libinput.so.10: cannot open shared object file: No such file or directory
```

is an installation/loader-resolution failure. An `undefined symbol` or compositor crash after the correct Build ID is actually mapped points instead toward ABI/runtime behavior.

## Lesson from the 0.1.0 validation incident

The first 0.1.0 installation was placed under `/usr/local`, and the old v14 system-path installation had been uninstalled first. The manual sequence did not include a separate explicit `ldconfig`/cache-verification step before reboot. The failed boot's journal proves that GNOME Shell and the Xorg libinput driver could not resolve `libinput.so.10`; it does **not** by itself prove the exact internal behavior of Meson/Ninja's install step or establish a single causal mechanism beyond that failed resolution state.

Recovery restored v14, and a later successful desktop boot was shown by Build-ID comparison to still be using v14. Inspection then showed the new `/usr/local` library existed and `/usr/local/lib/x86_64-linux-gnu` was configured in `ld.so.conf`, while the cache still selected the system/v14 copy.

The evidence therefore did **not** establish that `/usr/local` itself was unusable. The durable correction was to make an explicit cache refresh plus exact identity verification mandatory, not to hardcode `/usr`.

After the installer was corrected, the same `/usr/local` core-backed build was installed, its first `ldconfig` cache entry matched the build artifact's Build ID, the machine rebooted normally, and post-reboot live process mappings matched the same Build ID. Basic scrolling worked in that verified session.

Historical intermediate hypotheses such as “the core-backed library itself crashes GNOME” or “`/usr/local` cannot be used” are not current conclusions.

## Runtime configuration reload

The runtime file is parsed once per TrackPoint device initialization. After config-only changes, replug a removable device or restart the graphical session for a built-in device. After library changes, start a fresh graphical session so the compositor maps the replacement library.
