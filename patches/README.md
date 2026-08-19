# Patches

Production patches in this repository are complete replacement patches against the pinned pristine source revision, not incremental patches against another project version.

Current upstream target:

```text
659967488e1e66d7fb7210c6b86860c8e1e5bed4
```

## Deployed behavioral baseline

The last pre-extraction patch is v14:

```text
libinput-1.31.0-trackpoint-scroll-2ms-grid-startup-coalescing-middle-suppression-v14.patch
SHA-256 5a7f58a5406c03c085e495417acca8388e4b05b8073268830269e1e1d24e54cd
```

It is the behavioral reference for the initial core extraction. Its implementation keeps the reusable startup/reconstruction/memoryless-profile algorithms inline in libinput; the next production patch should replace those pieces with calls into `core/`.

The validated v14 patch artifact itself has not yet been imported into this repository. Do **not** recreate it from documentation or old snippets and label that reconstruction as v14. Import the exact validated artifact, or supersede it with a freshly generated and fully built core-backed patch against the pristine pinned source.

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
