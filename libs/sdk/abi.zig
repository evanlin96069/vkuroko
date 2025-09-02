const std = @import("std");
const builtin = @import("builtin");

pub const VCallConv: std.builtin.CallingConvention = switch (builtin.target.os.tag) {
    .windows => .{ .x86_thiscall = .{} },
    .linux => .c,
    else => unreachable,
};

pub const DtorVTable = switch (builtin.os.tag) {
    .windows => extern struct {
        dtor: *anyopaque,
    },
    else => extern struct {
        dtor1: *anyopaque,
        dtor2: *anyopaque,
    },
};

pub const dtor_adjust = switch (builtin.os.tag) {
    .windows => 0,
    else => 1,
};

pub fn ClassMeta(VTable: type) type {
    return switch (builtin.os.tag) {
        .windows => extern struct {
            rtti: *const anyopaque,
            vtable: VTable,
        },
        else => extern struct {
            top_offset: isize,
            rtti: *const anyopaque,
            vtable: VTable,
        },
    };
}
