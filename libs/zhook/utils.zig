const std = @import("std");
const builtin = @import("builtin");

pub const windows = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
    @cInclude("psapi.h");
});

pub inline fn isHex(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

pub fn makeHex(comptime str: []const u8) []const u8 {
    return comptime blk: {
        @setEvalBranchQuota(10000);
        var it = std.mem.splitSequence(u8, str, " ");
        var pat: []const u8 = &.{};

        while (it.next()) |byte| {
            if (byte.len != 2) {
                @compileError("Each byte should be 2 characters");
            }
            if (isHex(byte[0])) {
                if (!isHex(byte[1])) {
                    @compileError("The second hex digit is missing");
                }
                const n = try std.fmt.parseInt(u8, byte, 16);
                pat = pat ++ .{n};
            } else {
                @compileError("Only hex digits are allowed");
            }
        }
        break :blk pat;
    };
}

pub fn mprotect(ptr: *anyopaque, len: usize) !void {
    if (builtin.os.tag == .windows) {
        var old_protect: std.os.windows.DWORD = undefined;
        try std.os.windows.VirtualProtect(ptr, len, std.os.windows.PAGE_EXECUTE_READWRITE, &old_protect);
    } else {
        const page_size = std.heap.page_size_min;
        const aligned_ptr: *align(page_size) anyopaque = @ptrFromInt(@intFromPtr(ptr) & ~(page_size - 1));
        const aligned_len = len + (page_size - 1) & ~(page_size - 1);
        if (std.c.mprotect(aligned_ptr, aligned_len, 0b111) != 0) {
            return error.MProtectError;
        }
    }
}
