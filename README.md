# libinput-trackpoint-scroll

A libinput integration for responsive TrackPoint middle-button scrolling, built around the shared `trackpoint-scroll-core` submodule.

The project targets one pinned source revision:

```text
libinput 1.31.0
659967488e1e66d7fb7210c6b86860c8e1e5bed4
```

The currently deployed behavior was validated over weeks of daily use. Its essential properties are:

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

## Start here

- `docs/BEHAVIOR.md` — exact user-visible behavior and configuration semantics.
- `docs/ARCHITECTURE.md` — boundary between the shared engine and libinput integration.
- `docs/BUILD_AND_INSTALL.md` — pinned-source build/install workflow.
- `docs/DEVICE_SETUP.md` — device classification and udev details.
- `docs/DEBUGGING_AND_MAINTENANCE.md` — traps, validation rules, and operational checks.
- `docs/PROJECT_RULES.md` — contribution and documentation conventions.

## Repository status

The shared engine has been extracted into `core/`. The deployed v14 patch predates that extraction and is the behavioral reference while the integration is rewritten to call the submodule. Do not fabricate a replacement patch by reconstructing hunks from documentation: new production patches must be generated against the pristine pinned source and must pass a real build.

## Documentation rule

Important decisions made in discussions must also be recorded in these repositories so they remain usable without chat history. Porting handoff documents are the sole intended exception; any durable technical conclusion that affects this repository still belongs here.
