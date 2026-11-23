// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

pub const max_points = 32;

pub const Point = struct {
    x: f64,
    y: f64,
};

pub const table_intervals = 1024;

/// Prepared natural cubic spline sampled on a uniform pressure grid.
/// Owns its table inline. Rebuild when settings change and reuse per event.
pub const PressureCurve = struct {
    table: [table_intervals + 1]f64,

    pub fn init(points: []const Point) error{InvalidCurve}!PressureCurve {
        if (points.len == 0 or points.len > max_points) return error.InvalidCurve;
        var previous_x: f64 = -1;
        for (points) |point| {
            if (!isUnitValue(point.x) or !isUnitValue(point.y) or point.x <= previous_x)
                return error.InvalidCurve;
            previous_x = point.x;
        }

        var curve: PressureCurve = undefined;
        if (points.len == 1) {
            @memset(&curve.table, points[0].y);
            return curve;
        }
        const second = secondDerivatives(points);
        var interval: usize = 0;
        for (&curve.table, 0..) |*entry, index| {
            const x: f128 = @as(f128, @floatFromInt(index)) / table_intervals;
            while (interval + 2 < points.len and x >= points[interval + 1].x) {
                interval += 1;
            }
            const left = points[interval];
            const right = points[interval + 1];
            const width = @as(f128, right.x) - left.x;
            const bounded_x = std.math.clamp(x, points[0].x, points[points.len - 1].x);
            const t = (bounded_x - left.x) / width;
            const u = 1 - t;
            const curvature = (u * u * u - u) * second[interval] +
                (t * t * t - t) * second[interval + 1];
            const y = u * left.y + t * right.y + width * width * curvature / 6;
            entry.* = @floatCast(std.math.clamp(y, 0, 1));
        }
        return curve;
    }

    pub fn map(curve: *const PressureCurve, pressure: f64) error{InvalidPressure}!f64 {
        if (!std.math.isFinite(pressure)) return error.InvalidPressure;
        const position = std.math.clamp(pressure, 0, 1) * table_intervals;
        const lower: usize = @intFromFloat(@floor(position));
        const upper: usize = @intFromFloat(@ceil(position));
        const fraction = position - @floor(position);
        return curve.table[lower] + fraction * (curve.table[upper] - curve.table[lower]);
    }
};

/// Natural endpoint conditions and a tridiagonal solve for second derivatives.
/// f128 keeps initialization finite for arbitrarily close valid f64 anchors.
fn secondDerivatives(points: []const Point) [max_points]f128 {
    var upper: [max_points]f128 = @splat(0);
    var second: [max_points]f128 = @splat(0);
    for (1..points.len - 1) |i| {
        const left_width = @as(f128, points[i].x) - points[i - 1].x;
        const right_width = @as(f128, points[i + 1].x) - points[i].x;
        const left_slope = (@as(f128, points[i].y) - points[i - 1].y) / left_width;
        const right_slope = (@as(f128, points[i + 1].y) - points[i].y) / right_width;
        const diagonal = 2 * (left_width + right_width) - left_width * upper[i - 1];
        upper[i] = right_width / diagonal;
        second[i] = (6 * (right_slope - left_slope) - left_width * second[i - 1]) / diagonal;
    }
    var i = points.len - 1;
    while (i > 1) {
        i -= 1;
        second[i] -= upper[i] * second[i + 1];
    }
    return second;
}

fn isUnitValue(value: f64) bool {
    return value >= 0 and value <= 1;
}

test "natural spline samples preserve curvature and interpolate table entries" {
    const curve = try PressureCurve.init(&.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0.5, .y = 0.75 },
        .{ .x = 1, .y = 1 },
    });
    try std.testing.expectApproxEqAbs(@as(f64, 0.421875), try curve.map(0.25), 1e-14);
    try std.testing.expectEqual(@as(f64, 0.75), try curve.map(0.5));
    const halfway: f64 = @as(f64, 256.5) / table_intervals;
    try std.testing.expectEqual((curve.table[256] + curve.table[257]) / 2, try curve.map(halfway));
}

test "equal height anchors permit overshoot while outputs stay normalized" {
    const curve = try PressureCurve.init(&.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0.3, .y = 0.65 },
        .{ .x = 0.65, .y = 0.65 },
        .{ .x = 1, .y = 1 },
    });
    try std.testing.expect((try curve.map(0.4)) > 0.69);
    for (curve.table) |value| try std.testing.expect(isUnitValue(value));
    const clipping = try PressureCurve.init(&.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0.1, .y = 1 },
        .{ .x = 1, .y = 1 },
    });
    try std.testing.expectEqual(@as(f64, 1), try clipping.map(0.5));
}

test "closely spaced anchors produce a finite normalized table" {
    const tiny: f64 = @bitCast(@as(u64, 1));
    const curve = try PressureCurve.init(&.{
        .{ .x = 0, .y = 0 },
        .{ .x = 2 * tiny, .y = 0.5 },
        .{ .x = 1, .y = 1 },
    });
    for (curve.table) |value| try std.testing.expect(isUnitValue(value));
    try std.testing.expectEqual(@as(f64, 0), try curve.map(0));
    try std.testing.expectEqual(@as(f64, 1), try curve.map(1));
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
