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
- **0.1.0** — first core-backed line. Reusable startup, reconstruction, and memoryless-profile mechanics must come from the pinned `core/` submodule rather than a duplicated inline copy.

See `docs/VERSIONS.md`. A `VERSION` value of 0.1.0 marks the active development line; it does not by itself claim that a release-complete core-backed patch has passed the required pristine-source build and equivalence tests.

## Start here

- `docs/VERSIONS.md` — release/version meaning and compatibility baseline.
- `docs/BEHAVIOR.md` — exact user-visible behavior and configuration semantics.
- `docs/CONFIGURATION.md` — parser contract, aliases, compiled fallbacks, and reload behavior.
- `docs/ARCHITECTURE.md` — boundary between the shared engine and libinput integration.
- `docs/CORE_MIGRATION.md` — function-level plan for replacing the 0.0.14 inline algorithms with the submodule APIs.
- `docs/BUILD_AND_INSTALL.md` — pinned-source build/install workflow.
- `docs/DEVICE_SETUP.md` — device classification and udev details.
- `docs/DEBUGGING_AND_MAINTENANCE.md` — traps, validation rules, and operational checks.
- `docs/PROJECT_RULES.md` — contribution and documentation conventions.

## Repository status

The shared engine has been extracted into `core/`. Version 0.0.14 is preserved as the working compatibility reference while 0.1.0 is the core-backed integration line. Production 0.1.0 patch work must be generated against the pristine pinned source and must pass a real build; do not fabricate a replacement patch by reconstructing old hunks from prose.

The helper below exposes the pinned core checkout to a libinput source tree as a Meson subproject without copying it:

```bash
sh ./tools/link-core-subproject.sh /path/to/libinput-source
```

## Documentation rule

Important decisions made in discussions must also be recorded in these repositories so they remain usable without chat history. Porting handoff documents are the sole intended exception; any durable technical conclusion that affects this repository still belongs here.
