# Patches

Production patches in this repository are complete replacement patches against the pinned pristine source revision, not incremental patches against another project version.

The authoritative current upstream URL/version/commit live in the root-level `UPSTREAM` file. Current-line documentation and automation should refer readers to that file rather than duplicate the pin.

## 0.0.14 behavioral baseline

The known-working pre-core patch is preserved in the exact historical bundle under `releases/0.0.14/`:

```text
libinput-1.31.0-trackpoint-scroll-2ms-grid-startup-coalescing-middle-suppression-v14.patch
SHA-256 5a7f58a5406c03c085e495417acca8388e4b05b8073268830269e1e1d24e54cd
```

Project version **0.0.14** corresponds to that historical v14 distribution. It is the behavioral compatibility reference: its reusable startup/reconstruction/memoryless-profile algorithms remain inline in the libinput patch and it does not use the `core/` submodule.

## 0.1.0 core-backed candidate

The first core-backed replacement candidate is currently represented by a base patch plus two narrowly scoped integration corrections:

```text
patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.gz
patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0-meson-fix.patch
tools/fix-0.1.0-usec-boundary.py
```

`tools/prepare-libinput-tree.sh` applies/validates these in order and is the authoritative managed-source preparation path. Do not apply only the compressed base patch and assume the resulting tree is the current corrected candidate.

The Meson fix exists because the initial base patch split an assignment across a bare newline. Meson rejects that form; the correction keeps the dependency assignment on one statement.

The timestamp-boundary fixer exists because libinput deliberately defines `usec_t` as a strong newtype, while the platform-neutral core deliberately accepts plain `uint64_t` microsecond timestamps. The adapter therefore converts explicitly at the boundary. Call-site multiplicities are pinned to the exact upstream commit under `compat/libinput/<LIBINPUT_COMMIT>/`; structural matching validates each family and a re-pin without reviewed compatibility data fails closed.

The base patch can be materialized with:

```bash
gzip -dc patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.gz \
  > /tmp/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch
```

Checksums for the unchanged historical base candidate artifact:

```text
uncompressed base patch:
8a2149667755545fa8ff7b378de839bfb90e0728ed01cddfcabf03e3fa17c016

stored gzip:
8410949b4a8e12bb0a364657480615f787715ed07f96fd541ba8ee19aca04e74
```

The candidate is tied to core gitlink:

```text
133df50ea5ce58e71e3fed3240c26999ee689386
```

### Validation completed for the candidate

- base replacement patch against the pristine revision recorded by `LIBINPUT_COMMIT` in `UPSTREAM`;
- old-side/context inheritance checked against the exact 0.0.14 patch;
- `git apply --check`, `git apply`, and `git diff --check` passed;
- shared-core strict C11 tests and ASan/UBSan runs passed;
- standalone 0.0.14-vs-core trace comparison passed for the reusable behavior;
- the integration-owned custom block passed a strict mock-host C syntax check;
- real Meson configuration succeeded after correcting the generated dependency assignment;
- real Ninja compilation succeeded after correcting the explicit `usec_t`/`uint64_t` adapter boundary.

### Runtime validation still required

The apparent successful post-recovery desktop boot was later shown by ELF Build-ID comparison to be using an older/different libinput, not the core-backed build. Therefore that boot and its several-minute scrolling test do not count as 0.1.0 runtime validation.

Before runtime validation can be credited, the loader-selected installed `libinput.so.10` must have the same ELF Build ID as the build artifact, followed by a fresh graphical-session boot and behavioral smoke test.

### Confirmed installation/loader incident

The failed normal boot was an installation/loader failure rather than a scrolling-code crash: GNOME Shell and the Xorg libinput driver repeatedly failed with `libinput.so.10: cannot open shared object file`.

The known-working v14 library was loader-selected from the system libdir. The initial 0.1.0 build installed under `/usr/local/lib/x86_64-linux-gnu`, but the old build had been uninstalled first and `ldconfig` was not run after installing the new library. On the failed boot the loader could not resolve the SONAME. Recovery restored v14; a later successful boot still selected v14, as proven by Build-ID comparison.

The evidence does **not** establish that `/usr/local` is intrinsically unusable. The custom file and symlink chain existed and its directory was present in `ld.so.conf`; the missing safety step was a cache refresh plus exact loader-selection verification. Managed builds therefore retain the non-package default `/usr/local`, and `tools/install-managed-libinput.sh` now runs `ldconfig`, refuses dpkg-owned destinations, and verifies the selected Build ID before a restart is considered safe.

A previous self-compiled libinput elsewhere is not automatically removed. If it still wins dynamic linking, the installer fails closed and reports the selected path. A dpkg/apt-managed libinput is not overwritten by the managed helper; direct package-path replacement requires an explicit packaging or diversion strategy.

## Release checklist

A patch set is production-ready only after:

```text
pristine exact upstream checkout
git apply --check
git diff --check
Meson configure
Ninja compile
loader-selected Build ID matches build artifact
fresh graphical-session boot with that exact library
behavioral smoke test
```

Record the patch SHA-256, exact core gitlink, and the `UPSTREAM` state used by that patch.
