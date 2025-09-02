const std = @import("std");

const modules = @import("../../modules.zig");
const engine = modules.engine;

const game_detection = @import("../../utils/game_detection.zig");

const kuroko = @import("kuroko");
const VM = kuroko.KrkVM;
const KrkValue = kuroko.KrkValue;
const KrkString = kuroko.KrkString;
const KrkInstance = kuroko.KrkInstance;

const str_utils = @import("../../utils/str_utils.zig");

pub fn bindAttributes(module: *KrkInstance) void {
    module.bindFunction("get_game_dir", get_game_dir).setDoc(
        \\@brief Gets the absolute path to the game directory.
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
}

fn get_game_dir(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.c) KrkValue {
    _ = has_kw;
    _ = argv;
    if (argc != 0) {
        return VM.getInstance().exceptions.argumentError.runtimeError("get_game_dir() takes no arguments (%d given)", .{argc});
    }

    return KrkString.copyString(engine.client.getGameDirectory()).asValue();
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
