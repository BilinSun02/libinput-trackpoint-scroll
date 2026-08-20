# Core migration

## Goal and current status

The 0.0.14 behavior is the compatibility reference while reusable motion processing moves out of the large `src/evdev.c` patch body.

A first core-backed **0.1.0 candidate is implemented and host-buildable**. It reduces the libinput patch to an adapter around the `core/` API rather than maintaining two copies of startup/reconstruction/memoryless-profile algorithms.

This remains a structural refactor first. Behavioral changes should be separate and opt-in so a regression can be attributed cleanly.

Candidate identifiers:

```text
core gitlink:
133df50ea5ce58e71e3fed3240c26999ee689386

uncompressed base-patch SHA-256:
8a2149667755545fa8ff7b378de839bfb90e0728ed01cddfcabf03e3fa17c016
```

The current corrected candidate is the base patch plus the documented Meson and timestamp-boundary corrections managed by `tools/prepare-libinput-tree.sh`. These temporary corrections should be folded into the canonical 0.1.0 patch before final release packaging.

## Build linkage

The integration repository pins the exact shared revision as the `core/` git submodule. For a libinput source checkout, expose that checkout to Meson under:

```text
subprojects/trackpoint-scroll-core
```

The helper does this with a symlink rather than copying source:

```bash
sh ./tools/link-core-subproject.sh /path/to/libinput-source
```

The shared `meson.build` defines `core_dep`; the 0.1.0 libinput patch obtains that dependency from the subproject and adds it to `deps_libinput`.

A production build should fail clearly when the expected subproject is absent rather than silently fall back to a duplicated implementation.

## Ownership after extraction

### Provided by core

The 0.1.0 candidate no longer carries inline libinput copies of:

```text
first-step sign tracking
first-step report count/window logic
startup rebound filtering
interval-history median
logical pending/active/removal ring
raw-share lifetime accounting
affine scalar mapping
quadratic scalar mapping
hyperbolic scalar mapping
memoryless negative-output clamp/non-finite containment
```

Libinput feeds timestamped vectors to `tpsc_engine_feed()` and obtains output from `tpsc_engine_tick()`.

### Retained in the libinput adapter

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

## Integration state

The old large `evdev_scroll_grid`/inline-accelerator state has been replaced with an integration-owned pointer state whose responsibilities are approximately:

```text
core engine pointer + core configuration
selected profile and portable memoryless-profile parameters
integration-owned adaptive filter and parameters
logical-timer-active flag
raw-input timestamp used for host scheduling equivalence
public-posted flag
free/locked mode bit
gesture-active state
middle-click suppression policy
```

Core ring slots, interval history, startup signs, and startup report counters are not mirrored in `evdev.h`.

## Timestamp boundary

Upstream libinput deliberately defines `usec_t` as a strong newtype while the reusable core deliberately accepts plain `uint64_t` microsecond timestamps. The real host compile exposed adapter sites where implicit conversion was invalid.

The durable rule is:

```text
libinput usec_t -> core uint64_t: usec_as_uint64_t(...)
core uint64_t -> libinput usec_t: usec_from_uint64_t(...)
```

Do not change the core API to use libinput's `usec_t`. Commit-specific source-shape expectations for these conversion families live under `compat/libinput/<LIBINPUT_COMMIT>/` and are validated structurally by `tools/fix-0.1.0-usec-boundary.py`.

## Configuration translation

The text parser remains here because the path and accepted names are integration policy.

At device initialization the 0.1.0 candidate:

1. calls `tpsc_engine_config_defaults()`;
2. parses startup keys into the core configuration;
3. parses profile selection/parameters;
4. initializes portable affine/quadratic/hyperbolic `tpsc_profile` structures;
5. creates the integration-owned adaptive filter;
6. installs an integration transform callback/reset callback in the core config;
7. creates the core engine.

The transform callback dispatches as follows:

- affine/quadratic/hyperbolic: `tpsc_profile_apply()`;
- adaptive: dedicated upstream TrackPoint filter plus the existing scale/sensitivity wrapper.

