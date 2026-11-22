const std = @import("std");
const port = @import("port.zig");
const contract = @import("contract.zig");
comptime {
    if (!std.debug.runtime_safety) @compileError("Ziggify native libraries require Debug or ReleaseSafe");
}
const gpa = std.heap.smp_allocator;
const Result = extern struct { data: ?[*]const u8 = null, len: usize = 0, owner: u64 = 0 };
const Allocation = struct { id: u64, bytes: []u8, next: ?*Allocation };
const Token = struct { id: u64, flag: std.atomic.Value(bool), refs: usize = 1, next: ?*Token };
var mutex: std.atomic.Mutex = .unlocked;
var results: ?*Allocation = null;
var tokens: ?*Token = null;
var next_id: u64 = 1;
fn lock() void {
    while (!mutex.tryLock()) std.Thread.yield() catch {};
}
fn id() u64 {
    const result = next_id;
    next_id = std.math.add(u64, next_id, 1) catch @panic("handle space exhausted");
    return result;
}

export fn ziggify_abi_version() u32 {
    return 1;
}
export fn ziggify_cancel_new() u64 {
    const t = gpa.create(Token) catch return 0;
    lock();
    defer mutex.unlock();
    t.* = .{ .id = id(), .flag = .init(false), .next = tokens };
    tokens = t;
    return t.id;
}
export fn ziggify_cancel(handle: u64) u32 {
    lock();
    defer mutex.unlock();
    var cursor = tokens;
    while (cursor) |t| : (cursor = t.next) if (t.id == handle) {
        t.flag.store(true, .release);
        return 0;
    };
    return 6;
}
export fn ziggify_cancel_free(handle: u64) u32 {
    if (handle == 0) return 0;
    lock();
    var cursor = &tokens;
    while (cursor.*) |t| {
        if (t.id == handle) {
            cursor.* = t.next;
            t.refs -= 1;
            const destroy = t.refs == 0;
            mutex.unlock();
            if (destroy) gpa.destroy(t);
            return 0;
        }
        cursor = &t.next;
    }
    mutex.unlock();
    return 6;
}
fn acquire(handle: u64) ?*Token {
    lock();
    defer mutex.unlock();
    var cursor = tokens;
    while (cursor) |t| : (cursor = t.next) if (t.id == handle) {
        t.refs += 1;
        return t;
    };
    return null;
}
fn drop(t: *Token) void {
    lock();
    t.refs -= 1;
    const destroy = t.refs == 0;
    mutex.unlock();
    if (destroy) gpa.destroy(t);
}
export fn ziggify_release(output: ?*Result) u32 {
    const out = output orelse return 1;
    if (out.owner == 0) return if (out.data == null and out.len == 0) 0 else 6;
    lock();
    var cursor = &results;
    while (cursor.*) |allocation| {
        if (allocation.id == out.owner) {
            cursor.* = allocation.next;
            mutex.unlock();
            gpa.free(allocation.bytes);
            gpa.destroy(allocation);
            out.* = .{};
            return 0;
        }
        cursor = &allocation.next;
    }
    mutex.unlock();
    out.* = .{};
    return 6;
}
fn assign(out: *Result, bytes: []u8) u32 {
    const allocation = gpa.create(Allocation) catch {
        gpa.free(bytes);
        return 3;
    };
    lock();
    defer mutex.unlock();
    allocation.* = .{ .id = id(), .bytes = bytes, .next = results };
    results = allocation;
    out.* = .{ .data = bytes.ptr, .len = bytes.len, .owner = allocation.id };
    return 0;
}
fn failure(out: *Result, status: u32, name: []const u8) u32 {
    const bytes = std.json.Stringify.valueAlloc(gpa, .{ .@"error" = .{ .type = name } }, .{}) catch return 3;
    const assigned = assign(out, bytes);
    return if (assigned == 0) status else assigned;
}

