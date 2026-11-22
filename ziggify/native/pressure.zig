// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");

pub const resolution = 1024;
pub const max_points = 32;

pub const Point = struct {
    x: f64,
    y: f64,
    corner: bool = false,
};

/// Precomputed global pressure curve. Build once when settings change, then
/// map each incoming sample in constant time. Owns its table inline.
pub const PressureCurve = struct {
    table: [resolution + 1]f64,

    pub fn init(points: []const Point) error{InvalidCurve}!PressureCurve {
        if (points.len == 0 or points.len > max_points) return error.InvalidCurve;
        for (points, 0..) |point, i| {
            if (!inUnitInterval(point.x) or !inUnitInterval(point.y)) return error.InvalidCurve;
            if (i > 0 and point.x - points[i - 1].x < 1.0 / @as(f64, resolution)) {
                return error.InvalidCurve;
            }
        }

        var curve: PressureCurve = undefined;
        if (points.len == 1) {
            @memset(&curve.table, points[0].y);
            return curve;
        }

        const second_derivatives = solveSecondDerivatives(points);
        var interval: usize = 0;
        for (&curve.table, 0..) |*entry, index| {
            const x = std.math.clamp(@as(f64, @floatFromInt(index)) / resolution, points[0].x, points[points.len - 1].x);
            while (interval + 2 < points.len and x >= points[interval + 1].x) {
                interval += 1;
            }
            const left = points[interval];
            const right = points[interval + 1];
            const width = right.x - left.x;
            const t = (x - left.x) / width;
            const s = 1 - t;
            const correction = (s * s * s - s) * second_derivatives[interval] +
                (t * t * t - t) * second_derivatives[interval + 1];
            entry.* = std.math.clamp(s * left.y + t * right.y + correction * width * width / 6, 0, 1);
        }
        return curve;
    }

    /// Krita indexes the table with clamped pressure, then applies the
    /// input's sign to the interpolated result.
    pub fn map(curve: *const PressureCurve, pressure: f64) error{InvalidPressure}!f64 {
        if (!std.math.isFinite(pressure)) return error.InvalidPressure;
        const position = std.math.clamp(pressure, 0, 1) * resolution;
        const lower: usize = @intFromFloat(@floor(position));
        const upper: usize = @intFromFloat(@ceil(position));
        const fraction = position - @floor(position);
        const magnitude = if (fraction < 1e-6) curve.table[lower] else if (fraction > 1 - 1e-6)
            curve.table[upper]
        else
            curve.table[lower] + fraction * (curve.table[upper] - curve.table[lower]);
        return if (pressure < 0) -magnitude else magnitude;
    }
};

fn inUnitInterval(value: f64) bool {
    return value >= 0 and value <= 1;
}

/// Solve the natural cubic spline's tridiagonal system in local coordinates.
/// Corners end one natural spline and begin the next at the same knot.
fn solveSecondDerivatives(points: []const Point) [max_points]f64 {
    var upper: [max_points]f64 = @splat(0);
    var second: [max_points]f64 = @splat(0);
    for (1..points.len - 1) |i| {
        if (points[i].corner) continue;
        const left_width = points[i].x - points[i - 1].x;
        const right_width = points[i + 1].x - points[i].x;
        const left_slope = (points[i].y - points[i - 1].y) / left_width;
        const right_slope = (points[i + 1].y - points[i].y) / right_width;
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

test "map reuses a prepared curve and preserves signed pressure" {
    const curve = try PressureCurve.init(&.{ .{ .x = 0, .y = 0.25 }, .{ .x = 1, .y = 0.75 } });
    try std.testing.expectEqual(@as(f64, -0.25), try curve.map(-0.5));
    try std.testing.expectEqual(@as(f64, 0.5), try curve.map(0.5));
    try std.testing.expectEqual(@as(f64, 0.75), try curve.map(2));
    try std.testing.expectError(error.InvalidPressure, curve.map(std.math.nan(f64)));
}

test "a corner splits two natural spline segments" {
    const points = [_]Point{ .{ .x = 0, .y = 1 }, .{ .x = 0.5, .y = 0, .corner = true }, .{ .x = 1, .y = 1 } };
    const corner = try PressureCurve.init(&points);
    var smooth_points = points;
    smooth_points[1].corner = false;
    const smooth = try PressureCurve.init(&smooth_points);
    try std.testing.expectEqual(@as(f64, 0.5), try corner.map(0.25));
    try std.testing.expectEqual(@as(f64, 0.3125), try smooth.map(0.25));
}
