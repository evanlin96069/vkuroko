const std = @import("std");

const interfaces = @import("../interfaces.zig");

const Module = @import("Module.zig");

const core = @import("../core.zig");
const event = @import("../event.zig");
const tier1 = @import("tier1.zig");

const main = @import("../main.zig");

const sdk = @import("sdk");
const abi = sdk.abi;
const Edict = sdk.Edict;
const Vector = sdk.Vector;
const QAngle = sdk.QAngle;
const Ray = sdk.Ray;
const Trace = sdk.Trace;
const ITraceFilter = sdk.ITraceFilter;
const VCallConv = abi.VCallConv;

const zhook = @import("zhook");

pub var module: Module = .{
    .name = "engine",
    .init = init,
    .deinit = deinit,
};

var vkrk_unload = tier1.ConCommand.init(.{
    .name = "vkrk_unload",
    .flags = .{
        .dont_record = true,
    },
    .help_string = "Unloads vkuroko.",
    .command_callback = vkrk_unload_Fn,
});

fn getPluginIndex() ?u32 {
    const plugin_addr = @intFromPtr(&main.plugin);
    var i: u32 = 0;
    while (i < plugin_helper.plugins.size) : (i += 1) {
        if (@intFromPtr(plugin_helper.plugins.elements[i].plugin) == plugin_addr) {
            return i;
        }
    }
    return null;
}

pub fn unloadPlugin() bool {
    if (getPluginIndex()) |index| {
        var buf: [32]u8 = undefined;
        if (std.fmt.bufPrintZ(&buf, "plugin_unload {d}", .{index})) |cmd| {
            core.log.info("Unloading plugin...", .{});
            client.clientCmd(cmd);
            return true;
        } else |_| {
            core.log.warn("Failed to format command", .{});
            return false;
        }
    }

    core.log.warn("Could not determine plugin index", .{});
    return false;
}

fn vkrk_unload_Fn(args: *const tier1.CCommand) callconv(.c) void {
    _ = args;

    if (!unloadPlugin()) {
        core.log.warn("Failed to unload plugin", .{});
    }
}

const IVEngineServer = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const getEntityCount = 17;
        const pEntityOfEntIndex = 19;
    };

    pub fn getEntityCount(self: *IVEngineServer) c_int {
        const _getEntityCount: *const fn (this: *anyopaque) callconv(VCallConv) c_int = @ptrCast(self._vt[VTIndex.getEntityCount]);
        return _getEntityCount(self);
    }

    pub fn pEntityOfEntIndex(self: *IVEngineServer, index: c_int) ?*Edict {
        const _pEntityOfEntIndex: *const fn (this: *anyopaque, index: c_int) callconv(VCallConv) ?*Edict = @ptrCast(self._vt[VTIndex.pEntityOfEntIndex]);
        return _pEntityOfEntIndex(self, index);
    }
};

const IVEngineClient = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const clientCmd = 7;
        const getViewAngles = 19;
        const setViewAngles = 20;
        const isInGame = 26;
        const getGameDirectory = 35;
        const getLevelName = 51;
    };

    pub fn clientCmd(self: *IVEngineClient, command: [*:0]const u8) void {
        const _clientCmd: *const fn (this: *anyopaque, command: [*:0]const u8) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.clientCmd]);
        _clientCmd(self, command);
    }

    pub fn isInGame(self: *IVEngineClient) bool {
        const _isInGame: *const fn (this: *anyopaque) callconv(VCallConv) bool = @ptrCast(self._vt[VTIndex.isInGame]);
        return _isInGame(self);
    }

    pub fn getViewAngles(self: *IVEngineClient) QAngle {
        var va: QAngle = undefined;
        const _getViewAngles: *const fn (this: *anyopaque, va: *QAngle) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.getViewAngles]);
        _getViewAngles(self, &va);
        return va;
    }

    pub fn setViewAngles(self: *IVEngineClient, va: QAngle) void {
        const _setViewAngles: *const fn (this: *anyopaque, va: *QAngle) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.setViewAngles]);
        _setViewAngles(self, &va);
    }

    pub fn getGameDirectory(self: *IVEngineClient) [*:0]const u8 {
        const _getGameDirectory: *const fn (this: *anyopaque) callconv(VCallConv) [*:0]const u8 = @ptrCast(self._vt[VTIndex.getGameDirectory]);
        return _getGameDirectory(self);
    }

    pub fn getLevelName(self: *IVEngineClient) [*:0]const u8 {
        const _getLevelName: *const fn (this: *anyopaque) callconv(VCallConv) [*:0]const u8 = @ptrCast(self._vt[VTIndex.getLevelName]);
        return _getLevelName(self);
    }

    // basename without file extension
    pub fn getMapName(self: *IVEngineClient) []const u8 {
        const path = self.getLevelName();
        const filename = std.fs.path.basename(std.mem.span(path));
        const index = std.mem.lastIndexOfScalar(u8, filename, '.') orelse return filename;
        if (index == 0) return filename;
        return filename[0..index];
    }
};

