const std = @import("std");
const library = @import("library.zig");
comptime {
    if (!std.debug.runtime_safety) @compileError("Ziggify requires Debug or ReleaseSafe");
}
pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    const input = try reader.interface.allocRemaining(init.arena.allocator(), .limited(16 * 1024 * 1024));
    const response = library.evaluate(init.arena.allocator(), input, .{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        const bytes = try std.json.Stringify.valueAlloc(init.arena.allocator(), .{ .@"error" = .{ .type = @errorName(err) } }, .{});
        try std.Io.File.stdout().writeStreamingAll(init.io, bytes);
        try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
        std.process.exit(3);
    };
    try std.Io.File.stdout().writeStreamingAll(init.io, response);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
