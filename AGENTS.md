# Scoundrill Tablet contributor instructions

Write published library code, test harnesses, and replay tools in Zig. Keep
Krita implementation source, patches, instrumented binaries, and their build
artifacts inside a disposable verification VM. A private source build may
measure Krita's behavior. Publish numeric observations and provenance, and
implement Scoundrill against the observations without copying Krita code.
Keep instrumented measurements distinct from released-binary black-box
captures and from authored expectations.

Use Zig 0.16.0. Run `zig fmt --check build.zig build.zig.zon src tools` and
`zig build test` before committing.