const IEngineTool = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const hostFrameTime = 40 + abi.dtor_adjust;
    };

    pub fn hostFrameTime(self: *IEngineTool) c_int {
        const _hostFrameTime: *const fn (this: *anyopaque) callconv(VCallConv) c_int = @ptrCast(self._vt[VTIndex.hostFrameTime]);
        return _hostFrameTime(self);
    }
};

const IEngineTrace = extern struct {
    _vt: [*]*const anyopaque,

    const VTIndex = struct {
        const traceRay = 4;
        const pointOutsideWorld = 16;
    };

    pub fn traceRay(self: *IEngineTrace, ray: *const Ray, mask: c_uint, filter: ?*ITraceFilter, trace: *Trace) void {
        const _traceRay: *const fn (this: *anyopaque, ray: *const Ray, mask: c_uint, filter: ?*ITraceFilter, trace: *Trace) callconv(VCallConv) void = @ptrCast(self._vt[VTIndex.traceRay]);
        _traceRay(self, ray, mask, filter, trace);
    }

    pub fn pointOutsideWorld(self: *IEngineTrace, pt_test: Vector) bool {
        const _pointOutsideWorld: *const fn (this: *anyopaque, pt_test: *const Vector) callconv(VCallConv) bool = @ptrCast(self._vt[VTIndex.pointOutsideWorld]);
        return _pointOutsideWorld(self, &pt_test);
    }
};

pub var engine_dll: []const u8 = "";

pub var server: *IVEngineServer = undefined;
pub var client: *IVEngineClient = undefined;

pub var tool: *IEngineTool = undefined;

pub var trace_server: *IEngineTrace = undefined;
pub var trace_client: *IEngineTrace = undefined;

pub var plugin_helper: *sdk.CServerPlugin = undefined;

fn init() bool {
    engine_dll = zhook.utils.getModule("engine") orelse blk: {
        core.log.warn("Failed to get engine module", .{});
        break :blk "";
    };

    server = @ptrCast(interfaces.engineFactory("VEngineServer021", null) orelse {
        core.log.err("Failed to get IVEngineServer interface", .{});
        return false;
    });

    const client_info = interfaces.create(interfaces.engineFactory, "VEngineClient", .{ 13, 14 }) orelse {
        core.log.err("Failed to get IVEngineClient interface", .{});
        return false;
    };
    client = @ptrCast(client_info.interface);

    server = @ptrCast(interfaces.engineFactory("VEngineServer021", null) orelse {
        core.log.err("Failed to get IVEngineServer interface", .{});
        return false;
    });

    tool = @ptrCast(interfaces.engineFactory("VENGINETOOL003", null) orelse {
        core.log.err("Failed to get IEngineTool interface", .{});
        return false;
    });

    trace_server = @ptrCast(interfaces.engineFactory("EngineTraceServer003", null) orelse {
        core.log.err("Failed to get EngineTraceServer interface", .{});
        return false;
    });

    trace_client = @ptrCast(interfaces.engineFactory("EngineTraceClient003", null) orelse {
        core.log.err("Failed to get EngineTraceClient interface", .{});
        return false;
    });

    plugin_helper = @ptrCast(interfaces.engineFactory("ISERVERPLUGINHELPERS001", null) orelse {
        core.log.err("Failed to get IServerPluginHelpers interface", .{});
        return false;
    });

    vkrk_unload.register();

    return true;
}

fn deinit() void {}
