# Direct Krita pressure measurements

The reference came from the official
[Krita source archive](https://download.kde.org/stable/krita/6.0.4.1/krita-6.0.4.1.tar.gz).
Its SHA-256 is `eaff00521958503aa1d3ef1206d75e00b57ed65993e953689f0a04850427e2d8`.
This is the archive pinned by the [earlier Flathub build](../krita-5.3.4.1-qemu/README.md).
The common source builds as Krita 5.3.4.1 with Qt 5.

## Live pen measurements

We compiled the application’s pressure mapping entry point and the upstream
curve code from the pinned archive, with debug information and a numeric
trace at the return to the painting input path. We loaded that rebuilt
pressure component into the pinned Krita Flatpak
`3e661cda91808730da4d854b9fde688846305550808c75a9361b13d86b545eb6` in the
guest. The rest of the running application came from that release.

The Zig tablet probe sent two strokes each for the plateau and descending
curves using `tablet-probe emit 20138 24120 26427`. The captures repeated
exactly for both curves. Each case in [runtime-trace.json](runtime-trace.json)
contains all 98 normalized input/output pairs from one stroke, including
repeated pressure levels. The guest also traced the unchanged shipped
pressure method on the same input. The shipped method, rebuilt pressure
path, and standalone source-compiled component agreed exactly on all 196
pairs. The [runtime comparison](runtime-comparison.csv) reports the current
Zig mapper's errors on those pen events.

## Component measurements

In the headless QEMU VM, we compiled the upstream curve translation unit with
the upstream headers and its CMake-generated compiler flags. The probe linked
the built Krita global library and used Qt 5.15.13, Eigen 3.4.0, and GCC 13.3.
It constructed each curve from its serialized preferences and called the
same transfer-table and pressure lookup routines used by the canvas builder.
The component probe exercised the global mapping independently of canvas
events and the brush engine.

[component-trace.json](component-trace.json) contains the exact curve anchors
and 1,025 `[raw, mapped]` pairs per curve. The inputs are 513 evenly spaced
pressures from zero to one, plus a sample inside each interval. The probe
printed both values with 17 significant digits. Two VM runs returned
identical numeric output for all eight curves.

[component-comparison.csv](component-comparison.csv) compares those readings
with the current Zig mapper. Identity agrees to the displayed precision. The
largest difference is 0.053531 in normalized pressure on the plateau curve.
That is 5.35 percentage points of full-scale pressure. Between two plateau
anchors set to 0.650, Krita reached 0.696640 while the Zig mapper held 0.650.

```sh
zig build
zig-out/bin/tablet-probe compare-pressure \
  evidence/krita-5.3.4.1-instrumented/component-trace.json
zig-out/bin/tablet-probe compare-pressure \
  evidence/krita-5.3.4.1-instrumented/runtime-trace.json
```

An optional last argument applies a maximum absolute error tolerance. For
example, `0.000001` currently returns a failing status and prints the
worst sample for each curve. The tolerance refers to normalized pressure,
while the earlier black-box experiment used rendered stroke pixels.

All source, instrumentation, and build artifacts were confined to the VM.
