# Patches

Production patches in this repository are complete replacement patches against the pinned pristine source revision, not incremental patches against another project version.

Current upstream target:

```text
659967488e1e66d7fb7210c6b86860c8e1e5bed4
```

## 0.0.14 behavioral baseline

The known-working pre-core patch is preserved in the exact historical bundle under `releases/0.0.14/`:

```text
libinput-1.31.0-trackpoint-scroll-2ms-grid-startup-coalescing-middle-suppression-v14.patch
SHA-256 5a7f58a5406c03c085e495417acca8388e4b05b8073268830269e1e1d24e54cd
```

Project version **0.0.14** corresponds to that historical v14 distribution. It is the behavioral compatibility reference: its reusable startup/reconstruction/memoryless-profile algorithms remain inline in the libinput patch and it does not use the `core/` submodule.

## 0.1.0 core-backed candidate

The first core-backed replacement patch is stored compressed as:

```text
patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.gz
```

Materialize it with:

```bash
gzip -dc patches/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch.gz \
  > /tmp/libinput-1.31.0-trackpoint-scroll-core-v0.1.0.patch
```

Checksums:

```text
uncompressed patch:
8a2149667755545fa8ff7b378de839bfb90e0728ed01cddfcabf03e3fa17c016

stored gzip:
8410949b4a8e12bb0a364657480615f787715ed07f96fd541ba8ee19aca04e74
```

The patch is tied to core gitlink:

```text
133df50ea5ce58e71e3fed3240c26999ee689386
```

Unlike 0.0.14, it removes the duplicated startup/coalescing/ring/memoryless-profile implementation from the libinput patch. Those facilities are provided by `core/`. The libinput side retains routing, config parsing/aliases, the upstream adaptive-filter wrapper, timers, free/locked posting, Shift/Scroll Lock policy, middle-click suppression, and public sequence bookkeeping.

### Validation completed for the candidate

- complete replacement patch against the same pinned pristine revision;
- old-side/context inheritance checked against the exact 0.0.14 patch, with separately verified upstream Meson/include context;
- `git apply --check`, `git apply`, and `git diff --check` passed on the reconstructed pristine source map;
- stale-inline scan confirmed the old grid/ring/accelerator state is not duplicated in the new integration;
- shared-core strict C11 tests and ASan/UBSan runs passed;
- standalone 0.0.14-vs-core trace comparison passed for affine, quadratic, and hyperbolic behavior, including startup/coalescing, overlap, idle rearm, and Shift-style startup-bypass restart;
- the integration-owned custom block passed a strict mock-host C syntax check.

### Validation still required before calling 0.1.0 release-complete

The current execution environment did not have Meson and could not install it from the network. Therefore these remain mandatory on a real pristine checkout:

```text
Meson configure
Ninja compile
interactive behavioral smoke test
```

Do not describe the 0.1.0 candidate as fully release-validated until those checks pass.

## Release checklist

A patch is production-ready only after:

```text
pristine exact upstream checkout
git apply --check
git diff --check
Meson configure
Ninja compile
behavioral smoke test
```

Record the patch SHA-256 and exact core gitlink used by that patch.
