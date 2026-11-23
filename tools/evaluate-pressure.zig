// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const tablet = @import("scoundrill_tablet");
const ppm = @import("ppm.zig");

const Capture = struct {
    input_pressures: []const f64,
    columns: []const usize,
    y_start: usize,
    y_end: usize,
    identity_image: []const u8,
    curves: []const struct {
        name: []const u8,
        points: []const tablet.Point,
        image: []const u8,
    },
};

const Errors = struct {
    total: f64 = 0,
    peak: f64 = 0,
    count: usize = 0,

    fn add(errors: *Errors, delta: f64) void {
        errors.total += delta;
        errors.peak = @max(errors.peak, delta);
        errors.count += 1;
    }

    fn mean(errors: Errors) f64 {
        return errors.total / @as(f64, @floatFromInt(errors.count));
    }
};

pub fn compare(io: std.Io, allocator: std.mem.Allocator, path: []const u8, out: *std.Io.Writer) !void {
    const json = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024));
    defer allocator.free(json);
    const parsed = try std.json.parseFromSlice(Capture, allocator, json, .{});
    defer parsed.deinit();
    const capture = parsed.value;

    if (capture.columns.len < 2 or capture.columns.len > tablet.max_points or
        capture.columns.len != capture.input_pressures.len or capture.curves.len == 0)
        return error.InvalidCapture;
    var previous: f64 = -1;
    for (capture.input_pressures) |input| {
        if (!(input >= 0 and input <= 1 and input > previous)) return error.InvalidCapture;
        previous = input;
    }

    const directory = std.fs.path.dirname(path) orelse ".";
    var measurement_buffer: [tablet.max_points]f64 = undefined;
    const measurements = measurement_buffer[0..capture.columns.len];
    try readWidths(io, allocator, directory, capture.identity_image, capture, measurements);
    var calibration_buffer: [tablet.max_points]tablet.Point = undefined;
    const calibration = calibration_buffer[0..capture.columns.len];
    for (capture.input_pressures, measurements, calibration) |input, width, *point| {
        point.* = .{ .x = input, .y = width };
    }

    try out.writeAll("curve,linear_mae_px,smooth_mae_px,linear_max_px,smooth_max_px\n");
    var total_linear: Errors = .{};
    var total_smooth: Errors = .{};
    for (capture.curves) |item| {
        const smooth = try tablet.PressureCurve.init(item.points);
        try readWidths(io, allocator, directory, item.image, capture, measurements);
        var linear_errors: Errors = .{};
        var smooth_errors: Errors = .{};
        for (capture.input_pressures, measurements) |input, measured| {
            const linear_delta = @abs(interpolate(calibration, interpolate(item.points, input)) - measured);
            const smooth_delta = @abs(interpolate(calibration, try smooth.map(input)) - measured);
            linear_errors.add(linear_delta);
            smooth_errors.add(smooth_delta);
            total_linear.add(linear_delta);
            total_smooth.add(smooth_delta);
        }
        try printErrors(out, item.name, linear_errors, smooth_errors);
    }
    try printErrors(out, "all", total_linear, total_smooth);
}

fn readWidths(io: std.Io, allocator: std.mem.Allocator, directory: []const u8, file: []const u8, capture: Capture, widths: []f64) !void {
    const path = try std.fs.path.join(allocator, &.{ directory, file });
    defer allocator.free(path);
    const bytes = try ppm.readFile(io, allocator, path);
    defer allocator.free(bytes);
    const image = try ppm.Image.parse(bytes);
    for (capture.columns, widths) |column, *width| {
        width.* = @floatFromInt(try image.strokeWidth(column, capture.y_start, capture.y_end));
    }
}

/// Linear interpolation is used for both the previous global mapper and
/// the independent identity calibration. Calibration Y values are pixel widths.
fn interpolate(points: []const tablet.Point, input: f64) f64 {
    if (input <= points[0].x) return points[0].y;
    for (points[0 .. points.len - 1], points[1..]) |left, right| {
        if (input <= right.x) {
            const fraction = (input - left.x) / (right.x - left.x);
            return left.y + fraction * (right.y - left.y);
        }
    }
    return points[points.len - 1].y;
}

fn printErrors(out: *std.Io.Writer, name: []const u8, linear: Errors, smooth: Errors) !void {
    try out.print("{s},{d:.3},{d:.3},{d:.3},{d:.3}\n", .{ name, linear.mean(), smooth.mean(), linear.peak, smooth.peak });
}
