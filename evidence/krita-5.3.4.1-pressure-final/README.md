# Final pressure parity capture

Pressure mapping passes the agreed absolute normalized tolerance of `1e-6`
on the combined 35,383 recorded input/output pairs. This includes 26,987 fresh
samples from 13 curves with tight anchors, sharp transitions, and corner flags.
The maximum discrepancy in this capture is `1.435326413e-9`, on tight-flat.

## Reference and reproducibility

[Capture inputs](capture-inputs.json) were committed as `8dd7170` before
collecting outputs. The fresh headless QEMU guest ran Ubuntu 24.04.5 LTS,
Linux `6.8.0-147-generic`, GCC 13.3.0, Qt 5.15.13, and Eigen 3.4.0.

The source archive was
[Krita 6.0.4.1](https://download.kde.org/stable/krita/6.0.4.1/krita-6.0.4.1.tar.gz),
SHA-256 `eaff00521958503aa1d3ef1206d75e00b57ed65993e953689f0a04850427e2d8`.
This is the shared source for the Qt 5 build branded 5.3.4.1 and matches
the archive used for the [earlier instrumented verification](../krita-5.3.4.1-instrumented/README.md).

Inside the guest, CMake configured the complete source with Qt 5 and debug
information. We built Krita's global library, then compiled the unchanged
curve translation unit with its CMake-generated flags and upstream headers.
A private driver parsed each serialized curve, generated its 1,025-entry
floating-point transfer table, and called the pressure interpolation routine.
Corner flags were passed through the upstream `is_corner` setting.

The input set contains the 1,025 table positions, one offset within each
table interval, samples at and immediately beside anchors, midpoints between
anchors, and probes around the lookup snapping threshold. Each case was run
twice in independent processes and produced byte-identical CSV output.
[Capture digests](capture-digests.txt) list the sample count and SHA-256 of
each process's CSV stream. [trace.json](trace.json) stores those pairs as
numbers, together with the anchors and corner flags.

The private reference executable's SHA-256 was
`3affc1ed93fbfc9300d10e32690673b21390f6d6d2e0f4ea308eb8465cf8b2ea`.
The published JSON trace's SHA-256 is
`d2a41bc73bc9491d2ac2e91a9765713695610089442f059e02f622bd4d3c119f`.

These are fresh component observations. The prior live pen traces established
agreement between this reference path and the released application's path on
196 pen events. The final capture invoked the mapping directly in the VM.

## Changes and measured results

Zig anchors now accept an optional `corner = true`. At an interior corner,
the curve joins independently natural spline sections. Endpoint flags have
no effect. Existing anchors default to smooth behavior.

The new probes also confirmed snapping of interpolation weights within
`1e-6` of a table boundary to the adjacent entry. Adding the same snapping
reduced the largest fresh discrepancy from `3.993481187e-7` to
`1.435326413e-9`. The remaining small discrepancies occur on ill-conditioned
tight anchors and are within the agreed tolerance.

[comparison.csv](comparison.csv) reports all 13 cases. Run from the root:

```sh
zig build
zig build parity
zig-out/bin/tablet-probe compare-pressure \
  evidence/krita-5.3.4.1-pressure-final/trace.json 0.000001
```

The `parity` build step checks all three direct trace files, including the
fresh capture, and fails when any recorded output exceeds the tolerance.

## Closed scope

Pressure parity is accepted at `1e-6` for the recorded normalized input
domain and curve configurations. Coverage includes ordinary smooth curves,
inset endpoints, constant curves, overshoot and clipping, anchors separated
by `1/16384`, steep rises and valleys, single and multiple interior corners,
mixed smooth and corner anchors, and endpoint corner flags.

The API accepts 1–32 finite anchors in `[0, 1]` with strictly increasing X.
Authored tests additionally exercise subnormal spacing and invalid inputs.
The recorded comparison covers valid normalized pressure mapping. Device
delivery, tilt, pen and eraser routing, string parsing, and Krita's invalid
configuration recovery have their own scope.
