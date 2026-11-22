// SPDX-License-Identifier: GPL-2.0-or-later

const std = @import("std");

pub const max_points = 32;

pub const Point = struct {
    x: f64,
    y: f64,
};

/// An application-wide response curve for normalized pressure.
/// Anchors are owned by the curve and can be reused across pen events.
pub const PressureCurve = struct {
    anchors: [max_points]Point,
    count: usize,

    pub fn init(points: []const Point) error{InvalidCurve}!PressureCurve {
        if (points.len == 0 or points.len > max_points) return error.InvalidCurve;

        var previous_x: f64 = -1;
        for (points) |point| {
            if (!isUnitValue(point.x) or !isUnitValue(point.y) or point.x <= previous_x) {
                return error.InvalidCurve;
            }
            previous_x = point.x;
        }

        var curve: PressureCurve = .{ .anchors = undefined, .count = points.len };
        @memcpy(curve.anchors[0..points.len], points);
        return curve;
    }

    pub fn map(curve: *const PressureCurve, pressure: f64) error{InvalidPressure}!f64 {
        if (!std.math.isFinite(pressure)) return error.InvalidPressure;

        const points = curve.anchors[0..curve.count];
        if (pressure <= points[0].x) return points[0].y;
        if (pressure >= points[points.len - 1].x) return points[points.len - 1].y;

        var left: usize = 0;
        var right = points.len - 1;
        while (right - left > 1) {
            const middle = left + (right - left) / 2;
            if (pressure < points[middle].x) {
                right = middle;
            } else {
                left = middle;
            }
        }

        const start = points[left];
        const end = points[right];
        const fraction = (pressure - start.x) / (end.x - start.x);
        return start.y + fraction * (end.y - start.y);
    }
};

fn isUnitValue(value: f64) bool {
    return value >= 0 and value <= 1;
}

test "anchors and linear segments" {
    const curve = try PressureCurve.init(&.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0.25, .y = 0.5 },
        .{ .x = 0.75, .y = 0.25 },
        .{ .x = 1, .y = 1 },
    });

    try std.testing.expectEqual(@as(f64, 0.25), try curve.map(0.125));
    try std.testing.expectEqual(@as(f64, 0.5), try curve.map(0.25));
    try std.testing.expectEqual(@as(f64, 0.375), try curve.map(0.5));
    try std.testing.expectEqual(@as(f64, 0.625), try curve.map(0.875));
}

test "holds endpoint values outside the anchors" {
    const curve = try PressureCurve.init(&.{ .{ .x = 0.25, .y = 0.125 }, .{ .x = 0.75, .y = 0.875 } });
    try std.testing.expectEqual(@as(f64, 0.125), try curve.map(-0.25));
    try std.testing.expectEqual(@as(f64, 0.875), try curve.map(1.25));
}

test "a one-anchor curve is constant" {
    const curve = try PressureCurve.init(&.{.{ .x = 0.5, .y = 0.25 }});
    for ([_]f64{ 0, 0.5, 1 }) |sample| {
        try std.testing.expectEqual(@as(f64, 0.25), try curve.map(sample));
    }
}

test "validates curve anchors and pressure" {
    try std.testing.expectError(error.InvalidCurve, PressureCurve.init(&.{}));
    try std.testing.expectError(error.InvalidCurve, PressureCurve.init(&.{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 1 } }));
    try std.testing.expectError(error.InvalidCurve, PressureCurve.init(&.{ .{ .x = 0.5, .y = 0 }, .{ .x = 0.25, .y = 1 } }));
    try std.testing.expectError(error.InvalidCurve, PressureCurve.init(&.{.{ .x = 0, .y = 1.5 }}));
    try std.testing.expectError(error.InvalidCurve, PressureCurve.init(&.{.{ .x = std.math.nan(f64), .y = 0 }}));

    const curve = try PressureCurve.init(&.{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 } });
    try std.testing.expectError(error.InvalidPressure, curve.map(std.math.nan(f64)));
    try std.testing.expectError(error.InvalidPressure, curve.map(std.math.inf(f64)));
}
