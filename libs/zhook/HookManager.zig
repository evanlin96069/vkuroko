const std = @import("std");

const Hook = @import("Hook.zig");
const mem = @import("mem.zig");
const utils = @import("utils.zig");

const HookManager = @This();

allocator: std.mem.Allocator,
hooks: std.ArrayList(Hook),
exec_page: []u8,

// Page must has rwx permissions
pub fn init(alloc: std.mem.Allocator, exec_page: *align(std.heap.page_size_min) [std.heap.page_size_min]u8) HookManager {
    return HookManager{
        .allocator = alloc,
        .hooks = .empty,
        .exec_page = exec_page[0..],
    };
}

pub fn deinit(self: *HookManager) usize {
    var count: usize = 0;
    for (self.hooks.items) |*hook| {
        hook.unhook() catch continue;
        count += 1;
    }

    self.hooks.deinit(self.allocator);
    return count;
}

pub fn findAndHook(self: *HookManager, T: type, module: []const u8, patterns: []const []const ?u8, target: *const anyopaque) !T {
    const match = mem.scanUniquePatterns(module, patterns) orelse {
        return error.PatternNotFound;
    };

    return self.hookDetour(T, match.ptr, target);
}

pub fn hookVMT(self: *HookManager, T: type, vt: [*]*const anyopaque, index: usize, target: *const anyopaque) !T {
    var hook = try Hook.hookVMT(vt, index, target);
    errdefer hook.unhook() catch {};

    try self.hooks.append(self.allocator, hook);

    return @ptrCast(hook.orig.?);
}

pub fn hookDetour(self: *HookManager, T: type, func: *const anyopaque, target: *const anyopaque) !T {
    var hook = try Hook.hookDetour(@constCast(func), target, self.exec_page);
    errdefer hook.unhook() catch {};

    try self.hooks.append(self.allocator, hook);

    self.exec_page = self.exec_page[hook.data.detour.trampoline.len..];

    return @ptrCast(hook.orig.?);
}
