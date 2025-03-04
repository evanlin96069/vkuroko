const std = @import("std");
const builtin = @import("builtin");

const event = @import("event.zig");

const tier0 = @import("modules/tier0.zig");
const Module = @import("modules/Module.zig");
const Feature = @import("features/Feature.zig");

const HookManager = @import("zhook").HookManager;

pub const log = std.log.scoped(.vkuroko);

pub var hook_manager: HookManager = undefined;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

const core_modules: []const *Module = mods: {
    var mods: []const *Module = &.{};
    for (&.{
        @import("modules/tier0.zig"),
        @import("modules/tier1.zig"),
    }) |file| {
        mods = mods ++ .{&file.module};
    }
    break :mods mods;
};

const modules: []const *Module = mods: {
    var mods: []const *Module = &.{};
    for (&.{
        @import("modules/engine.zig"),
        @import("modules/server.zig"),
        @import("modules/client.zig"),
        @import("modules/vgui.zig"),
    }) |file| {
        mods = mods ++ .{&file.module};
    }
    break :mods mods;
};

const features: []const *Feature = mods: {
    var mods: []const *Feature = &.{};
    for (&.{
        @import("features/datamap.zig"),
        @import("features/texthud.zig"),
        @import("features/playerio.zig"),
        @import("features/kuroko/kuroko.zig"),
    }) |file| {
        mods = mods ++ .{&file.feature};
    }

    if (builtin.mode == .Debug) {
        mods = mods ++ .{&@import("features/dev.zig").feature};
    }

    break :mods mods;
};

pub fn init_core_modules() bool {
    for (core_modules) |module| {
        module.loaded = module.init();
        if (!module.loaded) {
            log.err("Failed to load module {s}.", .{module.name});
            return false;
        }
        log.debug("Module {s} loaded.", .{module.name});
    }
    return true;
}

pub fn init() bool {
    event.init();
    hook_manager = HookManager.init(allocator);

    var all_modules_loaded: bool = true;
    for (modules) |module| {
        module.loaded = module.init();
        if (!module.loaded) {
            log.err("Failed to load module {s}.", .{module.name});
            all_modules_loaded = false;
        } else {
            log.debug("Module {s} loaded.", .{module.name});
        }
    }

    if (!all_modules_loaded) {
        log.err("Failed to load all modules. Stop loading features.", .{});
        return false;
    }

    init_features();

    return true;
}

fn init_features() void {
    for (features) |feature| {
        if (feature.shouldLoad()) {
            feature.loaded = feature.init();
            if (!feature.loaded) {
                log.warn("Failed to load feature {s}.", .{feature.name});
            } else {
                log.debug("Feature {s} loaded.", .{feature.name});
            }
        } else {
            log.info("Skipped loading feature {s}.", .{feature.name});
        }
    }
}

pub fn deinit() void {
    for (core_modules ++ modules) |module| {
        if (!module.loaded) {
            continue;
        }
        module.deinit();
        module.loaded = false;
    }

    for (features) |feature| {
        if (!feature.loaded) {
            continue;
        }
        feature.deinit();
        feature.loaded = false;
    }

    hook_manager.deinit();
    event.deinit();

    const leak_check = gpa.deinit();
    if (leak_check == .leak) {
        log.warn("Memory leak detected", .{});
    }
    tier0.module.loaded = false;
}
