// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const stroke = @import("stroke.zig");
const uinput = @import("uinput.zig");
const ppm = @import("ppm.zig");

const usage =
    \\Usage:
    \\  tablet-probe plan X_START Y X_END
    \\  tablet-probe emit X_START Y X_END
    \\  tablet-probe measure IMAGE.ppm Y_START Y_END X [X ...]
    \\
    \\plan and emit use virtual tablet coordinates from 0 to 32767.
    \\emit sends a stroke to the desktop after a three-second delay.
    \\measure uses image pixel coordinates and an exclusive Y_END.
    \\
;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) {
        try stdout.interface.writeAll(usage);
        try stdout.interface.flush();
        return;
    }
    run(init, args[1..], &stdout.interface) catch |err| {
        switch (err) {
            error.Usage, error.InvalidStroke => std.debug.print("{s}\n{s}", .{ @errorName(err), usage }),
            error.AccessDenied, error.PermissionDenied => std.debug.print(
                "{s}: this process needs write access to /dev/uinput to emit tablet events.\n",
                .{@errorName(err)},
            ),
            else => std.debug.print("tablet-probe: {s}\n", .{@errorName(err)}),
        }
        std.process.exit(1);
    };
    try stdout.interface.flush();
}

fn run(init: std.process.Init, args: []const [:0]const u8, out: *std.Io.Writer) !void {
    if (args.len == 0) return error.Usage;
    if (std.mem.eql(u8, args[0], "measure")) {
        if (args.len < 5) return error.Usage;
        try measure(init, args[1..], out);
        return;
    }

    const preview = std.mem.eql(u8, args[0], "plan");
    if (args.len != 4 or (!preview and !std.mem.eql(u8, args[0], "emit"))) return error.Usage;
    const start_x = std.fmt.parseInt(i32, args[1], 10) catch return error.Usage;
    const y = std.fmt.parseInt(i32, args[2], 10) catch return error.Usage;
    const end_x = std.fmt.parseInt(i32, args[3], 10) catch return error.Usage;
    const frames = try stroke.plan(start_x, y, end_x);

    if (preview) {
        try out.writeAll("time_ms,phase,x,y,pressure,sample\n");
        for (frames, 0..) |frame, index| {
            try out.print("{d},{s},{d},{d},{d},{d}\n", .{
                index * stroke.step_ms, @tagName(frame.phase),      frame.x, frame.y,
                frame.pressure,         @intFromBool(frame.sample),
            });
        }
        return;
    }

    const tablet = try uinput.Tablet.create(init.io);
    defer tablet.destroy(init.io);
    std.debug.print("Virtual pen ready. Focus the test canvas or Tablet Tester. Stroke starts in three seconds.\n", .{});
    try std.Io.sleep(init.io, .fromSeconds(3), .awake);
    for (frames) |frame| {
        try tablet.send(frame);
        try std.Io.sleep(init.io, .fromMilliseconds(stroke.step_ms), .awake);
    }
    try std.Io.sleep(init.io, .fromMilliseconds(200), .awake);
    try out.print("Sent {d} frames.\n", .{frames.len});
}

fn measure(init: std.process.Init, args: []const [:0]const u8, out: *std.Io.Writer) !void {
    const y_start = std.fmt.parseUnsigned(usize, args[1], 10) catch return error.Usage;
    const y_end = std.fmt.parseUnsigned(usize, args[2], 10) catch return error.Usage;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[0], init.gpa, .limited(128 * 1024 * 1024));
    defer init.gpa.free(bytes);
    const image = try ppm.Image.parse(bytes);

    const widths = try init.gpa.alloc(struct { x: usize, width: usize }, args.len - 3);
    defer init.gpa.free(widths);
    for (args[3..], widths) |argument, *result| {
        const x = std.fmt.parseUnsigned(usize, argument, 10) catch return error.Usage;
        result.* = .{ .x = x, .width = try image.strokeWidth(x, y_start, y_end) };
    }

    try out.writeAll("x,width_px\n");
    for (widths) |item| try out.print("{d},{d}\n", .{ item.x, item.width });
}

test {
    std.testing.refAllDecls(stroke);
    std.testing.refAllDecls(uinput);
    std.testing.refAllDecls(ppm);
}
