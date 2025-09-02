const std = @import("std");
const builtin = @import("builtin");
const windows = @import("core.zig").windows;

pub fn panicFn(msg: []const u8, first_trace_addr: ?usize) noreturn {
    var trace_buf: [64]u8 = undefined;
    const trace_str = if (first_trace_addr) |addr|
        std.fmt.bufPrint(&trace_buf, "0x{x}", .{addr}) catch "(format error)"
    else
        "(null)";

    if (builtin.os.tag == .windows) {
        const allocator = std.heap.page_allocator;
        const null_terminated_msg = std.fmt.allocPrintSentinel(
            allocator,
            \\Runtime Error!
            \\
            \\vkuroko failed at {s}
            \\
            \\{s}
        ,
            .{ trace_str, msg },
            0,
        ) catch "panic (and failed to format message)";
        _ = windows.MessageBoxA(
            null,
            null_terminated_msg.ptr,
            "Runtime Error",
            windows.MB_OK | windows.MB_ICONERROR,
        );
        allocator.free(null_terminated_msg);
    } else {
        std.debug.print(
            \\Runtime Error!
            \\vkuroko failed at {s}
            \\{s}
        , .{ trace_str, msg });
    }

    std.process.exit(1);
}
