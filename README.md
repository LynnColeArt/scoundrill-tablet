# Scoundrill Tablet

A Zig 0.16 library for tablet input processing in Scoundrill projects. The first
recovered component is Krita's global pressure curve. It takes pressure values
from the host and maps them through a prepared curve before the host uses them
for painting.

## Zig API

Import `scoundrill_tablet` from the package's build module. Prepare a curve when
settings change and reuse it across events.

```zig
const tablet = @import("scoundrill_tablet");

const curve = try tablet.PressureCurve.init(&.{
    .{ .x = 0.0, .y = 0.0 },
    .{ .x = 0.4, .y = 0.22 },
    .{ .x = 1.0, .y = 1.0 },
});
const mapped = try curve.map(0.52);
```

Points must have coordinates in `[0, 1]`, with increasing X values at least
`1/1024` apart. A curve accepts 1–32 points. An interior point with
`corner = true` allows the slope to change sharply there. The curve owns its
lookup table and can be reused without allocations. The usual host pressure
range is `[0, 1]`. Finite values outside it follow Krita's lookup and sign
behavior.

## Native driver

```sh
zig build --build-file ziggify/native/build.zig -Doptimize=ReleaseSafe
printf '%s\n' '{"points":[{"x":0,"y":0},{"x":1,"y":1}],"samples":[0,0.25,1]}' \
  | ziggify/native/zig-out/bin/port
```

This prints `[0,250000000,1000000000]`. The Ziggify driver and generated C ABI
accept up to 4096 samples per request and return pressures rounded to billionths
as JSON integers. An invalid request returns a named `InvalidRequest` error.
The Zig API returns unquantized `f64` values.

## Verify the recovery

```sh
zig build test
python3 reference/build.py
ziggify replay . --original
ziggify gate .
```

Building the reference requires Python 3, a C++17 compiler, pkg-config, Qt Core
development headers, Eigen 3 headers and Boost headers. The recording was made
with Qt 5.15.13 and Eigen 3.4.0. The build defaults to `Qt5Core` and
`/usr/include/eigen3`. Override the package name with `QT_CORE_PKG` or the
include path with `EIGEN_INCLUDE_DIR` as needed. The script fetches and checks
pinned source files before compiling the headless driver into `.oracle/`.

The gate compares the Zig driver with the recorded output for 24 requests,
including increasing and decreasing pressure, smooth curves, sharp corners,
clipping and invalid inputs. See [attribution and reference details](ATTRIBUTION.md).

The recovered boundary starts at numeric samples and ends at remapped pressure.
Device discovery, OS event delivery, pen and eraser routing, tilt, touch, stroke
smoothing and brush response need their own reference cases.
