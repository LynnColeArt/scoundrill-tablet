// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

pub const Image = struct {
    width: usize,
    height: usize,
    rgb: []const u8,

    pub fn parse(bytes: []const u8) error{InvalidPpm}!Image {
        var input = bytes;
        if (!std.mem.eql(u8, token(&input), "P6")) return error.InvalidPpm;
        const width = std.fmt.parseUnsigned(usize, token(&input), 10) catch return error.InvalidPpm;
        const height = std.fmt.parseUnsigned(usize, token(&input), 10) catch return error.InvalidPpm;
        if (!std.mem.eql(u8, token(&input), "255")) return error.InvalidPpm;
        if (input.len == 0 or !std.ascii.isWhitespace(input[0])) return error.InvalidPpm;
        // After maxval, the single separator precedes binary data, which
        // may itself begin with whitespace or a comment marker.
        input = input[1..];

        if (width == 0 or height == 0) return error.InvalidPpm;
        const row_bytes = std.math.mul(usize, width, 3) catch return error.InvalidPpm;
        const total_bytes = std.math.mul(usize, height, row_bytes) catch return error.InvalidPpm;
        if (input.len != total_bytes) return error.InvalidPpm;
        return .{ .width = width, .height = height, .rgb = input };
    }

    /// Counts pixels at least half covered by a black stroke on white.
    /// y_start is inclusive and y_end exclusive.
    pub fn strokeWidth(image: Image, x: usize, y_start: usize, y_end: usize) error{InvalidMeasurement}!usize {
        if (x >= image.width or y_start >= y_end or y_end > image.height)
            return error.InvalidMeasurement;

        var width: usize = 0;
        for (y_start..y_end) |y| {
            const offset = (y * image.width + x) * 3;
            const rgb = image.rgb[offset..][0..3];
            const intensity = @as(u16, rgb[0]) + @as(u16, rgb[1]) + @as(u16, rgb[2]);
            if (intensity < 384) width += 1;
        }
        return width;
    }
};

fn token(input: *[]const u8) []const u8 {
    while (input.len != 0) {
        if (std.ascii.isWhitespace(input.*[0])) {
            input.* = input.*[1..];
        } else if (input.*[0] == '#') {
            const end = std.mem.indexOfScalar(u8, input.*, '\n') orelse input.len;
            input.* = input.*[end..];
        } else break;
    }
    const bytes = input.*;
    var end: usize = 0;
    while (end < bytes.len and !std.ascii.isWhitespace(bytes[end]) and bytes[end] != '#') : (end += 1) {}
    input.* = bytes[end..];
    return bytes[0..end];
}

test "reads P6 comments without discarding binary whitespace" {
    const image = try Image.parse("P6\n# test\n2 2\n255\n" ++
        "\x20\x20\x20" ++ "\xff\xff\xff" ++
        "\x80\x80\x80" ++ "\x7f\x7f\x7f");
    try std.testing.expectEqual(@as(usize, 1), try image.strokeWidth(0, 0, 2));
    try std.testing.expectEqual(@as(usize, 1), try image.strokeWidth(1, 0, 2));
    try std.testing.expectEqual(@as(usize, 0), try image.strokeWidth(1, 0, 1));
    try std.testing.expectError(error.InvalidMeasurement, image.strokeWidth(2, 0, 2));
    try std.testing.expectError(error.InvalidPpm, Image.parse("P6\n1 1\n255\n\x00\x00"));
}
