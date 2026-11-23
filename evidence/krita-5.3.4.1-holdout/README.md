# Held-out Krita pressure curves

The [comparison inputs](compare.json) and the smooth Zig implementation were
committed together as `21ae263`, before collecting these outputs. The test
uses two four-anchor curves, one with an asymmetric transition and one with
a nearly flat middle span. A new identity capture calibrates pressure
against apparent brush width.

The [isolated QEMU setup](../../docs/isolated-capture.md) ran the same
Krita Flathub commit `3e661cda91808730da4d854b9fde688846305550808c75a9361b13d86b545eb6`
in Ubuntu 24.04.5 with Linux `6.8.0-147-generic`, Xorg 21.1.12, and
libinput 1.25.0. Guest input and display were independent of the host.

- [Tablet Tester log](tablet-tester.txt) records `tablet-probe emit 21324 23346 22945`
  and confirms all eight reported pressure levels.
- [Canvas plan](canvas-plan.csv) records `tablet-probe emit 20138 24120 26427`.
  All runs used a 960×640 white canvas at 100% zoom, the `b) Basic-5 Size`
  preset at 64 px, black, 100% opacity, and Normal blending.
- Two captures of each curve produced byte-identical PPM exports. Each gzip
  file contains one copy of its pair.

| Capture | SHA-256 of both uncompressed PPM exports |
| --- | --- |
| [Identity](identity.ppm.gz) | `bd5674a9a7d5c2ea1e57b709567df45a6a7e8755d61d484732069d2d27729748` |
| [Asymmetric](asymmetric.ppm.gz) | `167e553ecaa7270fb482381477cc75f1a37a7278f5f62d6d2bec213d86ac215d` |
| [Near-flat](near-flat.ppm.gz) | `28d013eadc50a7e56d4b70622b647d923e543aa19f9f18eb4cba0208b6c16d3c` |

For each input pressure, the comparison maps pressure through the previous
linear mapper or the new shape-preserving cubic mapper. It estimates the
resulting width by interpolating the measured identity widths. It then
compares each estimate with the corresponding pixel measurement from
Krita's exported stroke.

| Curve | Linear mean error (px) | Smooth mean error (px) | Linear worst error (px) | Smooth worst error (px) |
| --- | ---: | ---: | ---: | ---: |
| Asymmetric | 1.899 | 1.334 | 5.371 | 3.164 |
| Near-flat | 1.507 | 0.784 | 4.836 | 1.936 |
| Combined | 1.703 | 1.059 | 5.371 | 3.164 |

The smooth mapper reduced combined mean absolute width error by 38% in this
test. The remaining width differences include the brush response, pressure
reporting precision, and pixel sampling. This test measures rendered
strokes for one brush at eight pressures per curve.

From the repository root, these commands remeasure the frozen exports and
reproduce the [comparison output](comparison.csv).

```sh
zig build
ziggify replay evidence/krita-5.3.4.1-holdout --original
zig-out/bin/tablet-probe compare evidence/krita-5.3.4.1-holdout/compare.json
```
