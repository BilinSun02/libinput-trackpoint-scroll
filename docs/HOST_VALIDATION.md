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

1. Start a middle-button gesture in the default free mode.
2. Press Shift only after middle is down, either before the first motion or during scrolling.
3. Continue moving.
4. Release that same Shift key.

Pass criteria:

- the gesture toggles from free to locked mode;
- locked mode exhibits libinput's ordinary buildup/direction/axis-lock behavior rather than unrestricted two-dimensional output;
- the fresh Shift press and its matching release are consumed by the custom gesture policy;
- the switch does not emit a second fixed startup micro-step; post-switch motion resumes through sustained reconstruction.

Repeat once with the gesture starting locked (see Scroll Lock below); post-middle Shift must toggle it back to free.

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

This check is only for the integration-owned adaptive wrapper; the recommended hyperbolic profile is memoryless.

Temporarily set:

```ini
profile=adaptive
```

and replug the TrackPoint. Then:

1. Scroll hard enough in one gesture to build substantial adaptive velocity history.
2. Release middle.
3. Start a fresh gesture with deliberately light motion.
4. Confirm the new gesture does not inherit the previous gesture's high-velocity response.
5. Build velocity again, press Shift after middle to switch mode, then continue with light post-switch motion.
6. Confirm the post-switch response does not inherit the pre-switch adaptive history.

Restore the recommended profile and replug when finished.

## Recording a pass

For a release candidate, record separately:

```text
runtime Build-ID verification: PASS
free + release cancellation:   PASS
Shift-before-middle:           PASS
post-middle Shift toggle:      PASS
Scroll Lock/latching:          PASS
middle suppression true/false: PASS
adaptive gesture/mode reset:   PASS
```

A basic scrolling smoke test is not a substitute for this matrix. The shared core unit/equivalence tests cover reusable startup/reconstruction/profile mechanics; this checklist covers integration-owned routing, keyboard policy, posting, suppression, and host reset behavior.
