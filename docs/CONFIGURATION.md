# Runtime configuration

## File and load timing

The integration reads:

```text
/etc/libinput/trackpoint-scroll.conf
```

once when each eligible TrackPoint device is initialized. There is no live reload.

For configuration-only changes, replug a removable device or restart the graphical session for a built-in device. After installing a rebuilt library, restart the session so the compositor maps the new shared object, then verify the mapped Build ID when runtime identity matters.

## Recommended configuration versus compiled fallback

The recommended tested file selects:

```ini
profile=hyperbolic
```

The current integration's **compiled fallback profile**, used when no valid `profile=` override is read, is `adaptive`. These are intentionally distinct facts. The core library itself does not choose an integration profile; profile selection is adapter policy.

Other compiled/current defaults include:

```ini
clamp_negative_output=false
suppress_middle_click=true
first_step_distance=0.4
first_step_axis_merge_ms=70.0
first_step_max_reports=-1
idle_reset_ms=333.3
```

The complete recommended file is `config/trackpoint-scroll.conf.example`.

## Syntax

The parser is deliberately small and case-sensitive:

- `key=value` entries;
- leading/trailing whitespace is trimmed;
- `#` begins an inline comment;
- blank lines are ignored;
- lines whose first non-space character is `;` or `[` are ignored;
- unknown keys are logged and ignored;
- malformed and nonfinite numbers are rejected;
- the line buffer is 256 bytes.

Accepted boolean true values:

```text
true
yes
on
1
```

Accepted boolean false values:

```text
false
no
off
0
```

`first_step_distance`, `first_step_axis_merge_ms`, and `idle_reset_ms` must be finite and nonnegative.

`first_step_max_reports` is a signed integer:

```text
>0  finite accepted-report quota
 1  first report only
 0  disable fixed startup behavior
<0  unlimited within the merge-time window
```

## Profile names

Canonical names:

```text
affine
quadratic
adaptive
hyperbolic
```

Accepted aliases:

```text
linear               -> affine
flat                 -> affine
asymptotic           -> hyperbolic
asymptotic-linear    -> hyperbolic
```

No compatibility alias exists for retired incorrect profile terminology. Do not reintroduce one.

## Parameter names and aliases

Canonical memoryless parameters:

```text
affine_k
affine_b
quadratic_a
quadratic_h
quadratic_k
hyperbolic_a
hyperbolic_u
hyperbolic_k
```

Accepted aliases:

```text
linear_k             -> affine_k
flat_k               -> affine_k
linear_b             -> affine_b
flat_b               -> affine_b
asymptotic_a         -> hyperbolic_a
asymptotic_u         -> hyperbolic_u
asymptotic_k         -> hyperbolic_k
```

Adaptive controls:

```text
adaptive_velocity_scale
adaptive_sensitivity
adaptive_speed
```

`adaptive_velocity_scale=0` is invalid for the wrapper and is replaced with its compiled default. Invalid adaptive speed falls back to the compiled default speed.

## Output clamping

`clamp_negative_output=false` preserves negative scalar memoryless-profile results, which reverses vector direction. `true` clamps such output to zero.

For the adaptive wrapper, clamping also suppresses a negative sensitivity rather than intentionally reversing the filter output.

The fixed startup step is sign-based and does not use this sustained-profile clamp.

## Middle-click suppression

```ini
suppress_middle_click=true
```

suppresses the deferred no-scroll middle-button press/release pair on the custom TrackPoint button-scroll path. It does not disable middle-button scrolling. Set it to `false` to restore the ordinary no-scroll click fallback.
