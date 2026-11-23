# Krita 5.3.4.1 pressure capture

These are black-box observations from the Flathub build of Krita 5.3.4.1
(commit `3e661cda91808730da4d854b9fde688846305550808c75a9361b13d86b545eb6`)
on Linux Mint under X11. The virtual pen was driven by the Zig tablet probe.

- [Tablet Tester log](tablet-tester.txt) was copied from Krita after
  `tablet-probe emit 21162 22451 22783`. The drawing-area trace ran from
  (24.92, 104.92) to (214.88, 104.92) and includes press and release.
- [Canvas input plan](canvas-plan.csv) was generated with
  `tablet-probe plan 18944 24120 25088`. The same arguments were used for
  every canvas replay.
- The archived images are lossless gzip copies of Krita's binary PPM exports
  from a 960×640 white canvas at 97.7% fit zoom. Each used the `b) Basic-5 Size`
  preset, 64 px, black, 100% opacity, and Normal mode.
- Identity and soft each produced two byte-identical exports. The archive
  contains one valid hard export. Earlier hard runs had the Move tool
  selected and were excluded. The hard result still needs a repeat.

| Curve | Control points | Export |
| --- | --- | --- |
| Identity | (0, 0), (1, 1) | [identity.ppm.gz](identity.ppm.gz) |
| Soft | (0, 0), (0.5, 0.749361), (1, 1) | [soft.ppm.gz](soft.ppm.gz) |
| Hard | (0, 0), (0.5, 0.25064), (1, 1) | [hard.ppm.gz](hard.ppm.gz) |

Widths count pixels with mean RGB below 128 in rows 245–369. Columns were
mapped from the eight marked plateau midpoints using the canvas position
and zoom. The pressure column is the value reported by the Tablet Tester.

| Device pressure | Krita reported | Canvas column | Identity (px) | Soft (px) | Hard (px) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 128 | 11.6% | 137 | 0 | 1 | 0 |
| 256 | 24.3% | 230 | 2 | 9 | 0 |
| 384 | 36.9% | 323 | 7 | 22 | 0 |
| 512 | 49.5% | 416 | 14 | 36 | 2 |
| 640 | 62.1% | 510 | 24 | 46 | 7 |
| 768 | 74.8% | 603 | 36 | 54 | 20 |
| 896 | 87.4% | 696 | 50 | 60 | 40 |
| 1023 | 99.9% | 789 | 62 | 64 | 62 |

To estimate how the current mapper would behave, first map each reported
pressure through Scoundrill's linear soft or hard curve. Then interpolate
the identity widths at the mapped pressure, holding the nearest endpoint
width outside the sampled range. At 74.8% pressure the estimates were
50.0 px for soft and 24.1 px for hard. Krita measured 54 px and 20 px.
These width estimates suggest a systematic difference, with brush
response and pixel quantization contributing uncertainty.

From the repository root, run `zig build` followed by
`ziggify replay . --original` to remeasure the three archived exports.
Replay verifies the measurements from frozen images. A live repeat requires
Krita and a virtual pen in a dedicated test desktop, preferably a Linux VM
with guest-local `/dev/uinput`.
