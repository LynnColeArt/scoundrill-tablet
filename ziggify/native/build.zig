const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    if (optimize == .ReleaseFast or optimize == .ReleaseSmall) @panic("Ziggify requires Debug or ReleaseSafe");
    const libmod = b.createModule(.{ .root_source_file = b.path("library.zig"), .target = target, .optimize = optimize });
    const lib = b.addLibrary(.{ .name = "ziggify_port", .linkage = .dynamic, .root_module = libmod });
    b.installArtifact(lib);
    const exe = b.addExecutable(.{ .name = "port", .root_module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = optimize }) });
    b.installArtifact(exe);
    const tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("library.zig"), .target = target, .optimize = .Debug }) });
    b.step("test", "Check port tests, leaks, and all allocation-failure paths").dependOn(&b.addRunArtifact(tests).step);
    if (b.option([]const u8, "node-include", "Directory containing node_api.h")) |include| {
        const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .sanitize_c = .full, .stack_protector = true });
        mod.addIncludePath(.{ .cwd_relative = include });
        mod.addIncludePath(b.path("."));
        mod.addCSourceFile(.{ .file = b.path("node.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
        mod.addRPathSpecial("$ORIGIN");
        const addon = b.addLibrary(.{ .name = "ziggify_node", .linkage = .dynamic, .root_module = mod });
        mod.linkLibrary(lib);
        b.installArtifact(addon);
    }
}
