const std = @import("std");

const sdk = @import("sdk");

const Module = @import("Module.zig");
const DynLib = @import("../utils/DynLib.zig");

pub var module: Module = .{
    .name = "tier0",
    .init = init,
    .deinit = deinit,
};

fn init() bool {
    var lib = DynLib.open("tier0.dll") catch return false;
    defer lib.close();

    const names = .{
        .msg = "Msg",
        .warning = "Warning",
        .colorMsg = "?ConColorMsg@@YAXABVColor@@PBDZZ",
        .devMsg = "?DevMsg@@YAXPBDZZ",
        .devWarning = "?DevWarning@@YAXPBDZZ",
    };

    inline for (comptime std.meta.fieldNames(@TypeOf(names))) |field| {
        const func = &@field(@This(), field);
        const name = @field(names, field);
        func.* = lib.lookup(@TypeOf(func.*), name) orelse return false;
    }

    memalloc = (lib.lookup(**MemAlloc, "g_pMemAlloc") orelse return false).*;

    ready = true;

    return true;
}

fn deinit() void {}

pub const FmtFn = *const fn (fmt: [*:0]const u8, ...) callconv(.C) void;
pub var msg: FmtFn = undefined;
pub var warning: FmtFn = undefined;
pub var colorMsg: *const fn (color: *const sdk.Color, fmt: [*:0]const u8, ...) callconv(.C) void = undefined;
pub var devMsg: FmtFn = undefined;
pub var devWarning: FmtFn = undefined;
pub var ready: bool = false;

var memalloc: ?*MemAlloc = null;

const MemAlloc = extern struct {
    _vt: *align(@alignOf(*anyopaque)) const anyopaque,

    const VTable = extern struct {
        _alloc: *const anyopaque,
        alloc: *const fn (this: *anyopaque, size: usize) callconv(.Thiscall) ?[*]u8,
        _realloc: *const anyopaque,
        realloc: *const fn (this: *anyopaque, mem: *anyopaque, size: usize) callconv(.Thiscall) ?[*]u8,
        _free: *const anyopaque,
        free: *const fn (this: *anyopaque, mem: *anyopaque) callconv(.Thiscall) void,
    };

    fn vt(self: *MemAlloc) *const VTable {
        return @ptrCast(self._vt);
    }

    pub fn alloc(self: *MemAlloc, size: usize) ?[*]u8 {
        return self.vt().alloc(self, size);
    }

    pub fn realloc(self: *MemAlloc, mem: *anyopaque, size: usize) ?[*]u8 {
        return self.vt().realloc(self, mem, size);
    }

    pub fn free(self: *MemAlloc, mem: *anyopaque) void {
        self.vt().free(self, mem);
    }
};

var allocator_state: Tier0Allocator = .{};
pub const allocator: std.mem.Allocator = allocator_state.allocator();

const Tier0Allocator = struct {
    pub fn allocator(self: *Tier0Allocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = alignment;
        _ = ret_addr;

        if (memalloc) |ptr| {
            return ptr.alloc(len);
        }
        return null;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = alignment;
        _ = ret_addr;

        if (new_len <= memory.len) {
            return true;
        }
        return false;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = alignment;
        _ = ret_addr;

        if (memalloc) |ptr| {
            return ptr.realloc(memory.ptr, new_len);
        }
        return null;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = alignment;
        _ = ret_addr;

        if (memalloc) |ptr| {
            ptr.free(memory.ptr);
        }
    }
};
