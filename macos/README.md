# macOS port

This directory contains a macOS user-space adapter for the shared `trackpoint-scroll-core` engine.

## Why the adapter being a "generic mouse" is not a blocker

The Linux integration needs a udev `ID_INPUT_POINTINGSTICK=1` tag because libinput selects policy from udev classification. macOS does not need an equivalent reclassification for this adapter.

The macOS process opens `IOHIDManager` with an exact USB vendor/product match (tested adapter defaults: `0x5859:0x0001`) and consumes the raw relative X/Y and button-3 HID elements directly. The device is therefore useful to the port even when the operating system also regards it as an ordinary mouse.

The default implementation deliberately does **not** seize the device. Ordinary pointer motion is left on macOS's stock mouse path so normal cursor acceleration/behavior is unchanged. While the physical middle button is held, a `kCGHIDEventTap` suppresses the ordinary mouse-motion and middle-button Quartz events and the raw HID deltas are instead passed through `trackpoint-scroll-core`; continuous two-axis scroll events are then posted with Core Graphics.

This split is important:

```text
not holding middle:
  USB HID -> normal macOS mouse path

holding middle:
  raw USB HID X/Y -> trackpoint-scroll-core -> synthetic continuous scroll
  ordinary Quartz mouse motion/middle events -> suppressed by HID event tap
```

Thus the initial generic-mouse classification is actually compatible with the design rather than something that must be changed first.

## Current parity

Implemented:

- exact adapter matching by vendor/product, independent of higher-level device classification;
- middle-button gesture lifecycle;
- raw, unaccelerated relative X/Y input into the shared core;
- 2 ms reconstruction/tick scheduling with bounded catch-up;
- startup fixed step, axis coalescing/rebound handling, idle reset, and interval reconstruction from the core;
- affine, quadratic, and hyperbolic core profiles;
- continuous two-dimensional Core Graphics scroll output;
- default no-scroll middle-click suppression;
- optional deferred middle-click replay with `suppress_middle_click=false`;
- ordinary macOS cursor behavior outside a middle-scroll gesture.

Not yet reproduced from the libinput-specific integration:

- libinput's adaptive TrackPoint acceleration filter (`profile=adaptive`), because that filter is not part of the platform-neutral core;
- the Linux integration's Shift free/locked toggle and Scroll Lock default-mode latch;
- libinput's locked-mode buildup/axis-lock notifier behavior.

The recommended Linux configuration uses `profile=hyperbolic`, so the normal tested profile is available on macOS without the libinput-only adaptive filter.

## Build

Requirements: Xcode Command Line Tools and a clone with submodules initialized.

```sh
git submodule update --init --recursive
cd macos
make
```

The resulting executable is:

```text
macos/trackpoint-scroll-macos
```

## Permissions

The process needs permission to listen to and post low-level events. On first launch macOS may prompt for these. If it exits with a permission error, grant the terminal/application that launches it access under Privacy & Security for Input Monitoring and Accessibility, then launch it again.

The executable checks `CGPreflightListenEventAccess()` and `CGPreflightPostEventAccess()` before opening the HID stream, specifically to avoid a failure mode where raw scrolling starts but the stock mouse events cannot be suppressed.

## Run

The tested adapter IDs are compiled as defaults:

```sh
./trackpoint-scroll-macos
```

For another adapter:

```sh
./trackpoint-scroll-macos --vendor 0x5859 --product 0x0001
```

With a config file:

```sh
./trackpoint-scroll-macos --config ./trackpoint-scroll-macos.conf.example
```

The process logs when a matching HID device is attached/removed.

## Configuration

The parser intentionally follows the small `key=value` style of the Linux integration. Supported keys are:

```text
profile = affine | quadratic | hyperbolic
clamp_negative_output
suppress_middle_click
scroll_scale
first_step_distance
first_step_axis_merge_ms
first_step_max_reports
idle_reset_ms
affine_k
affine_b
quadratic_a
quadratic_h
quadratic_k
hyperbolic_a
hyperbolic_u
hyperbolic_k
```

Aliases retained from the Linux configuration are accepted for affine (`linear`, `flat`) and hyperbolic (`asymptotic`, `asymptotic-linear`) names/parameters.

`scroll_scale` is macOS-specific and multiplies the core result before it becomes a pixel-unit Quartz scroll event.

## Safety / recovery

This version does not take exclusive ownership of the USB device, so killing the process immediately returns behavior to the normal macOS mouse path. If the event tap is disabled by the system because its callback times out, the callback re-enables it automatically.

If suppression is ever unreliable on a particular macOS release, the fallback architecture is to open the matched `IOHIDDevice` with `kIOHIDOptionsTypeSeizeDevice` and re-emit the non-scroll mouse events. Apple documents that seize mode establishes exclusive communication and prevents the system/other clients from receiving the device's events; that route is intentionally not the default because it would also make us responsible for reproducing normal pointer acceleration and every button behavior.
