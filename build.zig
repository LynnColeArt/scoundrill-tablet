const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const tablet = b.addModule("scoundrill_tablet", .{
        .root_source_file = b.path("ziggify/native/pressure.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = tablet });
    b.step("test", "Run tablet library tests").dependOn(&b.addRunArtifact(tests).step);
}
