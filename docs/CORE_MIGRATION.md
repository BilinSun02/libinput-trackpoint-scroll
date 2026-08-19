# Core migration

## Goal

The deployed v14 behavior remains the reference while reusable motion processing moves out of the large `src/evdev.c` patch body. The migration should reduce the libinput patch to an adapter around the `core/` API rather than maintain two copies of the startup/reconstruction/profile algorithms.

This is a structural refactor first. Behavioral changes should be separate and opt-in so a regression can be attributed cleanly.

## Build linkage

The integration repository pins the exact shared revision as the `core/` git submodule. For a libinput source checkout, expose that checkout to Meson under:

```text
subprojects/trackpoint-scroll-core
```

The helper does this with a symlink rather than copying source:

```bash
./tools/link-core-subproject.sh /path/to/libinput-source
```

The shared `meson.build` defines `core_dep`; the libinput Meson patch should obtain that dependency from the subproject and link it into the library target. This keeps the source of the reusable engine single and makes the recorded gitlink part of build reproducibility.

A production build should fail clearly when the expected subproject is absent rather than silently fall back to a duplicated implementation.

## Function-level migration map

### Move to core API calls

The inline v14 equivalents of these responsibilities should disappear from the libinput patch after migration:

```text
first-step sign tracking
first-step report count/window logic
startup rebound filtering
interval-history median
2 ms pending/active/removal ring
raw-share lifetime accounting
affine scalar mapping
quadratic scalar mapping
hyperbolic scalar mapping
memoryless negative-output clamp
```

Libinput should feed raw timestamped vectors to `tpsc_engine_feed()` and obtain output from `tpsc_engine_tick()`.

### Keep in the libinput adapter

```text
button-scroll route selection
1 ms click-versus-scroll timer transition
runtime text config parser
profile-name and compatibility aliases
adaptive-filter object and calibration wrapper
libinput timer scheduling
free/locked mode selection
continuous-axis notification
evdev_post_scroll() locked path
public posted/stop bookkeeping
post-middle Shift consumption
Scroll Lock default toggle
no-scroll middle-click suppression
TrackPoint device initialization/destruction
```

## Suggested integration state

The large v14 `evdev_scroll_grid` structure should shrink to adapter state similar in responsibility to:

```text
core engine pointer
logical-timer-active flag
public-posted flag
free/locked mode bit
integration profile/adaptive state
```

Do not mirror core ring slots, interval history, startup signs, or startup report counters in `evdev.h` after migration.

A forward declaration of the opaque core engine is preferable in broad internal headers when possible; include the full core API only in implementation files that call it.

## Configuration translation

The text parser remains here because the path and accepted names are integration policy.

At device initialization:

1. start with `tpsc_engine_config_defaults()`;
2. parse startup keys and override the corresponding core configuration fields;
3. parse the selected profile and its parameters;
4. install one integration transform callback into the core config;
5. create the core engine;
6. create the adaptive filter independently when adaptive support is available.

The transform callback should dispatch as follows:

- affine/quadratic/hyperbolic: call the corresponding shared profile implementation;
- adaptive: run the dedicated libinput TrackPoint filter and apply the current scale/sensitivity wrapper.

The reset callback should restart adaptive velocity history. It may be a no-op for memoryless profiles.

This preserves one core engine regardless of selected profile while keeping host-owned stateful acceleration outside the shared library.

## Timer translation

The current `device->scroll.timer` can continue to schedule logical ticks. The adapter should obtain the logical period from `tpsc_engine_tick_us()` rather than duplicate the 2 ms constant.

Each timer firing should:

1. call `tpsc_engine_tick()` with the current timestamp;
2. route the returned vector through free or locked posting;
3. set `posted` only at the final public notifier;
4. schedule another tick while `tpsc_engine_needs_ticks()` is true.

A zero-output cleanup tick is valid: expiration occurs before pending activation in the causal ring semantics, so the final bookkeeping tick may produce zero while clearing the last live contribution.

## Gesture and reset translation

- Middle gesture start: call `tpsc_engine_begin()` before accepting motion.
- Physical release: call `tpsc_engine_end()` and cancel timer work; do not drain the remaining tail.
- Idle rearm is owned internally by the core feed logic.
- Mode switch: end/reset the old core sequence, discard old-policy shares, reset libinput buildup/direction, then begin a fresh core sequence for post-switch motion.

The startup merge window begins on the first raw report after begin/reset, not at middle-button press itself.

## Equivalence tests before replacing v14

Before a core-backed patch supersedes v14, replay deterministic raw traces through both implementations where feasible and compare:

- first-step output for `(1,0)`, `(0,1)`, `(1,1)`, larger-magnitude startup reports;
- split-axis reports inside 70 ms;
- startup rebound cases;
- transition at the merge-window boundary;
- sustained identity-transform conservation;
- overlapping sparse reports;
- affine/quadratic/hyperbolic transformed output;
- idle rearm at 333.3 ms;
- explicit release cancellation;
- mode-switch reset behavior.

Then run the real libinput integration build and interactive free/locked/Shift/Scroll-Lock/middle-suppression checks. Core unit tests are necessary but do not substitute for the host build.
