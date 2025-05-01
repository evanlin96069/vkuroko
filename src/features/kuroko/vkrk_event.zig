const std = @import("std");

const core = @import("../../core.zig");
const texthud = @import("../texthud.zig");
const event = @import("../../event.zig");

const vkrk = @import("kuroko.zig");

const kuroko = @import("kuroko");
const VM = kuroko.KrkVM;
const KrkValue = kuroko.KrkValue;
const KrkString = kuroko.KrkString;
const KrkInstance = kuroko.KrkInstance;

var events = std.StringHashMap(std.ArrayList(KrkValue)).init(core.allocator);

pub fn bindAttributes(module: *KrkInstance) void {
    _ = module.bindFunction("_event_register", _event_register);

    var it = events.iterator();
    while (it.next()) |kv| {
        kv.value_ptr.clearAndFree();
    }

    _ = VM.interpret(@embedFile("scripts/event.krk"), vkrk.module_name);
}

pub fn init() void {
    events.put("on_tick", std.ArrayList(KrkValue).init(core.allocator)) catch return;
    events.put("on_paint", std.ArrayList(KrkValue).init(core.allocator)) catch return;

    VKrkHUD.register();
    event.tick.connect(onTick);
}

pub fn deinit() void {
    var it = events.iterator();
    while (it.next()) |kv| {
        kv.value_ptr.deinit();
    }
    events.deinit();
}

fn _event_register(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
    var event_name: [*:0]const u8 = undefined;
    var callback: KrkValue = undefined;
    if (!kuroko.parseArgs(
        "_event_register",
        argc,
        argv,
        has_kw,
        "sV",
        &.{
            "event_name",
            "callback",
        },
        .{ &event_name, &callback },
    )) {
        return KrkValue.noneValue();
    }

    if (events.getPtr(std.mem.span(event_name))) |callbacks| {
        callbacks.append(callback) catch return VM.getInstance().exceptions.Exception.runtimeError("Out of memory", .{});
    } else {
        return VM.getInstance().exceptions.argumentError.runtimeError("Unknown event name '%s'", .{event_name});
    }

    return KrkValue.noneValue();
}

pub fn triggerEvent(event_name: []const u8, args: []KrkValue) void {
    for (events.get(event_name).?.items) |callback| {
        VM.push(callback);
        for (args) |arg| {
            VM.push(arg);
        }
        _ = VM.callStack(@intCast(args.len));
        VM.resetStack();
    }
}

const VKrkHUD = struct {
    fn shouldDraw() bool {
        return true;
    }

    fn paint() void {
        triggerEvent("on_paint", &[_]KrkValue{});
    }

    fn register() void {
        texthud.addHUDElement(.{
            .shouldDraw = shouldDraw,
            .paint = paint,
        });
    }
};

fn onTick() void {
    triggerEvent("on_tick", &[_]KrkValue{});
}
