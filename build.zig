// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const tablet = b.addModule("scoundrill_tablet", .{
        .root_source_file = b.path("src/pressure.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = tablet });
    const test_step = b.step("test", "Run tablet library and probe tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    if (target.result.os.tag == .linux) {
        const probe_module = b.createModule(.{
            .root_source_file = b.path("tools/probe.zig"),
            .target = target,
            .optimize = optimize,
        });
        probe_module.addImport("scoundrill_tablet", tablet);
        const probe = b.addExecutable(.{ .name = "tablet-probe", .root_module = probe_module });
        b.installArtifact(probe);
        const parity = b.step("parity", "Compare archived Krita pressure traces within 1e-6");
        for ([_][]const u8{
            "evidence/krita-5.3.4.1-instrumented/component-trace.json",
            "evidence/krita-5.3.4.1-instrumented/runtime-trace.json",
            "evidence/krita-5.3.4.1-pressure-final/trace.json",
        }) |path| {
            const replay = b.addRunArtifact(probe);
            replay.addArg("compare-pressure");
            replay.addFileArg(b.path(path));
            replay.addArg("0.000001");
            parity.dependOn(&replay.step);
        }
        const probe_tests = b.addTest(.{ .root_module = probe_module });
        test_step.dependOn(&b.addRunArtifact(probe_tests).step);
    }
}
