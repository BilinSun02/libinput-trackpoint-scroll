# Patches

Production patches in this repository are complete replacement patches against the pinned pristine source revision, not incremental patches against another project version.

The authoritative current upstream URL/version/commit live in the root-level `UPSTREAM` file. Current-line documentation and automation should refer to that file rather than duplicate the pin.

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

The timestamp-boundary fixer exists because libinput deliberately defines `usec_t` as a strong newtype, while the platform-neutral core deliberately accepts plain `uint64_t` microsecond timestamps. The adapter must therefore convert explicitly:

```text
libinput usec_t -> core uint64_t: usec_as_uint64_t(...)
core uint64_t -> libinput usec_t: usec_from_uint64_t(...)
```

The fixer is intentionally strict. It expects exactly the ten call sites exposed by the first real Ninja compile and refuses a partial or drifted transformation. Once the canonical replacement patch is regenerated after successful host validation, these temporary corrections should be folded into that single patch artifact.

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

Unlike 0.0.14, it removes the duplicated startup/coalescing/ring/memoryless-profile implementation from the libinput patch. Those facilities are provided by `core/`. The libinput side retains routing, config parsing/aliases, the upstream adaptive-filter wrapper, timers, free/locked posting, Shift/Scroll Lock policy, middle-click suppression, and public sequence bookkeeping.

### Validation completed for the candidate

- base replacement patch against the pristine revision recorded by `LIBINPUT_COMMIT` in `UPSTREAM`;
- old-side/context inheritance checked against the exact 0.0.14 patch, with separately verified upstream Meson/include context;
- `git apply --check`, `git apply`, and `git diff --check` passed on the reconstructed pristine source map;
- stale-inline scan confirmed the old grid/ring/accelerator state is not duplicated in the new integration;
- shared-core strict C11 tests and ASan/UBSan runs passed;
- standalone 0.0.14-vs-core trace comparison passed for affine, quadratic, and hyperbolic behavior, including startup/coalescing, overlap, idle rearm, and Shift-style startup-bypass restart;
- the integration-owned custom block passed a strict mock-host C syntax check;
- the first real Meson configure exposed and localized the split-assignment syntax error, now corrected by the explicit Meson fixup patch;
- the first real Ninja compile exposed the `usec_t`/`uint64_t` adapter mismatch, now corrected explicitly at the integration boundary without changing the core API.

### Validation still required before calling 0.1.0 release-complete

After applying the current complete patch set, these remain mandatory:

```text
successful Ninja compile
interactive behavioral smoke test
```

Do not describe the 0.1.0 candidate as fully release-validated until those checks pass.

## Release checklist

A patch set is production-ready only after:

```text
pristine exact upstream checkout
git apply --check
git diff --check
Meson configure
Ninja compile
behavioral smoke test
```

Record the patch SHA-256, exact core gitlink, and the `UPSTREAM` state used by that patch.
