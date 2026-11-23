# Scoundrill Tablet

Scoundrill Tablet is a Zig 0.16 library for tablet input processing. It currently
provides a global pressure response curve. It is inspired by the global pressure
setting described in the [Krita Tablet Settings manual](https://docs.krita.org/en/reference_manual/preferences/tablet_settings.html).

## Pressure mapping

Import the package's `scoundrill_tablet` build module. Prepare a curve when
preferences change and reuse it for each pen sample.

```zig
const tablet = @import("scoundrill_tablet");

const curve = try tablet.PressureCurve.init(&.{
    .{ .x = 0.0, .y = 0.0 },
    .{ .x = 0.4, .y = 0.22 },
    .{ .x = 1.0, .y = 1.0 },
});
const mapped = try curve.map(0.52);
```

The curve accepts 1–32 anchors. Both coordinates must be in `[0, 1]`, and the
X coordinates must strictly increase. Three or more anchors define a natural
cubic spline with zero second derivative at each endpoint. An anchor with
`corner = true` joins independent natural spline sections at that point.
Endpoint corner flags have no effect. Initialization
samples it at 1,025 uniformly spaced pressures and clamps each sample to
`[0, 1]`. Mapping interpolates adjacent table entries in constant time.
The spline can overshoot the heights of neighboring anchors. Two anchors
define a straight line and one defines a constant. Input outside `[0, 1]`
uses the nearest end of the table, and nonfinite input is rejected.

The table owns all its storage and mapping allocates no memory. Initialization
uses wide intermediates so very close valid anchors still produce finite
table entries. Lookup sampling can slightly shift an off-grid anchor's output.
The natural spline uses a standard tridiagonal solve.

```sh
zig build test
```

## Recovery status

The mapper is tested against Scoundrill's own contract. The
[first black-box Krita baseline](evidence/krita-5.3.4.1/README.md) captures
raw pen input and measured stroke widths under three global curves. The
previous linear mapper differed from the observed stroke response. An
[isolated QEMU repeat](evidence/krita-5.3.4.1-qemu/README.md) produced two
byte-identical exports per curve. In a [held-out test](evidence/krita-5.3.4.1-holdout/README.md),
the earlier shape-preserving mapper reduced estimated mean stroke-width error from 1.70 px to
1.06 px across two new curves. Tablet device handling and cross-platform
coverage remain open.

[Direct pressure traces](evidence/krita-5.3.4.1-instrumented/README.md) isolate
the global mapping from brush rendering. The production natural spline and
lookup table pass all 8,396 archived input/output pairs at an absolute normalized pressure tolerance of `1e-6`.
The [final VM capture](evidence/krita-5.3.4.1-pressure-final/README.md) adds
26,987 observations for closely spaced anchors, sharp transitions, and corner
flags. All 35,383 direct pairs pass at `1e-6`, closing pressure mapping parity
for this recorded scope. Device delivery and other tablet sensors remain open.

Build the probe and replay the archived measurements with Ziggify.

```sh
zig build
zig build parity
ziggify replay . --original
ziggify replay evidence/krita-5.3.4.1-qemu --original
ziggify replay evidence/krita-5.3.4.1-holdout --original
zig-out/bin/tablet-probe compare evidence/krita-5.3.4.1-holdout/compare.json
zig-out/bin/tablet-probe compare-pressure evidence/krita-5.3.4.1-instrumented/component-trace.json
```

## Linux tablet probe

`zig build` installs `zig-out/bin/tablet-probe`. It generates a horizontal
stroke with eight pressure plateaus and reports the midpoint of each plateau.
Device coordinates use a 0–32767 axis range and pressure uses 0–1023.
The following coordinates are examples. Choose coordinates that map to an
empty drawing area on the desktop under test.

```sh
zig-out/bin/tablet-probe plan 9000 22000 15500
zig-out/bin/tablet-probe emit 9000 22000 15500
```

`plan` prints the intended event sequence and marks measurement rows with
`sample=1`. It runs without a device. `emit` requires write access to
`/dev/uinput`. It creates a temporary virtual pen and waits three seconds for
device discovery and focus before sending events. See the
[Linux uinput documentation](https://docs.kernel.org/input/uinput.html).

### Capturing Krita behavior

Run live capture in a dedicated Linux VM with Krita and `/dev/uinput` inside
the guest. Virtual tablet events are delivered to the desktop that owns the
device. See the [VM setup notes](docs/isolated-capture.md). Replaying the archived exports requires neither Krita nor device access.

1. Open Krita's Tablet Tester and replay the stroke entirely inside its drawing
   area. Save the text log and check that it shows pen contact, rising pressure,
   and release. Record the Krita version, desktop session, and exact probe
   arguments. See the [Krita Tablet Settings manual](https://docs.krita.org/en/reference_manual/preferences/tablet_settings.html).
2. In a fresh white canvas at 100% zoom, use a black opaque round pixel brush
   with size driven by pressure. Keep brush size, spacing, zoom, canvas position,
   and smoothing fixed. Leave room for the full stroke and its widest diameter.
3. Replay the stroke for the identity curve, a soft curve, and a hard curve.
   Save the control points and export one flattened 8-bit binary PPM per run.
   Repeat each capture on a blank canvas with the same screen layout.
4. Convert the eight marked device X positions to canvas pixel columns using
   the observed position of the stroke in the canvas. Measure those columns
   within an image row interval containing only the stroke.

```sh
zig-out/bin/tablet-probe measure example.ppm 120 220 170 210 250 290 330 370 410 450
```

The measurement counts pixels with mean RGB below 128. The Y interval is
half-open and all pixel indices are zero-based. Keep the raw logs, images, and
measurements together when creating a Ziggify baseline. The generated event
plan and the tool's unit tests are authored inputs and checks.

## License

Scoundrill Tablet is available under the [Apache License, Version 2.0](LICENSE).
