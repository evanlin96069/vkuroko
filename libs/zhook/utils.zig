const std = @import("std");
const builtin = @import("builtin");

const x86 = @import("x86.zig");
const mem = @import("mem.zig");

const windows = @cImport({
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

pub fn patchCode(addr: [*]u8, data: []const u8, restore_protect: u32) !void {
    if (builtin.os.tag == .windows) {
        var old_protect: windows.DWORD = undefined;

        try std.os.windows.VirtualProtect(addr, data.len, windows.PAGE_EXECUTE_READWRITE, &old_protect);
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

        if (std.c.mprotect(@ptrFromInt(page_start), page_len, prot_all) != 0)
            return error.MProtectWritable;

        @memcpy(addr, data);

        if (std.c.mprotect(@ptrFromInt(page_start), page_len, restore_protect) != 0)
            return error.MProtectRestore;
    }
}

// Windows: Return entire module memory
// Linux: Return the code segment memory
pub fn getModule(comptime module_name: []const u8) ?[]const u8 {
    return switch (builtin.os.tag) {
        .windows => getModuleWindows(module_name),
        .linux => getModuleLinux(module_name, 0b101) catch return null,
        else => @compileError("getModule is not available for this target"),
    };
}

// Return the entire module memory
pub fn getEntireModule(comptime module_name: []const u8) ?[]const u8 {
    return switch (builtin.os.tag) {
        .windows => getModuleWindows(module_name),
        .linux => getModuleLinux(module_name, 0) catch return null,
        else => @compileError("getModule is not available for this target"),
    };
}

fn getModuleWindows(comptime module_name: []const u8) ?[]const u8 {
    const dll_name = module_name ++ ".dll";
    const path_w = std.unicode.utf8ToUtf16LeStringLiteral(dll_name);
    const dll = windows.GetModuleHandleW(path_w) orelse return null;
    var info: windows.MODULEINFO = undefined;
    if (windows.GetModuleInformation(windows.GetCurrentProcess(), dll, &info, @sizeOf(windows.MODULEINFO)) == 0) {
        return null;
    }
    const module: [*]const u8 = @ptrCast(dll);
    return module[0..info.SizeOfImage];
}

fn getModuleLinux(comptime module_name: []const u8, permission: u32) !?[]const u8 {
    const file_name = module_name ++ ".so";

    var f = try std.fs.openFileAbsolute("/proc/self/maps", .{ .mode = .read_only });
    defer f.close();

    var buffer: [4096]u8 = undefined;
    var fr = f.reader(&buffer);

    var base: usize = 0;
    var end: usize = 0;
    var found = false;

    while (try fr.interface.takeDelimiter('\n')) |line| {
        // Example format:
        // de228000-de229000 r--p 00000000 00:29 1026008    /usr/lib/libstdc++.so.6.0.33

        if (!std.mem.endsWith(u8, line, file_name)) {
            if (found) break;
            continue;
        }

        const pos = line.len - file_name.len;
        if (line[pos - 1] != '/' and line[pos - 1] != ' ') continue;

        const dash = std.mem.indexOfScalar(u8, line, '-') orelse continue;
        const space = std.mem.indexOfScalarPos(u8, line, dash + 1, ' ') orelse continue;

        const perms_start = space + 1;
        if (line.len < perms_start + 4) continue;
        const read = line[perms_start];
        const write = line[perms_start + 1];
        const exec = line[perms_start + 2];
        if (permission & 0b001 != 0 and read == '-') continue;
        if (permission & 0b010 != 0 and write == '-') continue;
        if (permission & 0b100 != 0 and exec == '-') continue;

        const start_hex = line[0..dash];
        const end_hex = line[dash + 1 .. space];

        const start_addr = try std.fmt.parseInt(usize, start_hex, 16);
        const end_addr = try std.fmt.parseInt(usize, end_hex, 16);

        if (!found) {
            base = start_addr;
            end = end_addr;
            found = true;
        } else if (start_addr == end) {
            end = end_addr;
        } else {
            break;
        }
    }

    if (!found) return null;

    const size = end - base;
    const ptr: [*]const u8 = @ptrFromInt(base);
    return ptr[0..size];
}

// Match call + add pattern
// If matched, inst + len will be the start of the imm32
pub fn matchPIC(inst: [*]const u8) ?u32 {
    if (inst[0] != @intFromEnum(x86.Opcode.Op1.call)) return null;
    if (inst[5] == @intFromEnum(x86.Opcode.Op1.alumiw)) {
        const modrm = inst[6];
        // mod must be 0b11  (register operand)
        if ((modrm & 0b1100_0000) != 0b1100_0000) return null;
        // reg/opcode must be 0b000 (ADD)
        if ((modrm & 0b0011_1000) != 0b0000_0000) return null;

        // rm should not be 0b100 (ESP)
        // Although it's rare, compiler occasionally uses EBP for PIC
        const rm = modrm & 0b0000_0111;
        if (rm == 0b100) return null;
        return 7;
    } else if (inst[5] == @intFromEnum(x86.Opcode.Op1.addeaxi)) {
        return 6;
    }
    return null;
}

const GOT_pattern = mem.makePattern("E8 ?? ?? ?? ?? 05 ?? ?? ?? ?? 8D 80");

pub fn findGOTAddr(module: []const u8) ?u32 {
    if (mem.scanFirst(module, GOT_pattern)) |offset| {
        const imm32 = mem.loadValue(u32, module.ptr + offset + 6);
        return @intFromPtr(module.ptr + offset + 5) +% imm32;
    }
    return null;
}
