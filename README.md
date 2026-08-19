# libinput-trackpoint-scroll

A libinput integration for responsive TrackPoint middle-button scrolling, built around the shared `trackpoint-scroll-core` submodule.

Current development version: **0.1.0**. The exact known-working pre-core implementation is preserved as **0.0.14** under `releases/0.0.14/`.

The project targets one pinned source revision:

```text
libinput 1.31.0
659967488e1e66d7fb7210c6b86860c8e1e5bed4
```

The 0.0.14 behavior was validated over weeks of daily use. Its essential properties are:

- middle-button movement becomes scrolling with a 1 ms activation timeout;
- sparse TrackPoint motion is reconstructed on a 2 ms logical grid before nonlinear mapping;
- the first micro-scroll after a gesture or idle reset is a predictable componentwise fixed step;
- split-axis startup reports can coalesce and immediate opposite-sign rebound is suppressed only in the startup window;
- cursor acceleration and scroll acceleration are independent;
- free two-dimensional scrolling is the default;
- post-middle Shift switches between free and locked scrolling for the current gesture;
- Scroll Lock toggles the default mode for later gestures while remaining visible to normal software;
- no-scroll middle clicks are suppressed by default;
- release stops promptly and cancels any unexpired reconstruction tail.

The reusable motion-processing code lives in the `core/` submodule. This repository owns libinput-specific routing, configuration, keyboard policy, event posting, device setup, build instructions, and patches.

## Version lines

- **0.0.14** — exact historical v14 bundle, known-working baseline, with reusable algorithms still inline in the libinput patch.
- **0.1.0** — first core-backed line. A complete replacement candidate now exists and consumes the pinned core submodule for startup, reconstruction, and memoryless profile mechanics.

Current 0.1.0 candidate:

```text
patch (uncompressed SHA-256):
8a2149667755545fa8ff7b378de839bfb90e0728ed01cddfcabf03e3fa17c016

core gitlink:
133df50ea5ce58e71e3fed3240c26999ee689386
```

The patch is stored compressed under `patches/`; see `patches/README.md` and `docs/BUILD_AND_INSTALL.md`.

The candidate has passed core unit/sanitizer tests, standalone algorithm-equivalence traces, patch application/whitespace checks on the reconstructed pristine source map, and strict mock-host syntax checking. It has **not** yet passed the required real Meson/Ninja build and interactive smoke test, so 0.0.14 remains the fully field-tested fallback.

## Start here

- `docs/VERSIONS.md` — release/version meaning and compatibility baseline.
- `docs/BEHAVIOR.md` — exact user-visible behavior and configuration semantics.
- `docs/CONFIGURATION.md` — parser contract, aliases, compiled fallbacks, and reload behavior.
- `docs/ARCHITECTURE.md` — boundary between the shared engine and libinput integration.
- `docs/CORE_MIGRATION.md` — extracted-vs-integration ownership and 0.1.0 implementation/validation details.
- `docs/BUILD_AND_INSTALL.md` — managed-source and manual build/install workflows.
- `docs/DEVICE_SETUP.md` — device classification and udev details.
- `docs/DEBUGGING_AND_MAINTENANCE.md` — traps, validation rules, and operational checks.
- `docs/PROJECT_RULES.md` — contribution and documentation conventions.

## Fast path: prepare a managed libinput tree

For a fresh clone that does not already have libinput source available, run:

```bash
sh ./tools/prepare-libinput-tree.sh
```

This creates the git-ignored `.work/libinput/` checkout from the canonical upstream repository, checks out the pinned commit, initializes the shared submodule, links it into the upstream Meson tree, verifies/materializes the 0.1.0 patch, and applies it. It stops at a ready-to-configure source tree and never silently resets unrecognized local changes.

The manual workflow remains supported for users who already maintain a separate libinput checkout; see `docs/BUILD_AND_INSTALL.md`.

## Documentation rule

Important decisions made in discussions must also be recorded in these repositories so they remain usable without chat history. Porting handoff documents are the sole intended exception; any durable technical conclusion that affects this repository still belongs here.
