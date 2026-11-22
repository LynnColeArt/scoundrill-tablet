// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const linux = std.os.linux;
const stroke = @import("stroke.zig");

// Linux input-event-codes.h and uinput.h userspace ABI.
const ev_syn = 0;
const ev_key = 1;
const ev_abs = 3;
const btn_tool_pen = 0x140;
const btn_touch = 0x14a;
const btn_stylus = 0x14b;
const abs_x = 0;
const abs_y = 1;
const abs_pressure = 0x18;

const InputId = extern struct {
    bus: u16 = 6, // BUS_VIRTUAL
    vendor: u16 = 0,
    product: u16 = 0,
    version: u16 = 1,
};

const DeviceSetup = extern struct {
    id: InputId = .{},
    name: [80]u8 = @splat(0),
    max_force_feedback: u32 = 0,
};

const AxisSetup = extern struct {
    code: u16,
    value: i32 = 0,
    minimum: i32 = 0,
    maximum: i32,
    fuzz: i32 = 0,
    flat: i32 = 0,
    resolution: i32,
};

const Event = extern struct {
    seconds: c_long = 0,
    microseconds: c_long = 0,
    kind: u16,
    code: u16,
    value: i32,
};

const EncodedFrame = struct {
    events: [5]Event,
    has_key: bool,

    fn constSlice(frame: *const EncodedFrame) []const Event {
        return frame.events[if (frame.has_key) 0 else 1..];
    }
};

pub const Tablet = struct {
    file: std.Io.File,

    pub fn create(io: std.Io) !Tablet {
        const file = try std.Io.Dir.openFileAbsolute(io, "/dev/uinput", .{ .mode = .write_only });
        errdefer file.close(io);
        const fd = file.handle;

        try ioctl(fd, linux.IOCTL.IOW('U', 100, c_int), ev_key);
        try ioctl(fd, linux.IOCTL.IOW('U', 100, c_int), ev_abs);
        for ([_]usize{ btn_touch, btn_tool_pen, btn_stylus }) |code| {
            try ioctl(fd, linux.IOCTL.IOW('U', 101, c_int), code);
        }
        try ioctl(fd, linux.IOCTL.IOW('U', 110, c_int), 1); // INPUT_PROP_DIRECT

        const axes = [_]AxisSetup{
            .{ .code = abs_x, .maximum = stroke.axis_max, .resolution = 100 },
            .{ .code = abs_y, .maximum = stroke.axis_max, .resolution = 100 },
            .{ .code = abs_pressure, .maximum = stroke.pressure_max, .resolution = 0 },
        };
        for (&axes) |*axis| {
            try ioctl(fd, linux.IOCTL.IOW('U', 4, AxisSetup), @intFromPtr(axis));
        }

        var setup: DeviceSetup = .{};
        const name = "Scoundrill virtual pen";
        @memcpy(setup.name[0..name.len], name);
        try ioctl(fd, linux.IOCTL.IOW('U', 3, DeviceSetup), @intFromPtr(&setup));
        try ioctl(fd, linux.IOCTL.IO('U', 1), 0);
        return .{ .file = file };
    }

    pub fn destroy(tablet: Tablet, io: std.Io) void {
        ioctl(tablet.file.handle, linux.IOCTL.IO('U', 2), 0) catch {};
        tablet.file.close(io);
    }

    pub fn send(tablet: Tablet, frame: stroke.Frame) !void {
        const events = encode(frame);
        const bytes = std.mem.sliceAsBytes(events.constSlice());
        while (true) {
            const written = linux.write(tablet.file.handle, bytes.ptr, bytes.len);
            switch (linux.errno(written)) {
                .SUCCESS => {
                    if (written != bytes.len) return error.IncompleteFrame;
                    return;
                },
                .INTR => continue,
                else => |err| {
                    std.debug.print("uinput write failed: {s}\n", .{@tagName(err)});
                    return error.UinputWriteFailed;
                },
            }
        }
    }
};

fn ioctl(fd: linux.fd_t, request: u32, value: usize) !void {
    while (true) {
        switch (linux.errno(linux.ioctl(fd, request, value))) {
            .SUCCESS => return,
            .INTR => continue,
            else => |err| {
                std.debug.print("uinput ioctl 0x{x} failed: {s}\n", .{ request, @tagName(err) });
                return error.UinputIoctlFailed;
            },
        }
    }
}

fn encode(frame: stroke.Frame) EncodedFrame {
    const key: ?Event = switch (frame.phase) {
        .contact, .lift => .{
            .kind = ev_key,
            .code = btn_touch,
            .value = @intFromBool(frame.phase == .contact),
        },
        .hover, .leave => .{
            .kind = ev_key,
            .code = btn_tool_pen,
            .value = @intFromBool(frame.phase == .hover),
        },
        .drag => null,
    };
    return .{
        .has_key = key != null,
        .events = .{
            key orelse .{ .kind = 0, .code = 0, .value = 0 },
            .{ .kind = ev_abs, .code = abs_x, .value = frame.x },
            .{ .kind = ev_abs, .code = abs_y, .value = frame.y },
            .{ .kind = ev_abs, .code = abs_pressure, .value = frame.pressure },
            .{ .kind = ev_syn, .code = 0, .value = 0 }, // SYN_REPORT
        },
    };
}

test "the phase boundaries encode tablet keys and a sync report" {
    const frames = try stroke.plan(100, 200, 1050);
    for (frames) |frame| {
        const encoded = encode(frame);
        const events = encoded.constSlice();
        const pressure = events[events.len - 2];
        try std.testing.expectEqual(abs_pressure, pressure.code);
        try std.testing.expectEqual(frame.pressure, pressure.value);
        try std.testing.expectEqual(ev_syn, events[events.len - 1].kind);
        switch (frame.phase) {
            .hover, .leave => {
                try std.testing.expectEqual(btn_tool_pen, events[0].code);
                try std.testing.expectEqual(@intFromBool(frame.phase == .hover), events[0].value);
            },
            .contact, .lift => {
                try std.testing.expectEqual(btn_touch, events[0].code);
                try std.testing.expectEqual(@intFromBool(frame.phase == .contact), events[0].value);
            },
            .drag => try std.testing.expectEqual(ev_abs, events[0].kind),
        }
    }
}