The reset callback restarts adaptive velocity history. For memoryless profiles the reset has no additional state to clear.

## Timer translation

The existing `device->scroll.timer` continues to schedule logical ticks. The adapter obtains the logical period from `tpsc_engine_tick_us()` rather than duplicating the 2 ms constant.

Each core timer firing:

1. calls `tpsc_engine_tick()`;
2. routes the returned vector through free or locked posting;
3. sets `posted` only at the final public notifier;
4. schedules another tick while `tpsc_engine_needs_ticks()` is true.

A zero-output cleanup tick is valid: expiration occurs before pending activation in the causal ring semantics, so the final bookkeeping tick may produce zero while clearing the last live contribution.

### Idle-rearm scheduling subtlety

The core owns the logical idle rearm decision. The libinput adapter nevertheless tracks the previous raw-report timestamp for one host-specific reason: if a configured idle reset occurs while an old libinput timer is still scheduled, the adapter cancels that host timer before feeding the new report so the new burst's first logical tick is scheduled relative to the new report. This preserves the 0.0.14 scheduling behavior even with unusually small configured idle thresholds.

That raw timestamp is adapter scheduling state, not a duplicate core interval estimator.

## Gesture and reset translation

- Middle gesture start: call `tpsc_engine_begin()` before accepting motion.
- Physical release: call `tpsc_engine_end()` and cancel timer work; do not drain the remaining tail.
- Idle rearm is owned internally by the core feed logic.
- Mode switch: stop an already public sequence if necessary, cancel timer work, reset libinput buildup/direction, then call `tpsc_engine_restart(engine, time, TPSC_RESTART_BYPASS_STARTUP)`.

The bypass restart is important for behavioral equivalence with 0.0.14. A mode switch discards pre-switch shares and resets stateful transform history, but it does **not** turn the first post-switch motion report into another fixed startup step. That next report enters sustained reconstruction directly, with its first interval measured from the mode-switch timestamp.

`TPSC_RESTART_REARM_STARTUP` remains available for higher-level policies that deliberately want a new startup episode without ending the surrounding gesture; it is not used for the current Shift mode switch.

For a normal gesture start or idle-rearmed burst, the startup merge window begins on the first raw motion report, not at middle-button press itself.

## Validation performed

The 0.1.0 candidate has undergone:

- core strict C11 tests;
- core AddressSanitizer/UndefinedBehaviorSanitizer runs;
- standalone deterministic comparison between the 0.0.14 reference algorithm and the shared engine for affine, quadratic, and hyperbolic traces;
- startup fixed-step and split-axis cases;
- startup rebound cases;
- startup-to-sustained transition;
- overlapping sparse reports;
- idle rearm at 333.3 ms;
- explicit release/tail cancellation in core tests;
- mode-switch restart with no new startup step;
- non-finite memoryless-profile containment;
- complete-patch apply and whitespace checks;
- strict mock-host C syntax checking of the integration-owned block;
- real Meson configuration against the pinned libinput checkout;
- real Ninja compilation after fixing the explicit timestamp type boundary;
- verified installation with the `ldconfig` cache Build ID matching the build artifact;
- a fresh normal graphical boot after that installation;
- post-reboot live process mappings whose `libinput.so.10` Build ID matches the build artifact;
- basic interactive scrolling working in that verified session.

## Validation still useful before calling 0.1.0 fully field-tested

The core-backed build is no longer merely compile-tested: it has completed a real verified runtime boot. The remaining distinction from the long-used 0.0.14 baseline is depth of field testing, not whether the integration can build or start.

Before treating 0.1.0 as equally field-tested, re-exercise the full integration-owned behavior matrix explicitly:

```text
free scrolling
locked scrolling
post-middle Shift toggle in both directions
Shift held before middle remains visible/non-toggle
Scroll Lock default-mode toggle and latching
middle-click suppression true/false
release/tail cancellation
adaptive profile reset behavior if adaptive is used
```

Also fold the temporary Meson/timestamp corrections into the canonical 0.1.0 replacement patch and regenerate its release checksums before final release packaging.