fn inputBudget(a: std.mem.Allocator, input: []const u8, context: contract.Context) !void {
    var scanner = std.json.Scanner.initCompleteInput(a, input);
    defer scanner.deinit();
    var depth: usize = 0;
    var tokens_seen: usize = 0;
    while (true) {
        try context.check();
        const token = scanner.next() catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return error.InvalidJson,
        };
        tokens_seen += 1;
        if (tokens_seen > 1000000) return error.InputTooComplex;
        switch (token) {
            .object_begin, .array_begin => {
                depth += 1;
                if (depth > 64) return error.InputTooDeep;
            },
            .object_end, .array_end => depth -= 1,
            .end_of_document => return,
            else => {},
        }
    }
}
fn outputBudget(value: std.json.Value, depth: usize, remaining: *usize, context: contract.Context) !void {
    try context.check();
    if (depth > 64) return error.OutputTooDeep;
    if (remaining.* == 0) return error.OutputTooComplex;
    remaining.* -= 1;
    switch (value) {
        .array => |array| for (array.items) |child| try outputBudget(child, depth + 1, remaining, context),
        .object => |object| {
            var it = object.iterator();
            while (it.next()) |entry| try outputBudget(entry.value_ptr.*, depth + 1, remaining, context);
        },
        .string, .number_string => |text| if (text.len > contract.limit) return error.OutputTooLarge,
        else => {},
    }
}
pub fn evaluate(a: std.mem.Allocator, input: []const u8, context: contract.Context) ![]u8 {
    try inputBudget(a, input, context);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    try context.check();
    const request = std.json.parseFromSlice(std.json.Value, arena.allocator(), input, .{ .allocate = .alloc_always, .max_value_len = contract.limit }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return error.InvalidJson,
    };
    const value = try port.call(arena.allocator(), request.value, context);
    try context.check();
    var remaining: usize = 1000000;
    try outputBudget(value, 0, &remaining, context);
    const output = try std.json.Stringify.valueAlloc(a, value, .{});
    if (output.len > contract.limit) {
        a.free(output);
        return error.OutputTooLarge;
    }
    return output;
}
export fn ziggify_call(input: ?[*]const u8, length: usize, cancellation: u64, output: ?*Result) u32 {
    const out = output orelse return 1;
    if (out.owner != 0 or out.data != null or out.len != 0) return 6;
    if (length > contract.limit) return failure(out, 5, "InputTooLarge");
    if (input == null and length != 0) return failure(out, 1, "InvalidArgument");
    const token = if (cancellation != 0) acquire(cancellation) orelse return failure(out, 6, "InvalidHandle") else null;
    defer if (token) |t| drop(t);
    if (!port.implemented) return failure(out, 7, "Unported");
    const bytes = if (input) |p| p[0..length] else "";
    const response = evaluate(gpa, bytes, .{ .flag = if (token) |t| &t.flag else null }) catch |err| {
        const status: u32 = switch (err) {
            error.OutOfMemory => 3,
            error.Canceled => 4,
            error.OutputTooLarge, error.InputTooDeep, error.InputTooComplex, error.OutputTooDeep, error.OutputTooComplex => 5,
            error.InvalidJson => 1,
            else => 2,
        };
        return failure(out, status, @errorName(err));
    };
    return assign(out, response);
}
export fn ziggify_live_allocations() usize {
    lock();
    defer mutex.unlock();
    var n: usize = 0;
    var cursor = results;
    while (cursor) |r| : (cursor = r.next) n += 1;
    return n;
}
fn allocationCase(a: std.mem.Allocator, input: []const u8) !void {
    const result = evaluate(a, input, .{}) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return,
    };
    defer a.free(result);
}
test "all recorded native requests are leak checked under every allocation failure" {
    try std.testing.expect(port.implemented);
    const cases = try std.json.parseFromSlice([]const []const u8, std.testing.allocator, @embedFile("memory-cases.json"), .{});
    defer cases.deinit();
    for (cases.value) |input| try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{input});
}
