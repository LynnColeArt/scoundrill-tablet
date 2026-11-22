# Scoundrill Tablet contributor instructions

Write the library, test harnesses, and reference adapters in Zig. Do not
consult, copy, download, or compile Krita implementation source. Use public
documentation and black-box observations from an installed Krita binary for
behavioral recovery. Record the application version, inputs, and observed
outputs before claiming compatibility. Keep authored expectations distinct
from observations.

Use Zig 0.16.0. Run `zig fmt --check build.zig build.zig.zon src tools` and
`zig build test` before committing.
