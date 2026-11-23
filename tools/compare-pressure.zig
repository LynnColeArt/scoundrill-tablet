// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const tablet = @import("scoundrill_tablet");

const Case = struct {
    name: []const u8,
    points: []const tablet.Point,
    samples: []const [2]f64,
};

const Report = struct {
    absolute_error_sum: f64 = 0,
    maximum_error: f64 = 0,
    worst_raw: f64 = 0,
    reference: f64 = 0,
    candidate: f64 = 0,
};

pub fn compare(io: std.Io, allocator: std.mem.Allocator, path: []const u8, tolerance: ?f64, out: *std.Io.Writer) !void {
    if (tolerance) |limit| {
        if (!normalized(limit)) return error.InvalidTolerance;
    }
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(struct { cases: []const Case }, allocator, bytes, .{});
    defer parsed.deinit();
    const cases = parsed.value.cases;
    if (cases.len == 0) return error.InvalidTrace;

    try out.writeAll("case,samples,mean_abs_error,max_abs_error,worst_raw,reference,candidate\n");
    var maximum: f64 = 0;
    for (cases) |item| {
        const report = try analyze(item);
        const mean = report.absolute_error_sum / @as(f64, @floatFromInt(item.samples.len));
        try out.print("{s},{d},{e:.9},{e:.9},{d:.9},{d:.9},{d:.9}\n", .{
            item.name, item.samples.len, mean, report.maximum_error, report.worst_raw, report.reference, report.candidate,
        });
        maximum = @max(maximum, report.maximum_error);
    }

    if (tolerance) |limit| {
        if (maximum > limit) {
            try out.flush();
            return error.PressureMismatch;
        }
    }
}

fn analyze(item: Case) !Report {
    if (item.name.len == 0 or item.samples.len == 0) return error.InvalidTrace;
    for (item.name) |character| {
        if (!std.ascii.isAlphanumeric(character) and character != '-' and character != '_') return error.InvalidTrace;
    }

    const curve = try tablet.PressureCurve.init(item.points);
    var report: Report = .{};
    for (item.samples, 0..) |sample, index| {
        const raw, const reference = sample;
        if (!normalized(raw) or !normalized(reference)) return error.InvalidTrace;
        const candidate = try curve.map(raw);
        const delta = @abs(candidate - reference);
        report.absolute_error_sum += delta;
        if (index == 0 or delta > report.maximum_error) {
            report.maximum_error = delta;
            report.worst_raw = raw;
            report.reference = reference;
            report.candidate = candidate;
        }
    }
    return report;
}

fn normalized(value: f64) bool {
    return value >= 0 and value <= 1;
}

test "reports the input and values behind the largest discrepancy" {
    const report = try analyze(.{
        .name = "identity",
        .points = &.{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 } },
        .samples = &.{ .{ 0, 0 }, .{ 0.25, 0.375 }, .{ 1, 1 } },
    });
    try std.testing.expectEqual(@as(f64, 0.125), report.maximum_error);
    try std.testing.expectEqual(@as(f64, 0.25), report.worst_raw);
    try std.testing.expectEqual(@as(f64, 0.375), report.reference);
    try std.testing.expectEqual(@as(f64, 0.25), report.candidate);
}
