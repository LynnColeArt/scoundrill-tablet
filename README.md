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
X coordinates must strictly increase. It interpolates linearly between anchors
and holds the endpoint values outside their span. A one-anchor curve is
constant. The mapping accepts finite pressure values and uses no heap
allocations.

```sh
zig build test
```

## Recovery status

The pressure behavior above is Scoundrill's own contract, tested directly in
Zig. The previous source-based reference and its recordings were retired.
Krita parity is unverified. Any future Ziggify baseline must come from
black-box observations of the installed application. Krita's Tablet Tester
reports raw input, so it can supply tablet event observations. Pressure mapping
requires observing a path that applies the global curve, such as painting.
