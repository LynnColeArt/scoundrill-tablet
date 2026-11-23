# Krita 5.3.4.1 isolated QEMU capture

This capture used the same Flathub build and the same pressure curve control
points as the [first capture](../krita-5.3.4.1/README.md). The app commit was
`3e661cda91808730da4d854b9fde688846305550808c75a9361b13d86b545eb6`.

QEMU 8.2.2 with KVM ran an Ubuntu 24.04.5 LTS guest using Linux
`6.8.0-147-generic`, Xorg 21.1.12, and libinput 1.25.0. Openbox and Krita ran
on a guest-only Xorg dummy screen at 3840×2160. The guest's `/dev/uinput`
fed that X server. SSH carried the commands and exports, with X11
forwarding disabled. The host grant was closed. See the
[VM setup notes](../../docs/isolated-capture.md).

- [Tablet Tester log](tablet-tester.txt) records `tablet-probe emit 21324 23346 22945`.
  Krita reported all eight pressure levels, press, and release.
- The [identity plan](identity-plan.csv) uses `20138 26547 26427`. The
  [soft and hard plan](soft-hard-plan.csv) uses `20138 24120 26427` because
  reopening the canvas changed the screen Y coordinate of the same image row.
- All exports used a 960×640 white canvas at 100% zoom, the `b) Basic-5 Size`
  preset at 64 px, black, and 100% opacity. Two captures of each curve produced
  byte-identical exports within their pair. Each archive contains one copy of
  its pair.

| Curve | Interior control point | SHA-256 of both uncompressed PPM exports |
| --- | --- | --- |
| [Identity](identity.ppm.gz) | None | `6c7f042b96b90f3ce47480fac2405a7834d6e1049cb291dcde2bd4db6cc361d6` |
| [Soft](soft.ppm.gz) | (0.5, 0.749361) | `d463f29516e357a76212527d3230e7d1b7b60bf7577e50facb3d27c420bc9037` |
| [Hard](hard.ppm.gz) | (0.5, 0.25064) | `a50852064266417b20608c03076f5f8bf19287741c00cd6faa261bad8237f4c6` |

All curves use endpoints (0, 0) and (1, 1). Widths count pixels below the
same RGB threshold and in the same image rows 245–369 as the first capture.

| Krita reported | Column | Identity (px) | Soft (px) | Hard (px) |
| ---: | ---: | ---: | ---: | ---: |
| 11.6% | 137 | 0 | 1 | 0 |
| 24.3% | 230 | 2 | 9 | 0 |
| 36.9% | 323 | 7 | 22 | 1 |
| 49.5% | 416 | 14 | 36 | 2 |
| 62.1% | 510 | 24 | 46 | 7 |
| 74.8% | 603 | 36 | 54 | 20 |
| 87.4% | 696 | 49 | 60 | 40 |
| 99.9% | 789 | 63 | 63 | 62 |

Across the 24 width measurements, 20 stayed identical to the first capture
and four differed by one pixel. At 74.8% reported pressure, both setups
measured 54 px on the soft curve and 20 px on the hard curve. The earlier
linear estimates at those points were 50.0 px and 24.1 px.

From the repository root, build the probe and replay the frozen guest baseline.

```sh
zig build
ziggify replay evidence/krita-5.3.4.1-qemu --original
```
