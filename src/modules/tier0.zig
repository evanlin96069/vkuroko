const std = @import("std");

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
        .devMsg = "?DevMsg@@YAXPBDZZ",
    };

    inline for (comptime std.meta.fieldNames(@TypeOf(names))) |field| {
        const func = &@field(@This(), field);
        const name = @field(names, field);
        func.* = lib.lookup(@TypeOf(func.*), name) orelse return false;
    }

    memalloc = (lib.lookup(**MemAlloc, "g_pMemAlloc") orelse return false).*;

    return true;
}

fn deinit() void {}

pub const FmtFn = *const fn (fmt: [*:0]const u8, ...) callconv(.C) void;
pub var msg: FmtFn = undefined;
pub var warning: FmtFn = undefined;
pub var devMsg: FmtFn = undefined;

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
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = ptr_align;
        _ = ret_addr;

        if (memalloc) |ptr| {
            return ptr.alloc(len);
        }
        return null;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf_align;
        _ = ret_addr;

        if (new_len <= buf.len) {
            return true;
        }
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf_align;
        _ = ret_addr;

        if (memalloc) |ptr| {
            ptr.free(buf.ptr);
        }
    }
};
