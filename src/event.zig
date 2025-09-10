const std = @import("std");

const core = @import("core.zig");
const CUserCmd = @import("sdk").CUserCmd;

fn Event(comptime CallbackFn: type) type {
    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        works: bool = false,
        callbacks: std.ArrayList(CallbackFn),

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{
                .alloc = alloc,
                .callbacks = .empty,
            };
        }

        pub fn deinit(self: *Self) void {
            self.callbacks.deinit(self.alloc);
        }

        pub fn emit(self: *const Self, args: anytype) void {
            for (self.callbacks.items) |callback| {
                @call(.auto, callback, args);
            }
        }

        pub fn connect(self: *Self, callback: CallbackFn) void {
            self.callbacks.append(self.alloc, callback) catch unreachable;
        }
    };
}

pub var paint = Event(*const fn () void).init(core.allocator);
pub var tick = Event(*const fn () void).init(core.allocator);
pub var frame = Event(*const fn () void).init(core.allocator);
pub var create_move = Event(*const fn (is_server: bool, cmd: *CUserCmd) void).init(core.allocator);

pub fn init() void {
    tick.works = true;
    frame.works = true;
}

pub fn deinit() void {
    paint.deinit();
    tick.deinit();
    frame.deinit();
    create_move.deinit();
}
