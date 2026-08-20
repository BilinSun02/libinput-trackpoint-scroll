# Debugging and maintenance

## Prove the loaded library before debugging behavior

Do not infer which libinput is active from a successful `ninja install`, from the existence of a file under an expected prefix, or from `ldconfig -p` alone.

There are three distinct facts:

1. **installed file identity** — what bytes exist at a filesystem path;
2. **cache selection** — which SONAME entry appears first in `ldconfig -p` after `ldconfig`;
3. **runtime mapping** — which file an actual running process has mapped in `/proc/<pid>/maps`.

For post-reboot validation use:

```bash
sh ./tools/verify-runtime-libinput.sh
```

The helper compares the build artifact, the first cache entry, and readable process mappings by ELF Build ID. Runtime claims should be based on actual process mappings, not cache terminology.

A previous false-positive validation happened because the desktop booted and scrolling worked, but later Build-ID comparison showed the running session was still using the older v14 library. That boot was correctly discarded as validation of 0.1.0.

## Preserve failed-boot evidence

If a graphical session fails after a custom libinput install, preserve the failed boot's journal before changing installations when practical:

```bash
journalctl --list-boots
journalctl -b <failed-boot> --no-pager | \
  grep -Ei 'libinput|gnome-shell|mutter|gdm|gdm-wayland|gdm-session|segfault|coredump|shared object|undefined symbol|ld\.so'
```

The 0.1.0 install incident was eventually identified from journal lines showing GNOME Shell and the Xorg libinput driver could not resolve `libinput.so.10`. Repeated GDM `GDM_IS_REMOTE_DISPLAY` assertions were also present on successful boots and were incidental rather than causal.

Do not promote a plausible explanation such as “missing `ldconfig` caused it” until the evidence supports that level of specificity. In the incident, the durable fact was missing SONAME resolution on the failed boot; the corrected workflow then demonstrated that an explicit cache refresh plus verification allowed the `/usr/local` build to be selected and run successfully.

## Do not infer compositor settings from standalone tools

`libinput list-devices` and `libinput debug-events` create their own libinput contexts. Their displayed defaults are not the live GNOME/Mutter pointing-stick preferences.

Use `gsettings` for GNOME's live configuration. When testing `debug-events`, supply explicit options as needed.

## Prove the execution path before tuning

Plausible public output does not prove the intended internal path is active. For routing problems, instrument boundaries explicitly:

1. route selection in the button-scroll motion path;
2. raw feed into the shared engine;
3. logical timer/tick execution;
4. transformed output before posting;
5. the final public notifier.

Useful fields include device, timestamp, state, raw vector, estimated interval, tick count, reconstructed vector, transformed vector, and whether public output was posted.

Do not tune transfer-function constants while the loaded library or execution route is uncertain.

## Safe replacement and uninstall

Do not normally use `ninja uninstall` before installing a compatible replacement. Besides creating a temporary interval where the SONAME may disappear, uninstall uses the invoking build tree's install manifest. If another build has since installed over the same destinations, the old uninstall can remove the newer build's files.

After installing a shared-library candidate:

```bash
sudo ldconfig
```

then verify cache identity before restarting, and verify live process mappings after the restart.

Do not automatically remove a different self-compiled libinput simply because it wins cache order. Identify its prefix/provenance first. Do not overwrite dpkg-owned paths without an explicit packaging/diversion strategy.

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
