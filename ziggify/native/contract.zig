const std = @import("std");
pub const limit = 16 * 1024 * 1024;
pub const Context = struct {
    flag: ?*const std.atomic.Value(bool) = null,
    pub fn check(c: Context) error{Canceled}!void {
        if (c.flag) |flag| if (flag.load(.acquire)) return error.Canceled;
    }
};
