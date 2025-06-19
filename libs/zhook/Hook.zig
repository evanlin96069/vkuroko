const std = @import("std");
const builtin = @import("builtin");

const x86 = @import("x86.zig");
const utils = @import("utils.zig");

const loadValue = @import("mem.zig").loadValue;

const Hook = @This();

const HookType = enum {
    vmt,
    detour,
};

const Rel32Patch = struct {
    offset: u32, // offset into the trampoline
    dest: u32, // absolute address rel32 points to
    orig: u32, // original data in the instruction
};

// Windows doesn't use PIC
const PICAddiPatch = switch (builtin.os.tag) {
    .linux => struct {
        offset: u32, // offset into the original function
        orig: u32, // original data in the instruction
    },
    .windows => void,
    else => @compileError("Unsupported OS"),
};

const HookData = union(HookType) {
    const HookVMTResult = struct {
        vt: [*]*const anyopaque,
        index: u32,
    };

    const HookDetourResult = struct {
        func: [*]u8,
        trampoline: []u8,
        rel32_patch: ?Rel32Patch = null,
        pic_addi_patch: ?PICAddiPatch = null,
    };

    vmt: HookVMTResult,
    detour: HookDetourResult,
};

orig: ?*const anyopaque,
data: HookData,

pub fn hookVMT(vt: [*]*const anyopaque, index: usize, target: *const anyopaque) !Hook {
    const orig: *const anyopaque = vt[index];
    const entry_ptr: [*]u8 = @ptrCast(vt + index);

    const bytes = std.mem.toBytes(target);
    try utils.patchCode(entry_ptr, &bytes);

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

fn isAddImm32(mem: [*]const u8) bool {
    if (mem[0] != x86.Opcode.Op1.alumiw) return false;

    const modrm = mem[1];
    // mod must be 0b11  (register operand)
    if ((modrm & 0b1100_0000) != 0b1100_0000) return false;
    // reg/opcode must be 000 (ADD)
    if ((modrm & 0b0011_1000) != 0b0000_0000) return false;
    return true;
}

// Trampoline memory must have rwx permissions
pub fn hookDetour(func: *anyopaque, target: *const anyopaque, trampoline: []u8) !Hook {
    var mem: [*]u8 = @ptrCast(func);

    // Hook the underlying thing if the function jmp immediately.
    while (mem[0] == x86.Opcode.Op1.jmpiw) {
        const offset = loadValue(u32, mem + 1);
        mem = @ptrFromInt(@intFromPtr(mem + 5) +% offset);
    }

    var rel32_patch: ?Rel32Patch = null;
    var pic_addi_patch: ?PICAddiPatch = null;

    var len: usize = 0;
    while (true) {
        if (mem[len] == x86.Opcode.Op1.call) {
            const offset = loadValue(u32, mem + len + 1);
            rel32_patch = .{
                .offset = len + 1,
                .dest = @intFromPtr(mem + len + 5) +% offset,
                .orig = offset,
            };

            if (builtin.os.tag == .linux) {
                // Look for PIC pattern:
                // call __i686.get_pc_thunk.reg
                // add reg, imm32
                if (isAddImm32(mem + len + 5)) {
                    const imm32 = loadValue(u32, mem + len + 7);
                    pic_addi_patch = .{
                        .offset = len + 7,
                        .orig = imm32,
                    };
                }
            }
        }

        len += try x86.x86_len(mem + len);

        if (len >= 5) {
            break;
        }

        if (mem[len] == x86.Opcode.Op1.jmpiw) {
            const offset = loadValue(u32, mem + len + 1);
            rel32_patch = .{
                .offset = len + 1,
                .dest = @intFromPtr(mem + len + 5) +% offset,
                .orig = offset,
            };
        }
    }

    const trampoline_size = len + 5;
    if (trampoline.len < trampoline_size) {
        return error.OutOfTrampoline;
    }

    @memcpy(trampoline[0..len], mem);
    trampoline[len] = x86.Opcode.Op1.jmpiw;
    const jmp1_offset: *align(1) u32 = @ptrCast(trampoline.ptr + len + 1);
    jmp1_offset.* = @intFromPtr(mem + len) -% @intFromPtr(trampoline.ptr + len + 5);

    if (rel32_patch) |r| {
        const rel_patch: *align(1) u32 = @ptrCast(trampoline.ptr + r.offset);
        rel_patch.* = r.dest -% (@intFromPtr(trampoline.ptr + r.offset + 4));
    }

    var detour: [5]u8 = undefined;
    detour[0] = x86.Opcode.Op1.jmpiw;
    const jmp2_offset: *align(1) u32 = @ptrCast(&detour[1]);
    jmp2_offset.* = @intFromPtr(target) -% @intFromPtr(mem + 5);

    try utils.patchCode(mem, detour[0..]);

    if (builtin.os.tag == .linux) {
        if (pic_addi_patch) |p| {
            const delta: u32 = @intFromPtr(trampoline.ptr) -% @intFromPtr(mem);
            const new_value: u32 = p.orig -% delta;

            const bytes = std.mem.toBytes(new_value);
            try utils.patchCode(mem + p.offset, &bytes);
        }
    }

    return Hook{
        .orig = trampoline.ptr,
        .data = .{ .detour = .{
            .func = mem,
            .trampoline = trampoline[0..trampoline_size],
            .rel32_patch = rel32_patch,
            .pic_addi_patch = pic_addi_patch,
        } },
    };
}

pub fn unhook(self: *Hook) !void {
    const orig = self.orig orelse return;
    switch (self.data) {
        .vmt => |v| {
            const entry_ptr: [*]u8 = @ptrCast(v.vt + v.index);
            const bytes = std.mem.toBytes(orig);
            try utils.patchCode(entry_ptr, &bytes);
        },
        .detour => |v| {
            if (v.rel32_patch) |r| {
                const orig_patch: *align(1) u32 = @ptrCast(v.trampoline.ptr + r.offset);
                orig_patch.* = r.orig;
            }
            try utils.patchCode(v.func, v.trampoline[0 .. v.trampoline.len - 5]);
            if (builtin.os.tag == .linux) {
                if (v.pic_addi_patch) |p| {
                    const bytes = std.mem.toBytes(p.orig);
                    try utils.patchCode(v.func + p.offset, &bytes);
                }
            }
        },
    }
    self.orig = null;
}
