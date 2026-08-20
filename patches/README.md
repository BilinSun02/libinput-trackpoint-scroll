# Patches

Production patches in this repository are complete replacement patches against the pinned pristine source revision, not incremental patches against another project version.

The authoritative current upstream URL/version/commit live in the root-level `UPSTREAM` file. Current-line documentation and automation should refer readers to that file rather than duplicate the pin.

## 0.0.14 behavioral baseline

The known-working pre-core patch is preserved in the exact historical bundle under `releases/0.0.14/`. Project version **0.0.14** corresponds to that historical v14 distribution and remains the deep field-tested behavioral compatibility reference.

## 0.1.0 core-backed candidate

The first core-backed replacement candidate is currently represented by a stored base patch plus two narrowly scoped integration corrections:

```text
patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.gz
patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0-meson-fix.patch
tools/fix-0.1.0-usec-boundary.py
```

`tools/prepare-libinput-tree.sh` applies/validates these in order and is the authoritative managed-source preparation path. Do not apply only the compressed base patch and assume the resulting tree is the current corrected candidate.

The Meson fix corrects the initial generated dependency-assignment syntax. The timestamp-boundary fixer preserves the deliberate distinction between libinput's strong `usec_t` and the core's plain `uint64_t` microsecond API; commit-specific source-shape expectations live under `compat/libinput/<LIBINPUT_COMMIT>/`.

The stored base patch can be materialized with:

```bash
gzip -dc patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.gz \
  > /tmp/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch
```

Checksums for the unchanged stored base artifact:

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

- base replacement patch checked against the pinned upstream revision;
- old-side/context inheritance checked against the exact 0.0.14 patch;
- `git apply --check`, `git apply`, and `git diff --check` passed;
- shared-core strict C11 tests and ASan/UBSan runs passed;
- standalone 0.0.14-vs-core trace comparison passed for the reusable behavior;
- the integration-owned custom block passed a strict mock-host C syntax check;
- real Meson configuration succeeded after correcting the generated dependency assignment;
- real Ninja compilation succeeded after correcting the explicit `usec_t`/`uint64_t` adapter boundary;
- the managed installer refreshed the loader cache and verified the first cache entry for `libinput.so.10` had the build artifact's ELF Build ID;
- a fresh normal graphical boot succeeded;
- post-reboot live process mappings of `libinput.so.10` had the same Build ID as the build artifact;
- basic interactive scrolling worked in that verified session.

The earlier post-recovery successful boot is **not** counted: Build-ID comparison later proved that session still mapped the older v14 library.

### Confirmed installation/loader incident

The failed normal boot was an installation/loader-resolution failure rather than a scrolling-code crash: GNOME Shell and the Xorg libinput driver repeatedly failed with `libinput.so.10: cannot open shared object file`.

The first 0.1.0 install placed the library under `/usr/local` after the old v14 installation had been removed. That manual sequence did not include a separate explicit `ldconfig`/cache-verification step before reboot. The failed-boot journal proves SONAME resolution failed, but it does not by itself prove the precise internal behavior of the Meson/Ninja install step or justify a stronger single-cause claim.

Recovery restored v14; a later boot still used v14. Inspection then showed the `/usr/local` candidate existed and its directory was configured in `ld.so.conf`, while the cache still selected v14. The evidence therefore did **not** establish that `/usr/local` was intrinsically unusable.

The corrected workflow keeps the non-package default `/usr/local`, performs an explicit `ldconfig`, refuses dpkg-owned destinations, verifies the first cache entry's Build ID before restart, and verifies actual process mappings after restart. See `tools/install-managed-libinput.sh`, `tools/verify-runtime-libinput.sh`, and `docs/BUILD_AND_INSTALL.md`.

Do not use `ldconfig -p` cache order as proof of what an already-running process mapped. Do not automatically remove other custom installations. Do not trust an old build tree's uninstall manifest after another overlapping installation has replaced the same destinations.

### Remaining 0.1.0 release work

The candidate has passed initial verified runtime validation, but final release packaging should still:

1. fold the Meson and timestamp-boundary corrections into one canonical replacement patch;
2. regenerate patch/gzip checksums and update materialization metadata;
3. re-run the complete pristine-checkout build/install validation on that final artifact;
4. explicitly re-exercise the integration-owned behavior matrix (free/locked, Shift ordering/toggle, Scroll Lock, middle suppression, release cancellation, and adaptive reset behavior where applicable).

## Release checklist

A patch set is production-ready only after:

```text
pristine exact upstream checkout
git apply --check
git diff --check
Meson configure
Ninja compile
cache Build ID matches build artifact
fresh graphical-session boot
live process mapping Build ID matches build artifact
behavioral smoke/matrix checks
```

Record the patch SHA-256, exact core gitlink, and the `UPSTREAM` state used by that patch.
