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

## 0.1.0 line

0.1.0 is the first core-backed integration line. A production 0.1.0 patch must replace the duplicated reusable mechanics with calls into the pinned `core/` submodule while retaining libinput-owned routing, adaptive filtering, event posting, keyboard policy, config parsing, and middle-click suppression.

Do not declare the 0.1.0 patch release-complete until it has been generated against the pristine pinned upstream tree and built/tested as described in `docs/CORE_MIGRATION.md`.

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

Record the patch SHA-256 and the exact core gitlink used by that patch.
