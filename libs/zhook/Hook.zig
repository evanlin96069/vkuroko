const std = @import("std");
const builtin = @import("builtin");

const x86 = @import("x86.zig");
const utils = @import("utils.zig");
const windows = utils.windows;

const loadValue = @import("mem.zig").loadValue;

const Hook = @This();

const HookType = enum {
    vmt,
    detour,
};

const Rel32 = struct {
    offset: u32, // offset into the trampoline
    dest: u32, // absolute address rel32 points to
    orig: u32, // original data in the instruction
};

const HookData = union(HookType) {
    const HookVMTResult = struct {
        vt: [*]*const anyopaque,
        index: u32,
    };

    const HookDetourResult = struct {
        alloc: std.mem.Allocator,
        func: [*]u8,
        trampoline: []u8,
        rel32: ?Rel32 = null,
    };

    vmt: HookVMTResult,
    detour: HookDetourResult,
};

orig: ?*const anyopaque,
data: HookData,

pub fn hookVMT(vt: [*]*const anyopaque, index: usize, target: *const anyopaque) !Hook {
    try utils.mprotect(@ptrCast(vt + index), @sizeOf(*anyopaque));

    const orig: *const anyopaque = vt[index];
    vt[index] = target;

    return Hook{
        .orig = orig,
        .data = .{
            .vmt = .{
                .vt = vt,
                .index = index,
            },
        },
    };
}

pub fn hookDetour(func: *anyopaque, target: *const anyopaque, alloc: std.mem.Allocator) !Hook {
    var mem: [*]u8 = @ptrCast(func);

    // Hook the underlying thing if the function jmp immediately.
    while (mem[0] == x86.Opcode.Op1.jmpiw) {
        const offset = loadValue(u32, mem + 1);
        mem = @ptrFromInt(@intFromPtr(mem + 5) +% offset);
    }

    var rel32: ?Rel32 = null;

    var len: usize = 0;
    while (true) {
        // CALL and JMP instructions use relative offsets rather than absolute addresses.
        // We can't copy them into the trampoline directly. Just returns an error for now.
        if (mem[len] == x86.Opcode.Op1.call) {
            const offset = loadValue(u32, mem + len + 1);
            rel32 = .{
                .offset = len + 1,
                .dest = @intFromPtr(mem + len + 5) +% offset,
                .orig = offset,
            };
        }

        len += try x86.x86_len(mem + len);

        if (len >= 5) {
            break;
        }

        if (mem[len] == x86.Opcode.Op1.jmpiw) {
            const offset = loadValue(u32, mem + len + 1);
            rel32 = .{
                .offset = len + 1,
                .dest = @intFromPtr(mem + len + 5) +% offset,
                .orig = offset,
            };
        }
    }

    try utils.mprotect(mem, 5);

    var trampoline = try alloc.alloc(u8, len + 5);
    try utils.mprotect(trampoline.ptr, trampoline.len);

    @memcpy(trampoline[0..len], mem);
    trampoline[len] = x86.Opcode.Op1.jmpiw;
    const jmp1_offset: *align(1) u32 = @ptrCast(trampoline.ptr + len + 1);
    jmp1_offset.* = @intFromPtr(mem) -% @intFromPtr(trampoline.ptr + 5);

    if (rel32) |r| {
        const rel_patch: *align(1) u32 = @ptrCast(trampoline.ptr + r.offset);
        rel_patch.* = r.dest -% (@intFromPtr(trampoline.ptr + r.offset + 4));
    }

    mem[0] = x86.Opcode.Op1.jmpiw;
    const jmp2_offset: *align(1) u32 = @ptrCast(mem + 1);
    jmp2_offset.* = @intFromPtr(target) -% @intFromPtr(mem + 5);

    if (builtin.os.tag == .windows) {
        _ = windows.FlushInstructionCache(windows.GetCurrentProcess(), mem, 5);
    }

    return Hook{
        .orig = trampoline.ptr,
        .data = .{ .detour = .{
            .alloc = alloc,
            .func = mem,
            .trampoline = trampoline,
            .rel32 = rel32,
        } },
    };
}

pub fn unhook(self: *Hook) void {
    const orig = self.orig orelse return;
    switch (self.data) {
        .vmt => |v| {
            v.vt[v.index] = orig;
        },
        .detour => |v| {
            @memcpy(v.func, v.trampoline[0 .. v.trampoline.len - 5]);
            if (v.rel32) |r| {
                const orig_patch: *align(1) u32 = @ptrCast(v.func + r.offset);
                orig_patch.* = r.orig;
            }

            if (builtin.os.tag == .windows) {
                _ = windows.FlushInstructionCache(windows.GetCurrentProcess(), v.func, 5);
            }

            v.alloc.free(v.trampoline);
        },
    }
    self.orig = null;
}
