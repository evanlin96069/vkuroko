const std = @import("std");

const zhook = @import("zhook");

const modules = @import("../modules.zig");
const tier1 = modules.tier1;
const engine = modules.engine;

pub fn doesGameLooksLikePortal() bool {
    const S = struct {
        var cached = false;
        var result: ?*tier1.ConCommand = null;
    };

    if (!S.cached) {
        S.result = tier1.icvar.findCommand("upgrade_portalgun");
        S.cached = true;
    }

    return S.result != null;
}

pub fn getBuildNumber() ?i32 {
    const S = struct {
        var initialized: bool = false;
        var build_num: ?i32 = null;
    };

    if (!engine.module.loaded) return null;

    if (S.initialized) {
        return S.build_num;
    }

    const build_num = findBuildNumber();
    S.initialized = true;
    S.build_num = build_num;
    return build_num;
}

// Exe build:
const build_str = zhook.mem.makePattern("45 78 65 20 62 75 69 6C 64 3A");

fn findBuildNumber() ?i32 {
    var build_num: ?i32 = null;
    const engine_dll = engine.engine_dll;
    if (zhook.mem.scanFirst(engine_dll, build_str)) |offset| {
        build_num = calculateBuildNumber(engine_dll[offset + 20 .. offset + 31]);
    } else if (tier1.icvar.findCommand("version")) |version| {
        // Find build number via `version` command
        const module_start = @intFromPtr(engine_dll.ptr);
        const module_end = module_start + engine_dll.len;

        const build_num_ptr_ptr: *const u8 = @ptrFromInt(@intFromPtr(version.command_callback) + 3);
        if (@intFromPtr(build_num_ptr_ptr) >= module_start and
            @intFromPtr(build_num_ptr_ptr) <= module_end)
        {
            const build_num_ptr: *const u8 = @as(*align(1) const *const u8, @ptrCast(build_num_ptr_ptr)).*;
            if (@intFromPtr(build_num_ptr) >= module_start and
                @intFromPtr(build_num_ptr) <= module_end)
            {
                build_num = @as(*align(1) const i32, @ptrCast(build_num_ptr)).*;
            }
        }
    }

    return build_num;
}

fn calculateBuildNumber(date_str: []const u8) i32 {
    const months = [_][]const u8{
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };

    const month_days = [_]u32{
        31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
    };

    var m: u32 = 0;
    var d: u32 = 0;
    var y: u32 = 0;

    while (m < 11) : (m += 1) {
        const month = months[m];
        if (std.mem.startsWith(u8, date_str, month)) {
            break;
        }
        d += month_days[m];
    }

    if (date_str[4] == ' ') {
        d += @as(u32, date_str[5] - '0') - 1;
    } else {
        d += (@as(u32, date_str[4] - '0') * 10 + @as(u32, date_str[5] - '0')) - 1;
    }

    y = std.fmt.parseInt(u32, date_str[7..], 10) catch return -1;
    y -= 1900;

    var build_num: i32 = @intCast(((y - 1) * 365 + (y - 1) / 4) + d);

    if (y % 4 == 0 and m > 1) {
        build_num += 1;
    }

    build_num -= 35739;
    return build_num;
}
