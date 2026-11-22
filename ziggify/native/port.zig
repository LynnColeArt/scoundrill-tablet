// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const contract = @import("contract.zig");
const pressure = @import("pressure.zig");

pub const implemented = true;

pub fn call(a: std.mem.Allocator, request: std.json.Value, context: contract.Context) !std.json.Value {
    try context.check();
    if (request != .object) return error.InvalidRequest;
    const points = request.object.get("points") orelse return error.InvalidRequest;
    const samples = request.object.get("samples") orelse return error.InvalidRequest;
    if (points != .array or samples != .array or
        points.array.items.len > pressure.max_points or samples.array.items.len > 4096)
        return error.InvalidRequest;

    var knots: [pressure.max_points]pressure.Point = undefined;
    for (points.array.items, knots[0..points.array.items.len]) |point, *knot| {
        if (point != .object) return error.InvalidRequest;
        const x = point.object.get("x") orelse return error.InvalidRequest;
        const y = point.object.get("y") orelse return error.InvalidRequest;
        const corner = point.object.get("corner") orelse std.json.Value{ .bool = false };
        if (corner != .bool) return error.InvalidRequest;
        knot.* = .{ .x = try number(x), .y = try number(y), .corner = corner.bool };
    }
    const curve = pressure.PressureCurve.init(knots[0..points.array.items.len]) catch return error.InvalidRequest;
    var result = try std.json.Array.initCapacity(a, samples.array.items.len);
    for (samples.array.items) |sample| {
        try context.check();
        const mapped = curve.map(try number(sample)) catch return error.InvalidRequest;
        result.appendAssumeCapacity(.{ .integer = @intFromFloat(@round(mapped * 1e9)) });
    }
    return .{ .array = result };
}

fn number(value: std.json.Value) error{InvalidRequest}!f64 {
    return switch (value) {
        .integer => @floatFromInt(value.integer),
        .float => value.float,
        .number_string => std.fmt.parseFloat(f64, value.number_string) catch error.InvalidRequest,
        else => error.InvalidRequest,
    };
}

test {
    std.testing.refAllDecls(pressure);
}
