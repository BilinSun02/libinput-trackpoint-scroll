# Host runtime validation

This checklist covers the libinput/GNOME behavior that is not proven by the shared core tests. Run it only after a fresh graphical-session start or reboot with the intended build installed.

## 1. Prove the running binary

```bash
sudo sh ./tools/verify-runtime-libinput.sh
```

Required result: cache identity and observed live mappings match the build artifact's ELF Build ID.

Do not credit any behavioral observation to the candidate until this passes.

## 2. Default free scrolling and release cancellation

With the normal recommended configuration and custom Scroll Lock state off:

1. Hold middle and move the TrackPoint diagonally in content that can scroll in both axes.
2. Confirm both axes can move without generic axis locking.
3. Produce a reasonably strong movement and release middle while reconstructed work could still remain.
4. Confirm scrolling stops promptly on release; there is no continuing tail or momentum.

Pass criteria: immediate two-dimensional free scrolling and prompt stop on release.

## 3. Shift held before middle

1. Hold Shift before pressing middle.
2. Start scrolling while continuing to hold Shift.

Pass criteria:

- the gesture keeps its normal default mode; pre-held Shift does not toggle it;
- Shift remains an ordinary visible key to applications rather than becoming a consumed post-middle toggle.

## 4. Fresh Shift after middle

Shift is a **toggle**, not a hold-to-select modifier. Its press changes the current gesture mode; releasing that same Shift key is consumed but does not undo the toggle.

1. Start a middle-button gesture in the default free mode.
2. Press Shift only after middle is down, either before the first motion or during scrolling.
3. Continue moving and confirm the gesture is now locked.
4. Release that same Shift key while keeping middle held.
5. Continue moving: the gesture must remain locked after Shift is released.
6. Press Shift freshly a second time while the same middle gesture is still active; the gesture must toggle back to free. Release Shift again; it must remain free.

Pass criteria:

- each fresh post-middle Shift press toggles the current gesture between free and locked;
- a matching Shift release is consumed but never toggles the mode;
- locked mode exhibits libinput's ordinary buildup/direction/axis-lock behavior rather than unrestricted two-dimensional output;
- free mode restores unrestricted two-dimensional output;
- a switch does not emit another fixed startup micro-step; post-switch motion resumes through sustained reconstruction.

Repeat once with the gesture starting locked (see Scroll Lock below) if desired; the first fresh post-middle Shift press must toggle it to free.

## 5. Scroll Lock default and latching

1. With no active middle gesture, press Scroll Lock once.
2. Confirm the key remains visible normally (and the keyboard LED changes where hardware exposes one).
3. Start a new middle gesture.
4. Confirm its default is now locked.
5. During an active gesture, press Scroll Lock again and keep scrolling.
6. End the gesture and start another one.

Pass criteria:

- a fresh Scroll Lock press changes the default for later gestures;
- Scroll Lock itself is not consumed from normal software/LED handling;
- an active gesture keeps the mode latched at middle press;
- the changed default takes effect only on the next gesture.

Restore the preferred custom Scroll Lock state when finished.

## 6. Middle-click suppression enabled and disabled

With the normal recommended setting:

```ini
suppress_middle_click=true
```

press and release middle without motion on something with an obvious middle-click action, for example a browser link.

Pass criterion: no ordinary middle click is delivered, while middle-button scrolling still works.

Then temporarily set:

```ini
suppress_middle_click=false
```

Reinitialize the removable TrackPoint (replug it), repeat the no-motion middle click, and confirm the ordinary deferred middle click is delivered. Restore `true` and replug again afterward.

## 7. Adaptive state reset

This check concerns the integration-owned **state reset**, not whether adaptive feels dramatically different from affine/quadratic/hyperbolic. Similar overall response between profiles is neither a pass nor a failure.

The manual adaptive comparison on the verified 0.1.0 runtime was inconclusive because the adaptive-state effect was not clearly perceptible. The required reset wiring was therefore checked directly in the exact source used for that build.

The integration registers:

```text
core_config.transform.reset = evdev_trackpoint_scroll_transform_reset
```

and that callback calls:

```text
filter_restart(state->adaptive.filter, state->device, time)
```

when the adaptive filter exists.

The shared engine invokes its registered transform reset from all relevant boundaries:

- `tpsc_engine_begin()` — gesture start;
- `tpsc_engine_end()` — gesture end;
- `tpsc_engine_restart()` — in-gesture restart, including the Shift mode switch with `TPSC_RESTART_BYPASS_STARTUP`;
- `begin_burst()` — first input of a burst and idle rearm after a gap exceeding `idle_reset_ms`.

Thus the adapter-to-core reset path is structurally complete for gesture, mode-switch, and idle-reset boundaries. The perceptual adaptive comparison is retained only as an optional smoke test; it is not required to distinguish profiles by feel.

## Current 0.1.0 host observations

On the verified core-backed runtime session:

```text
runtime Build-ID verification: PASS
free + release cancellation:   PASS
Shift-before-middle:           PASS
post-middle Shift toggle:      PASS
Scroll Lock/latching:          PASS
middle suppression true/false: PASS
adaptive gesture/mode reset:   PASS (code-path verification; manual effect not clearly perceptible)
```

For the post-middle Shift check, persistence of locked mode after releasing Shift is affirmative evidence: release is not supposed to revert the toggle.

## Recording a future complete pass

For a release candidate, record separately:

```text
runtime Build-ID verification: PASS
free + release cancellation:   PASS
Shift-before-middle:           PASS
post-middle Shift toggle:      PASS
Scroll Lock/latching:          PASS
middle suppression true/false: PASS
adaptive gesture/mode reset:   PASS (manual, instrumented, or exact code-path verification)
```

A basic scrolling smoke test is not a substitute for this matrix. The shared core unit/equivalence tests cover reusable startup/reconstruction/profile mechanics; this checklist covers integration-owned routing, keyboard policy, posting, suppression, and host reset behavior.
