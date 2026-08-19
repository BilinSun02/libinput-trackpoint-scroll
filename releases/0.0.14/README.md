# 0.0.14

This release records the known-working pre-core-refactor implementation formerly distributed as **v14**.

The historical v14 filenames and contents are preserved inside `libinput-trackpoint-scroll-v14-documented-bundle.zip`. The bundle was supplied from the deployed/validated working version rather than reconstructed from chat history.

Target upstream revision:

```text
libinput 1.31.0
659967488e1e66d7fb7210c6b86860c8e1e5bed4
```

Canonical patch inside the bundle:

```text
libinput-1.31.0-trackpoint-scroll-2ms-grid-startup-coalescing-middle-suppression-v14.patch
SHA-256 5a7f58a5406c03c085e495417acca8388e4b05b8073268830269e1e1d24e54cd
```

The original manifest inside the bundle verifies the patch, example configuration, notes, and complete guide. Project version **0.0.14** corresponds to that historical v14 distribution.

## Status

0.0.14 is the compatibility/baseline release: it is known to work in daily use, but its reusable startup, reconstruction, and memoryless-profile code remains embedded directly in the libinput patch and does **not** use the `core/` submodule.

Development after this release is versioned **0.1.0** and is intended to preserve 0.0.14 behavior while moving reusable mechanics to `trackpoint-scroll-core`.
