# Current behavior

## Recommended configuration

```ini
profile=hyperbolic
clamp_negative_output=false
suppress_middle_click=true

first_step_distance=0.4
first_step_axis_merge_ms=70.0
first_step_max_reports=-1
idle_reset_ms=333.3

affine_k=0.4
affine_b=0.0

quadratic_a=0.16
quadratic_h=0.0
quadratic_k=0.025

adaptive_velocity_scale=100.0
adaptive_sensitivity=1.086
adaptive_speed=0.0

hyperbolic_a=0.75
hyperbolic_u=1.6
hyperbolic_k=-1.175
```

The runtime file is `/etc/libinput/trackpoint-scroll.conf` and is read once per TrackPoint device initialization.

## Gesture lifecycle

The scroll button is the middle button. The normal libinput button-scroll timeout is reduced from about 200 ms to 1 ms.

With `suppress_middle_click=true`, pressing and releasing the middle button without scrolling emits no public middle-click press/release pair. Scrolling itself is unchanged. Set the option to `false` to restore the ordinary deferred click fallback.

No public middle-button press is emitted while the gesture is unresolved, so suppression does not create an unmatched button state.

## Startup micro-step

After a new middle-button gesture, or after a raw-motion gap strictly greater than `idle_reset_ms`, early reports enter the fixed-step startup window.

For each axis, raw magnitude is discarded and only sign matters:

```text
positive component -> +first_step_distance
zero component     -> 0
negative component -> -first_step_distance
```

At the default distance 0.4:

```text
( 1, 0) -> ( 0.4,  0.0)
( 0, 2) -> ( 0.0,  0.4)
( 1, 1) -> ( 0.4,  0.4)
( 7,-3) -> ( 0.4, -0.4)
```

This fixed output bypasses the sustained acceleration profile and is queued for the next 2 ms tick; the implementation does not wait for the merge window to close before producing visible motion.

The merge window begins at the first raw motion report, not at middle-button press and not as a rolling deadline.

### Coalescing and report limit

A previously unseen axis can add one fixed component during the merge window. Repeated same-sign reports do not add another component.

`first_step_max_reports` semantics:

```text
N > 0   at most N accepted reports participate
N = 1   only the first report receives fixed-step treatment
N = 0   disable the fixed startup step; use the normal profile path
N < 0   unlimited accepted reports within the merge-time window
```

The default is `-1`; therefore the 70 ms time window, not report count, bounds startup coalescing.

Consumed startup reports are not replayed into the sustained profile later. Their timestamps still establish the interval to the first later profile-governed report.

### Startup rebound

Within the merge window, an opposite-sign component on an already represented axis is treated as immediate mechanical rebound and ignored. A rebound-only report does not consume a finite report quota. In a mixed report, the rebound component is discarded while a new or surviving component follows the ordinary startup/quota rules.

This is intentionally scoped to startup. Deliberate reversals after the merge window are normal input.

## Sustained reconstruction

After startup, raw displacement is reconstructed causally on a fixed 2 ms grid before nonlinear mapping.

Current constants:

```text
logical grid period:          2 ms
initial interval estimate:  240 ms
measured interval clamp:  10..250 ms
interval history:             5 samples, median
idle reset:                 333.3 ms
```

For raw displacement `d`, estimated report interval `T`, and grid period `h`:

```text
N = round(T / h)
share = d / N
```

Each report contributes the same share for `N` logical ticks. Overlapping reports add linearly. Before acceleration, the shares sum to the original displacement unless an explicit release/reset cancels the finite remaining tail.

No emitted share is revised after later input arrives. There is no predicted trajectory, correction reservoir, repayment, or momentum model.

## Sustained profiles

Memoryless profiles operate radially: compute vector magnitude `x`, map it to output magnitude `y`, then restore the original vector direction. Exact zero input produces exact zero output.

### Affine

```text
y = k*x + b
```

Default: `k=0.4`, `b=0.0`. The zero intercept is intentional: a positive affine offset overshot under the lightest force.

### Quadratic

```text
y = a*(x-h)^2 + k
```

Default: `a=0.16`, `h=0`, `k=0.025`.

### Hyperbolic

```text
y = a*sqrt(u^2 + x^2) + k
```

Default: `a=0.75`, `u=1.6`, `k=-1.175`.

At `x=2.5`, the affine, quadratic, and hyperbolic defaults produce approximately `1.000`, `1.025`, and `1.051` respectively.

### Adaptive

The adaptive profile uses a dedicated upstream TrackPoint adaptive filter with separate state from cursor acceleration. The current wrapper scales input by `adaptive_velocity_scale`, runs the filter at `adaptive_speed`, then scales output by `adaptive_velocity_scale * adaptive_sensitivity`.

The calibrated defaults produce approximately magnitude 1 at input magnitude 2.5 for a TrackPoint multiplier of 1. A device-specific multiplier changes exact calibration.

### Negative output

With `clamp_negative_output=false`, a negative scalar profile result reverses vector direction. With `true`, negative memoryless output is clamped to zero. For the adaptive profile, a negative sensitivity is suppressed when clamping is enabled.

## Free and locked modes

Free mode is the default. It sends accelerated two-dimensional output directly to the continuous-axis notifier, bypassing generic buildup and axis locking.

Locked mode feeds accelerated output through `evdev_post_scroll()`, retaining libinput's ordinary buildup/direction/axis-lock behavior.

### Shift ordering

- Shift already held before middle remains visible to applications and does not toggle the gesture.
- A fresh Shift press after middle toggles the current gesture between free and locked mode and is consumed.
- The matching Shift release is also consumed.
- Repeated press events for an already consumed Shift remain consumed but do not repeatedly toggle.

A mode switch ends an already public scroll sequence if needed, cancels pending timer work, resets generic buildup/direction state, discards pre-switch reconstruction, and restarts stateful acceleration history. Only post-switch motion contributes to the new mode.

### Scroll Lock

A fresh physical Scroll Lock press toggles the default mode for subsequent middle-button gestures. It remains visible to normal software and keyboard LEDs. Auto-repeat does not repeatedly toggle the custom state.

The default is latched when middle is pressed; changing Scroll Lock during an active gesture does not retroactively alter that gesture.

```text
custom Scroll Lock state off:
  middle + motion       -> free
  middle then Shift     -> locked

custom Scroll Lock state on:
  middle + motion       -> locked
  middle then Shift     -> free
```

## Stop and public-sequence bookkeeping

The implementation records whether scroll output actually reached a public notifier. This matters because locked-mode buildup can suppress early deltas. Stop events are emitted only for a sequence that actually became public.

Physical middle-button release cancels remaining reconstructed tail immediately. Prompt stop is preferred over preserving unexpired pre-acceleration displacement after release.
