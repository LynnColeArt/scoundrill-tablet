// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

pub const axis_max = 32767;
pub const pressure_max = 1023;
pub const pressures = [_]i32{ 128, 256, 384, 512, 640, 768, 896, pressure_max };
pub const steps_per_pressure = 12;
pub const step_ms = 20;
const contact_frames = pressures.len * steps_per_pressure;
pub const frame_count = contact_frames + 3;

pub const Frame = struct {
    phase: enum { hover, contact, drag, lift, leave },
    x: i32,
    y: i32,
    pressure: i32 = 0,
    sample: bool = false,
};

pub fn plan(start_x: i32, y: i32, end_x: i32) error{InvalidStroke}![frame_count]Frame {
    if (start_x < 0 or y < 0 or y > axis_max or end_x > axis_max or
        end_x - @as(i64, start_x) < contact_frames - 1)
        return error.InvalidStroke;

    var frames: [frame_count]Frame = undefined;
    frames[0] = .{ .phase = .hover, .x = start_x, .y = y };
    for (0..contact_frames) |index| {
        const step: i32 = @intCast(index);
        frames[index + 1] = .{
            .phase = if (index == 0) .contact else .drag,
            .x = start_x + @divTrunc((end_x - start_x) * step, @as(i32, contact_frames - 1)),
            .y = y,
            .pressure = pressures[index / steps_per_pressure],
            .sample = index % steps_per_pressure == steps_per_pressure / 2,
        };
    }
    frames[frame_count - 2] = .{ .phase = .lift, .x = end_x, .y = y };
    frames[frame_count - 1] = .{ .phase = .leave, .x = end_x, .y = y };
    return frames;
}

test "stroke has ordered transitions and eight stable measurement positions" {
    const frames = try plan(100, 200, 1050);
    try std.testing.expectEqual(.hover, frames[0].phase);
    try std.testing.expectEqual(.contact, frames[1].phase);
    try std.testing.expectEqual(.drag, frames[frame_count - 3].phase);
    try std.testing.expectEqual(.lift, frames[frame_count - 2].phase);
    try std.testing.expectEqual(.leave, frames[frame_count - 1].phase);
    try std.testing.expectEqual(@as(i32, 1050), frames[frame_count - 3].x);
    try std.testing.expectEqual(@as(i32, 0), frames[frame_count - 2].pressure);

    var sample_index: usize = 0;
    for (frames[1 .. frame_count - 2], 0..) |frame, index| {
        try std.testing.expectEqual(pressures[index / steps_per_pressure], frame.pressure);
        if (index != 0) try std.testing.expect(frame.x > frames[index].x);
        if (frame.sample) {
            try std.testing.expectEqual(pressures[sample_index], frame.pressure);
            sample_index += 1;
        }
    }
    try std.testing.expectEqual(pressures.len, sample_index);
    try std.testing.expectError(error.InvalidStroke, plan(100, 200, 101));
    try std.testing.expectError(error.InvalidStroke, plan(100, 200, std.math.minInt(i32)));
}
