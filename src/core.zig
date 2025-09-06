const std = @import("std");
const builtin = @import("builtin");

const sdk = @import("sdk");
const tier0 = @import("modules/tier0.zig");
const Module = @import("modules/Module.zig");
const Feature = @import("features/Feature.zig");
const event = @import("event.zig");
const HookManager = @import("zhook").HookManager;
const colorLog = @import("log.zig").colorLog;

pub const windows = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("windows.h");
});

pub const log = std.log.scoped(.vkuroko);

var exec_page: [std.heap.page_size_min]u8 align(std.heap.page_size_min) = undefined;

pub var hook_manager: HookManager = undefined;

var gpa: std.heap.DebugAllocator(.{}) = .init;
pub const allocator =
    if (builtin.mode == .Debug)
        gpa.allocator()
    else
        std.heap.smp_allocator;

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
        @import("features/entlist.zig"),
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
            log.err("Failed to load module {s}", .{module.name});
            return false;
        }
        log.debug("Module {s} loaded", .{module.name});
    }
    return true;
}

pub fn init() bool {
    event.init();

    hook_manager = HookManager.init(allocator, exec_page[0..]);
    // mprotect after hook manager init so we can always deinit hook manager on unload
    std.posix.mprotect(exec_page[0..], 0b111) catch {
        log.err("Failed to setup memory for function hooking", .{});
        return false;
    };

    var all_modules_loaded: bool = true;
    for (modules) |module| {
        module.loaded = module.init();
        if (!module.loaded) {
            log.err("Failed to load module {s}", .{module.name});
            all_modules_loaded = false;
        } else {
            log.debug("Module {s} loaded", .{module.name});
        }
    }

    if (!all_modules_loaded) {
        log.err("Failed to load all modules. Stop loading features", .{});
        return false;
    }

    init_features();
    log.info("Successfully loaded", .{});
    print_feature_status();

    return true;
}

fn init_features() void {
    for (features) |feature| {
        if (feature.shouldLoad()) {
            feature.loaded = feature.init();
            if (!feature.loaded) {
                feature.status = .failed;
                log.warn("Failed to load feature {s}", .{feature.name});
            } else {
                feature.status = .ok;
                log.debug("Feature {s} loaded", .{feature.name});
            }
        } else {
            feature.status = .skipped;
            log.info("Skipped loading feature {s}", .{feature.name});
        }
    }
}

fn print_feature_status() void {
    const green: sdk.Color = .{ .r = 128, .g = 255, .b = 128 };
    const red: sdk.Color = .{ .r = 255, .g = 128, .b = 128 };
    const cyan: sdk.Color = .{ .r = 100, .g = 255, .b = 255 };
    std.log.info("---- List of plugin features ---", .{});
    for (features) |feature| {
        switch (feature.status) {
            .ok => colorLog(green, " [     OK!     ] {s}", .{feature.name}),
            .failed => colorLog(red, " [   FAILED!   ] {s}", .{feature.name}),
            .skipped, .none => colorLog(cyan, " [   skipped   ] {s}", .{feature.name}),
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

    const hook_count = hook_manager.hooks.items.len;
    const unhook_count = hook_manager.deinit();
    if (hook_count != unhook_count) {
        log.warn("Failed to unhook {d} out of {d} functions", .{ hook_count - unhook_count, hook_count });
    }
    event.deinit();

    if (builtin.mode == .Debug) {
        const leak_check = gpa.deinit();
        if (leak_check == .leak) {
            log.warn("Memory leak detected", .{});
        }
    }

    log.info("Plugin unloaded", .{});
}
