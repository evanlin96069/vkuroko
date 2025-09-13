const std = @import("std");

const sdk = @import("sdk");

const vkrk = @import("kuroko.zig");

const modules = @import("../../modules.zig");
const engine = modules.engine;
const server = modules.server;

const game_detection = @import("../../utils/game_detection.zig");

const kuroko = @import("kuroko");
const VM = kuroko.KrkVM;
const KrkValue = kuroko.KrkValue;
const KrkString = kuroko.KrkString;
const KrkClass = kuroko.KrkClass;
const KrkInstance = kuroko.KrkInstance;

const str_utils = @import("../../utils/str_utils.zig");

pub const GlobalVars = struct {
    var class: *KrkClass = undefined;

    pub fn create(vars: *sdk.CGlobalVars) KrkValue {
        const inst = KrkInstance.create(class);
        VM.push(inst.asValue());
        inst.fields.attachNamedValue("real_time", KrkValue.floatValue(vars.real_time));
        inst.fields.attachNamedValue("frame_count", KrkValue.intValue(vars.frame_count));
        inst.fields.attachNamedValue("absolute_frame_time", KrkValue.floatValue(vars.absolute_frame_time));
        inst.fields.attachNamedValue("current_time", KrkValue.floatValue(vars.current_time));
        inst.fields.attachNamedValue("frame_time", KrkValue.floatValue(vars.frame_time));
        inst.fields.attachNamedValue("max_clients", KrkValue.intValue(vars.max_clients));
        inst.fields.attachNamedValue("tick_count", KrkValue.intValue(vars.tick_count));
        inst.fields.attachNamedValue("interval_per_tick", KrkValue.floatValue(vars.interval_per_tick));
        inst.fields.attachNamedValue("interpolation_amount", KrkValue.floatValue(vars.interpolation_amount));
        inst.fields.attachNamedValue("sim_ticks_this_frame", KrkValue.intValue(vars.sim_ticks_this_frame));
        inst.fields.attachNamedValue("network_protocol", KrkValue.intValue(vars.network_protocol));
        return VM.pop();
    }
};

pub fn bindAttributes(module: *KrkInstance) void {
    _ = VM.interpret(@embedFile("scripts/game.krk"), vkrk.module_name);

    GlobalVars.class = module.fields.get(KrkString.copyString("GlobalVars").asValue()).?.asClass();

    module.bindFunction("get_game_dir", get_game_dir).setDoc(
        \\@brief Gets the absolute path to the game directory.
    );
    module.bindFunction("get_game_name", get_game_name).setDoc(
        \\@brief Gets the base name of the game directory.
    );
    module.bindFunction("is_portal", is_portal).setDoc(
        \\@brief Does game look like Portal?
    );
    module.bindFunction("get_build_number", get_build_number).setDoc(
        \\@brief Gets the build number
        \\@return Build number, `None` if build number not available
    );
    module.bindFunction("get_map_name", get_map_name).setDoc(
        \\@brief Gets the current map name.
    );
    module.bindFunction("get_global_vars", get_global_vars).setDoc(
        \\@brief Gets `g_pGlobals`.
    );
}

fn get_game_dir(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
    _ = has_kw;
    _ = argv;
    if (argc != 0) {
        return VM.getInstance().exceptions.argumentError.runtimeError("get_game_dir() takes no arguments (%d given)", .{argc});
    }

    return KrkString.copyString(engine.client.getGameDirectory()).asValue();
}

fn get_game_name(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
    _ = has_kw;
    _ = argv;
    if (argc != 0) {
        return VM.getInstance().exceptions.argumentError.runtimeError("get_game_name() takes no arguments (%d given)", .{argc});
    }

    const name: [*:0]const u8 = @ptrCast(std.fs.path.basename(std.mem.span(engine.client.getGameDirectory())).ptr);
    return KrkString.copyString(name).asValue();
}

fn is_portal(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
    _ = has_kw;
    _ = argv;
    if (argc != 0) {
        return VM.getInstance().exceptions.argumentError.runtimeError("is_portal() takes no arguments (%d given)", .{argc});
    }

    return KrkValue.boolValue(game_detection.doesGameLooksLikePortal());
}

fn get_build_number(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
    _ = has_kw;
    _ = argv;
    if (argc != 0) {
        return VM.getInstance().exceptions.argumentError.runtimeError("get_build_number() takes no arguments (%d given)", .{argc});
    }

    if (game_detection.getBuildNumber()) |build_num| {
        return KrkValue.intValue(build_num);
    }
    return KrkValue.noneValue();
}

fn get_map_name(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
    _ = has_kw;
    _ = argv;
    if (argc != 0) {
        return VM.getInstance().exceptions.argumentError.runtimeError("get_map_name() takes no arguments (%d given)", .{argc});
    }

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const map_name: [*:0]const u8 = std.fmt.bufPrintZ(&buf, "{s}", .{engine.client.getMapName()}) catch "";

    return KrkString.copyString(map_name).asValue();
}

fn get_global_vars(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
    _ = has_kw;
    _ = argv;
    if (argc != 0) {
        return VM.getInstance().exceptions.argumentError.runtimeError("get_global_vars() takes no arguments (%d given)", .{argc});
    }

    return GlobalVars.create(server.global_vars);
}
