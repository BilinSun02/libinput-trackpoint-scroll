# Debugging and maintenance

## Do not infer compositor settings from standalone tools

`libinput list-devices` and `libinput debug-events` create their own libinput contexts. Their displayed defaults are not the live GNOME/Mutter pointing-stick preferences.

Use `gsettings` for GNOME's live configuration. When testing `debug-events`, supply explicit options as needed.

## Prove the execution path before tuning

A major earlier debugging lesson was that plausible public output does not prove the intended internal path is active. For routing problems, instrument boundaries explicitly:

1. route selection in the button-scroll motion path;
2. raw feed into the shared engine;
3. logical timer/tick execution;
4. transformed output before posting;
5. the final public notifier.

Useful fields include device, timestamp, state, raw vector, estimated interval, tick count, reconstructed vector, transformed vector, and whether public output was posted.

Do not tune transfer-function constants while the loaded library or execution route is uncertain.

## Cursor and scroll acceleration are independent

An earlier implementation accidentally attached scrolling behavior to a particular pointer profile. The final architecture uses a dedicated scrolling transform. GNOME's pointing-stick `accel-profile` and speed affect cursor behavior, not the custom sustained scroll profile.

## Application-level scaling differs

A system-level continuous scroll delta is not guaranteed to represent identical visible distance in every toolkit/application.

On the tested desktop, GNOME Papers was used as the reference application. Firefox felt substantially faster and was brought close with:

```text
mousewheel.default.delta_multiplier_x = 50
mousewheel.default.delta_multiplier_y = 50
```

The Z multiplier is irrelevant to ordinary X/Y scrolling. Exact visual equivalence is not expected because toolkit and application paths scale continuous scrolling differently.

Tune the shared/libinput transform using a stable reference application, then treat application-specific corrections separately.

## Raw-input evidence and hypotheses

Low-force sparse timing, not hand jitter, is the primary demonstrated problem. Do not add broad sustained reversal gates, hand-jitter filters, recalibration detectors, or prediction machinery without a controlled residual failure that requires them.

Immediate opposite-sign startup rebound is a narrow, evidence-backed exception and remains confined to the startup merge window.

## Approaches not to revive casually

- long attack/release low-pass constants: produced lag, buildup, overshoot, and momentum-like behavior;
- mutable trajectory prediction plus later correction: produced repayment/reversal artifacts;
- cumulative telescoping against a revisable target: mathematically conservative only for a fixed target;
- nonlinear acceleration before temporal regularization: makes behavior depend on hardware packetization;
- assuming one downstream accumulation mechanism explained all jumps: bypassing it alone did not fix the sparse-timing problem.

## Internal API caveats

The internal notifier is named `evdev_notify_axis_continous` in the pinned tree. Do not locally "correct" the spelling at custom call sites unless the symbol itself is changed consistently.

A previous custom helper named `normalized_length` collided with an existing libinput helper. Namespace integration helpers to avoid repeating this class of failure.

## Runtime config parser conventions

`/etc/libinput/trackpoint-scroll.conf` is a simple case-sensitive `key=value` file:

- leading/trailing whitespace is trimmed;
- `#` begins an inline comment;
- blank lines are ignored;
- lines beginning (after trim) with `;` or `[` are ignored;
- unknown keys are logged and ignored;
- nonfinite numeric values are rejected;
- boolean true values: `true`, `yes`, `on`, `1`;
- boolean false values: `false`, `no`, `off`, `0`;
- line buffer is 256 bytes.

`first_step_distance`, `first_step_axis_merge_ms`, and `idle_reset_ms` must be finite and nonnegative. `first_step_max_reports` is signed and follows the semantics documented in `BEHAVIOR.md`.

## Operational rollback

Set:

```ini
suppress_middle_click=false
```

to restore ordinary no-scroll middle-click fallback without disabling TrackPoint scrolling.
