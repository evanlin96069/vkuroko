const std = @import("std");

const sdk = @import("sdk");
const Hook = @import("zhook").Hook;

const core = @import("core.zig");
const interfaces = @import("interfaces.zig");

const modules = @import("modules.zig");
const tier0 = modules.tier0;
const engine = modules.engine;
const vgui = modules.vgui;

const event = @import("event.zig");

const VCallConv = sdk.abi.VCallConv;

const IServerPluginCallbacks = sdk.IServerPluginCallbacks;

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = @import("log.zig").log,
};

pub const panic = std.debug.FullPanic(@import("panic.zig").panicFn);

pub var ifacever: u8 = undefined;

var plugin_loaded: bool = false;
var should_defer_load: bool = false;
var skip_unload: bool = false;

var vgui_connect_hook: Hook = undefined;

fn deferLoad() !bool {
    if (vgui.getEngineVGui()) |engine_vgui| {
        if (engine_vgui.isInitialized()) {
            return false;
        }

        core.log.debug("Plugin loaded early", .{});

        const vtidx_connect = 4;
        vgui_connect_hook = try Hook.hookVMT(engine_vgui._vt, vtidx_connect, hookedVGuiConnect);
        should_defer_load = true;

        return true;
    }

    return error.ModuleNotFound;
}

const VGuiConnectFunc = *const @TypeOf(hookedVGuiConnect);

fn hookedVGuiConnect(self: *anyopaque) callconv(VCallConv) void {
    @as(VGuiConnectFunc, @ptrCast(vgui_connect_hook.orig.?))(self);
    if (should_defer_load) {
        should_defer_load = false;
        if (!core.init()) {
            core.log.info("Try unloading plugin...", .{});
            if (!engine.module.loaded or !engine.unloadPlugin()) {
                core.log.warn("Failed to unload plugin", .{});
            }
        }
    }
    vgui_connect_hook.unhook() catch {};
}

fn load(_: *anyopaque, interfaceFactory: interfaces.CreateInterfaceFn, gameServerFactory: interfaces.CreateInterfaceFn) callconv(VCallConv) bool {
    if (plugin_loaded) {
        core.log.err("Plugin already loaded", .{});
        skip_unload = true;
        return false;
    }
    plugin_loaded = true;

    interfaces.engineFactory = interfaceFactory;
    interfaces.serverFactory = gameServerFactory;

    if (!core.init_core_modules()) {
        return false;
    }

    if (deferLoad() catch blk: {
        core.log.warn("Failed to defer plugin load", .{});
        core.log.warn("SOME FEATURES MAY BE BROKEN!!!", .{});
        break :blk false;
    }) {
        return true;
    }

    if (!core.init()) {
        return false;
    }

    return true;
}

fn unload(_: *anyopaque) callconv(VCallConv) void {
    if (skip_unload) {
        skip_unload = false;
        return;
    }

    core.deinit();

    plugin_loaded = false;
}

fn pause(_: *anyopaque) callconv(VCallConv) void {}

fn unpause(_: *anyopaque) callconv(VCallConv) void {}

fn getPluginDescription(_: *anyopaque) callconv(VCallConv) [*:0]const u8 {
    return "vkuroko - evanlin96069";
}

fn levelInit(_: *anyopaque, map_name: [*:0]const u8) callconv(VCallConv) void {
    _ = map_name;
}

fn serverActivate(
    _: *anyopaque,
    edict_list: [*]*anyopaque,
    edict_count: c_int,
    client_max: c_int,
) callconv(VCallConv) void {
    _ = edict_list;
    _ = edict_count;
    _ = client_max;
}

fn gameFrame(_: *anyopaque, simulating: bool) callconv(VCallConv) void {
    if (simulating) {
        event.tick.emit(.{});
    }
}

fn levelShutdown(_: *anyopaque) callconv(VCallConv) void {}

fn clientActive(_: *anyopaque, entity: *anyopaque) callconv(VCallConv) void {
    _ = entity;
}

fn clientDisconnect(_: *anyopaque, entity: *anyopaque) callconv(VCallConv) void {
    _ = entity;
}

fn clientPutInServer(_: *anyopaque, entity: *anyopaque, player_name: [*:0]const u8) callconv(VCallConv) void {
    _ = entity;
    _ = player_name;
}

fn setCommandClient(_: *anyopaque, index: c_int) callconv(VCallConv) void {
    _ = index;
}

fn clientSettingsChanged(_: *anyopaque, entity: *anyopaque) callconv(VCallConv) void {
    _ = entity;
}

fn clientConnect(
    _: *anyopaque,
    allow: *bool,
    entity: *anyopaque,
    name: [*:0]const u8,
    addr: [*:0]const u8,
    reject: [*:0]u8,
    max_reject_len: c_int,
) callconv(VCallConv) c_int {
    _ = allow;
    _ = entity;
    _ = name;
    _ = addr;
    _ = reject;
    _ = max_reject_len;
    return 0;
}

fn clientCommand(_: *anyopaque, entity: *anyopaque, args: *const anyopaque) callconv(VCallConv) c_int {
    _ = entity;
    _ = args;
    return 0;
}

fn networkIdValidated(_: *anyopaque, user_name: [*:0]const u8, network_id: [*:0]const u8) callconv(VCallConv) c_int {
    _ = user_name;
    _ = network_id;
    return 0;
}

fn onQueryCvarValueFinished(
    _: *anyopaque,
    cookie: c_int,
    player_entity: *anyopaque,
    status: c_int,
    cvar_name: [*:0]const u8,
    cvar_value: [*:0]const u8,
) callconv(VCallConv) void {
    _ = cvar_value;
    _ = cvar_name;
    _ = status;
    _ = player_entity;
    _ = cookie;
}

fn onEdictAllocated(_: *anyopaque, edict: *anyopaque) callconv(VCallConv) void {
    _ = edict;
}

fn onEdictFreed(_: *anyopaque, edict: *const anyopaque) callconv(VCallConv) void {
    _ = edict;
}

const vt_IServerPluginCallbacks = [_]*const anyopaque{
    &load,
    &unload,
    &pause,
    &unpause,
    &getPluginDescription,
    &levelInit,
    &serverActivate,
    &gameFrame,
    &levelShutdown,
    &clientActive,
    &clientDisconnect,
    &clientPutInServer,
    &setCommandClient,
    &clientSettingsChanged,
    &clientConnect,
    &clientCommand,
    &networkIdValidated,
    &onQueryCvarValueFinished,
    &onEdictAllocated,
    &onEdictFreed,
};

pub const plugin: IServerPluginCallbacks = .{
    ._vt = @ptrCast(&vt_IServerPluginCallbacks),
};

export fn CreateInterface(name: [*:0]u8, ret: ?*c_int) ?*const IServerPluginCallbacks {
    if (std.mem.startsWith(u8, std.mem.span(name), "ISERVERPLUGINCALLBACKS00")) {
        if (name[24] >= '2' and name[24] <= '3' and name[25] == 0) {
            ifacever = name[24] - '0';

            if (ret) |r| r.* = 0;
            return &plugin;
        }
    }

    if (ret) |r| r.* = 1;
    return null;
}
