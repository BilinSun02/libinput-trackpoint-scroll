# Architecture

## Ownership boundary

The `core/` submodule owns deterministic timestamped motion processing:

- startup fixed-step semantics;
- split-axis coalescing and scoped startup rebound handling;
- idle rearming;
- interval estimation;
- causal fixed-time reconstruction;
- built-in memoryless affine/quadratic/hyperbolic profiles;
- transform/reset extension points.

This repository owns the libinput adapter around that engine:

- selecting eligible TrackPoint button-scroll devices;
- button-scroll lifecycle and the 1 ms activation timeout;
- translating `usec_t` and libinput coordinate structures to/from core types;
- timer scheduling;
- runtime config parsing;
- the upstream adaptive-profile wrapper;
- free versus locked event posting;
- Shift/Scroll Lock policy and cross-device keyboard bookkeeping;
- no-scroll middle-click suppression;
- stop-event/public-post bookkeeping;
- device initialization/destruction and failure handling.

Keep that boundary explicit. Do not duplicate core algorithms in the integration after migration.

## Intended data path

```text
raw REL_X / REL_Y during middle-button scrolling
        |
        v
libinput adapter
        |
        | timestamp + raw relative displacement
        v
core engine
        |
        | fixed startup output and/or reconstructed 2 ms vector
        v
transform
        |- core memoryless profile, or
        `- integration-owned adaptive wrapper
        |
        v
libinput adapter
        |- free: direct continuous-axis notifier
        `- locked: evdev_post_scroll() buildup/axis lock
```

The core's `tick_us` is a logical period. The libinput adapter may continue using `device->scroll.timer`, but scheduling mechanics must not leak into the core API.

## Adapter state that remains integration-specific

### Gesture routing

The custom path is selected only when the device is tagged as a TrackPoint and configured for scroll-on-button-down. Other pointer paths remain unchanged.

### Keyboard policy

Current implementation state is process-global:

- one current TrackPoint Shift target;
- one Scroll Lock default-mode bit;
- a fixed table of 16 consumed Shift entries keyed by keyboard device and keycode.

This permits a keyboard separate from the pointing device but is not a general simultaneous-multi-gesture/per-seat design. A future cleanup may make this seat-scoped, but it must preserve ordering semantics.

### Locked mode

Locked mode deliberately delegates to `evdev_post_scroll()` rather than duplicating its buildup/axis-lock algorithm. Free mode deliberately bypasses that path.

### Adaptive transform

The adaptive profile is currently backed by libinput's TrackPoint accelerator and velocity history. It should be presented to the core through the stateful transform callback/reset interface. Do not copy host filter internals into the core merely to make every profile live in one repository.

## Refactor rules

- Core types must be translated at the adapter boundary; do not add libinput types to core headers.
- Keep the shared engine opaque.
- Do not make the core parse `/etc/libinput/trackpoint-scroll.conf`; parse here and fill a core config/profile structure.
- Reset stateful transforms wherever the core signals a burst/gesture reset.
- Preserve the existing public-post bookkeeping around locked-mode buildup.
- Preserve release cancellation semantics.
- Preserve the existing internal spelling `evdev_notify_axis_continous` at call sites unless the upstream symbol itself is changed consistently.

## Current migration state

The deployed v14 patch contains the algorithms inline in `src/evdev.c`. The first refactor milestone extracts those reusable algorithms into `core/`; the next integration patch should replace the duplicated inline startup/grid/memoryless-profile implementation with core API calls while leaving libinput-specific policy here.

Do not produce a production patch by editing or reconstructing old hunk text from prose. Start from the pristine pinned source, apply deliberate integration changes, and compile the result.
