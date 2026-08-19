# Device setup

## Tested device

```text
name:    xy_3dg12 xy_3dg12 USB RF Adapter
bus:     0x0003
vendor:  0x5859
product: 0x0001
version: 0x0110
```

Relevant input capabilities include `REL_X`, `REL_Y`, `BTN_LEFT`, `BTN_RIGHT`, and `BTN_MIDDLE`.

At low force the TrackPoint commonly emits discrete one-unit reports separated by tens or hundreds of milliseconds. One recorded trace had a median interval around 129 ms, common gaps around 50–200 ms, and occasional ordinary gaps around 440 ms. Higher force can approach roughly 10 ms report intervals. This sparse cadence is why reconstruction happens before the nonlinear scroll transform.

## udev classification

The custom route requires a TrackPoint tag and scroll-on-button-down method. The USB adapter initially may be classified as a generic mouse only. Add `ID_INPUT_POINTINGSTICK=1` while retaining `ID_INPUT_MOUSE=1`.

The precise tested rule is:

```udev
ACTION!="remove", \
SUBSYSTEM=="input", \
KERNEL=="event[0-9]*", \
ATTRS{name}=="xy_3dg12 xy_3dg12 USB RF Adapter", \
ATTRS{id/vendor}=="5859", \
ATTRS{id/product}=="0001", \
ENV{ID_INPUT_POINTINGSTICK}="1"
```

Recommended path:

```text
/etc/udev/rules.d/99-xy-3dg12-pointing-stick.rules
```

### Same-parent caveat

All `ATTRS{...}` matches in one rule must resolve on the same parent device. Do not mix the input parent's:

```text
name
id/vendor
id/product
```

with USB-parent `idVendor` / `idProduct` fields in the same parent-match set. The superficially similar mixed rule cannot match as intended.

## Activate and verify

```bash
sudo udevadm control --reload-rules
sudo udevadm test /sys/class/input/eventN
```

Then physically replug the device and check:

```bash
udevadm info --query=property --name=/dev/input/eventN |
  grep -E '^ID_INPUT_(MOUSE|POINTINGSTICK)='
```

Expected:

```text
ID_INPUT_MOUSE=1
ID_INPUT_POINTINGSTICK=1
```

## GNOME cursor settings

Reclassification changes which GNOME schema applies to ordinary cursor motion. The tested cursor setup is:

```bash
gsettings set org.gnome.desktop.peripherals.pointingstick accel-profile 'flat'
gsettings set org.gnome.desktop.peripherals.pointingstick speed 0.5
```

These cursor settings are separate from the custom scroll transform.
