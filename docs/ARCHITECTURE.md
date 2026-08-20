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
- translating libinput `usec_t` and coordinate structures to/from core types;
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
        | uint64_t microseconds + raw relative displacement
        v
core engine
        |
        | fixed startup output and/or reconstructed logical-tick vector
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

The core's `tick_us` is a logical period. The libinput adapter continues using `device->scroll.timer`; host scheduler mechanics do not leak into the core API.

## Timestamp type boundary

Upstream libinput deliberately uses the strong `usec_t` newtype while the portable core deliberately uses plain `uint64_t` microsecond timestamps. The adapter converts explicitly at every boundary:

```text
libinput -> core: usec_as_uint64_t(...)
core -> libinput: usec_from_uint64_t(...)
```

Do not move `usec_t` into the core API merely to silence host compile errors. The strong type is useful because it catches missing adapter conversions.

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

The adaptive profile is backed by libinput's TrackPoint accelerator and velocity history. It is presented to the core through the stateful transform callback/reset interface. Host filter internals remain outside the core.

## Refactor rules

- Core types must be translated at the adapter boundary; do not add libinput types to core headers.
- Keep the shared engine opaque.
- Do not make the core parse `/etc/libinput/trackpoint-scroll.conf`; parse here and fill core configuration/profile structures.
- Reset stateful transforms wherever gesture/burst policy requires it.
- Preserve public-post bookkeeping around locked-mode buildup.
- Preserve release cancellation semantics.
- Preserve the existing internal spelling `evdev_notify_axis_continous` at call sites unless the upstream symbol itself is changed consistently.

## Current migration state

The historical 0.0.14/v14 patch contains startup/reconstruction/memoryless-profile algorithms inline in `src/evdev.c` and remains the behavioral reference.

The 0.1.0 candidate has completed the extraction milestone: the reusable implementation comes from the pinned `core/` submodule, while libinput-specific policy remains in the adapter. The candidate has successfully configured and compiled against the pinned real libinput tree and has booted a fresh graphical session with the built library verified by ELF Build ID in both the loader cache and live process mappings.

This does not make every future change safe automatically. Production patches must still be regenerated/validated against the pristine pinned upstream tree, and runtime identity must be proven rather than inferred from installation success alone.
