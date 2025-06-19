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

pub fn patchCode(addr: [*]u8, data: []const u8) !void {
    if (builtin.os.tag == .windows) {
        var old_protect: windows.DWORD = undefined;

        try windows.VirtualProtect(addr, data.len, windows.PAGE_EXECUTE_READWRITE, &old_protect);
        @memcpy(addr, data);

        _ = windows.FlushInstructionCache(windows.GetCurrentProcess(), addr, data.len);
        try std.os.windows.VirtualProtect(addr, data.len, old_protect, &old_protect);
    } else {
        const page_size = std.heap.page_size_min;
        const addr_int = @intFromPtr(addr);
        const page_start = addr_int & ~(page_size - 1);
        const page_end = addr_int + data.len;
        const page_len = (page_end - page_start + page_size - 1) & ~(page_size - 1);

        const prot_all = 0b111; // rwx
        const prot_rx = 0b101; // r-x

        if (std.c.mprotect(@ptrFromInt(page_start), page_len, prot_all) != 0)
            return error.MProtectWritable;

        @memcpy(addr, data);

        if (std.c.mprotect(@ptrFromInt(page_start), page_len, prot_rx) != 0)
            return error.MProtectRestore;
    }
}
