const std = @import("std");
const sdk = @import("sdk");
const tier0 = @import("modules.zig").tier0;
const PrintContext = struct {
    writer: std.Io.Writer,
    mode: union(enum) {
        color: sdk.Color,
        dev,
    },
    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const ctx: *PrintContext = @fieldParentPtr("writer", w);
        const bytes: []const u8 = b: {
            const buf = w.buffered();
            if (buf.len > 0) {
                w.end = 0; // unbuffer everything
                break :b buf;
            }
            const slices = switch (splat) {
                0 => data[0 .. data.len - 1],
                else => data,
            };
            for (slices) |s| {
                if (s.len > 0) break :b s;
            }
            unreachable;
        };
        var skip: usize = 0;
        while (skip < bytes.len and bytes[skip] == 0x1B) {
            // Console color code, possibly from a stack trace. Ignore up to the terminating 'm'
            skip += 1;
            skip += std.mem.indexOfScalar(u8, bytes[skip..], 'm') orelse break;
        }
        const str = bytes[skip..];
        switch (ctx.mode) {
            .color => |c| tier0.colorMsg(&c, "%.*s", str.len, str.ptr),
            .dev => tier0.devMsg("%.*s", str.len, str.ptr),
        }
        return bytes.len;
    }
};

// TODO: the mutex is a stopgap solution, but really we should just send
// this stuff over to the main thread
var log_mutex: std.Thread.Mutex = .{};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (!tier0.ready) return; // we can't log if we don't have console

    var buf: [1024]u8 = undefined;
    var print_ctx: PrintContext = .{
        .writer = .{
            .vtable = &.{ .drain = &PrintContext.drain },
            .buffer = &buf,
        },
        .mode = switch (level) {
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
        },
    };

    log_mutex.lock();
    defer log_mutex.unlock();

    const scope_prefix = if (scope == .default) "" else ("[" ++ @tagName(scope) ++ "] ");
    print_ctx.writer.print(scope_prefix ++ format ++ "\n", args) catch unreachable;
    print_ctx.writer.flush() catch unreachable;
}

pub fn colorLog(
    color: sdk.Color,
    comptime format: []const u8,
    args: anytype,
) void {
    if (!tier0.ready) return; // we can't log if we don't have console

    var buf: [1024]u8 = undefined;
    var print_ctx: PrintContext = .{
        .writer = .{
            .vtable = &.{ .drain = &PrintContext.drain },
            .buffer = &buf,
        },
        .mode = .{
            .color = color,
        },
    };

    log_mutex.lock();
    defer log_mutex.unlock();

    print_ctx.writer.print(format ++ "\n", args) catch unreachable;
    print_ctx.writer.flush() catch unreachable;
}
