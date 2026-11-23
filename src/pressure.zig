// SPDX-License-Identifier: Apache-2.0

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
    // Derivatives scaled by the interval width, ready for Hermite evaluation.
    tangents: [max_points - 1][2]f64 = undefined,

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
        if (points.len > 2) curve.prepareTangents(points);
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
        const delta = end.y - start.y;
        if (points.len == 2) return start.y + fraction * delta;

        const remaining = 1 - fraction;
        const tangents = curve.tangents[left];
        const base = start.y + delta * (fraction * fraction * (3 - 2 * fraction));
        const correction = fraction * remaining * (remaining * tangents[0] - fraction * tangents[1]);
        return std.math.clamp(base + correction, @min(start.y, end.y), @max(start.y, end.y));
    }

    fn prepareTangents(curve: *PressureCurve, points: []const Point) void {
        const intervals = points.len - 1;
        // Wide intermediates keep the secants finite even for adjacent
        // subnormal X coordinates. Mapping uses only f64.
        var widths: [max_points - 1]f128 = undefined;
        var secants: [max_points - 1]f128 = undefined;
        for (0..intervals) |i| {
            widths[i] = @as(f128, points[i + 1].x) - points[i].x;
            secants[i] = (@as(f128, points[i + 1].y) - points[i].y) / widths[i];
        }

        var slopes: [max_points]f128 = undefined;
        slopes[0] = endpointSlope(widths[0], widths[1], secants[0], secants[1]);
        slopes[intervals] = endpointSlope(
            widths[intervals - 1],
            widths[intervals - 2],
            secants[intervals - 1],
            secants[intervals - 2],
        );
        for (1..intervals) |i| {
            slopes[i] = interiorSlope(widths[i - 1], widths[i], secants[i - 1], secants[i]);
        }
        for (0..intervals) |i| {
            curve.tangents[i] = .{ @floatCast(slopes[i] * widths[i]), @floatCast(slopes[i + 1] * widths[i]) };
        }
    }
};

/// Fritsch–Butland weighted harmonic mean for a monotone Hermite interpolant.
fn interiorSlope(left_width: f128, right_width: f128, left: f128, right: f128) f128 {
    if (left == 0 or right == 0 or (left > 0) != (right > 0)) return 0;
    const left_weight = 2 * right_width + left_width;
    const right_weight = right_width + 2 * left_width;
    return (left_weight + right_weight) / (left_weight / left + right_weight / right);
}

fn endpointSlope(width: f128, next_width: f128, secant: f128, next_secant: f128) f128 {
    const slope = ((2 * width + next_width) * secant - width * next_secant) / (width + next_width);
    if (secant == 0 or (slope > 0) != (secant > 0)) return 0;
    if ((secant > 0) != (next_secant > 0) and @abs(slope) > @abs(3 * secant)) return 3 * secant;
    return slope;
}

fn isUnitValue(value: f64) bool {
    return value >= 0 and value <= 1;
}

test "curved segments pass through their anchors and meet with a common slope" {
    const curve = try PressureCurve.init(&.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0.5, .y = 0.75 },
        .{ .x = 1, .y = 1 },
    });

    try std.testing.expectApproxEqAbs(@as(f64, 0.453125), try curve.map(0.25), 1e-14);
    try std.testing.expectEqual(@as(f64, 0.75), try curve.map(0.5));
    try std.testing.expectApproxEqAbs(@as(f64, 0.921875), try curve.map(0.75), 1e-14);
    const step = 1e-6;
    const center = try curve.map(0.5);
    const left_slope = (center - try curve.map(0.5 - step)) / step;
    const right_slope = (try curve.map(0.5 + step) - center) / step;
    try std.testing.expectApproxEqAbs(left_slope, right_slope, 3e-6);
}

test "flat and descending segments stay between their anchors" {
    const points = [_]Point{
        .{ .x = 0, .y = 0.2 },
        .{ .x = 0.1, .y = 0.9 },
        .{ .x = 0.6, .y = 0.9 },
        .{ .x = 1, .y = 0.3 },
    };
    const curve = try PressureCurve.init(&points);
    for (points[0 .. points.len - 1], points[1..]) |start, end| {
        var previous = start.y;
        for (1..64) |step| {
            const x = start.x + (end.x - start.x) * @as(f64, @floatFromInt(step)) / 64;
            const value = try curve.map(x);
            try std.testing.expect(value >= @min(start.y, end.y) and value <= @max(start.y, end.y));
            try std.testing.expect(if (start.y <= end.y) value >= previous else value <= previous);
            previous = value;
        }
    }
}

test "closely spaced anchors remain finite" {
    const tiny: f64 = @bitCast(@as(u64, 1));
    const curve = try PressureCurve.init(&.{
        .{ .x = 0, .y = 0 },
        .{ .x = 2 * tiny, .y = 0.5 },
        .{ .x = 1, .y = 1 },
    });
    const mapped = try curve.map(tiny);
    try std.testing.expect(mapped > 0 and mapped < 0.5);
    try std.testing.expectEqual(@as(f64, 0.5), try curve.map(2 * tiny));
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
