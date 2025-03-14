const std = @import("std");
const sdk = @import("sdk");
const tier0 = @import("modules.zig").tier0;

const Context = union(enum) {
    color: sdk.Color,
    dev: void,
};

fn writeFn(ctx: Context, bytes: []const u8) error{}!usize {
    if (bytes[0] == 0x1B) {
        // Console color code, possibly from a stack trace.
        // Ignore up to the terminating 'm'
        if (std.mem.indexOfScalar(u8, bytes, 'm')) |len| {
            return len + 1;
        }
    }

    switch (ctx) {
        .color => |c| tier0.colorMsg(&c, "%.*s", bytes.len, bytes.ptr),
        .dev => tier0.devMsg("%.*s", bytes.len, bytes.ptr),
    }
    return bytes.len;
}

var log_mutex: std.Thread.Mutex = .{};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (!tier0.ready) return;

    const scope_prefix = if (scope == .default) "" else ("[" ++ @tagName(scope) ++ "] ");
    const ctx: Context = switch (level) {
        .err => .{ .color = .{ .r = 255, .g = 90, .b = 90 } },
        .warn => .{ .color = .{ .r = 255, .g = 190, .b = 60 } },
        .info => .{
            .color = if (scope == .default) .{
                .r = 255,
                .g = 255,
                .b = 255,
            } else .{
                .r = 100,
                .g = 255,
                .b = 255,
            },
        },
        .debug => .dev,
    };

    log_mutex.lock();
    defer log_mutex.unlock();

    std.fmt.format(
        std.io.Writer(Context, error{}, writeFn){ .context = ctx },
        scope_prefix ++ format ++ "\n",
        args,
    ) catch unreachable;
}

pub fn colorLog(
    color: sdk.Color,
    comptime format: []const u8,
    args: anytype,
) void {
    std.fmt.format(
        std.io.Writer(Context, error{}, writeFn){ .context = .{
            .color = color,
        } },
        format ++ "\n",
        args,
    ) catch unreachable;
}
