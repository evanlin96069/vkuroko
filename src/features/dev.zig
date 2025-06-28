const std = @import("std");

const event = @import("../event.zig");

const core = @import("../core.zig");

const modules = @import("../modules.zig");
const tier1 = modules.tier1;
const vgui = modules.vgui;
const engine = modules.engine;

const Color = @import("sdk").Color;

const Feature = @import("Feature.zig");

pub var feature: Feature = .{
    .name = "dev",
    .shouldLoad = shouldLoad,
    .init = init,
    .deinit = deinit,
};

var vkrk_debug_hud = tier1.Variable.init(.{
    .name = "vkrk_debug_hud",
    .help_string = "Draw test HUD.",
    .default_value = "0",
});

var vkrk_debug_cmd = tier1.ConCommand.init(.{
    .name = "vkrk_debug_cmd",
    .help_string = "For debuging CCommand.",
    .command_callback = debug_cmd_Fn,
});

fn debug_cmd_Fn(args: *const tier1.CCommand) callconv(.C) void {
    std.log.info("argc = {d}", .{args.argc});
    std.log.info("argv_0_size = {d}", .{args.argv_0_size});
    std.log.info("args_buffer = \"{s}\"", .{args.args_buffer});
    var i: u32 = 0;
    while (i < args.argc) : (i += 1) {
        std.log.info("argv[{d}] = \"{s}\"", .{ i, args.argv[i] });
    }

    core.log.info("This is an info.", .{});
    core.log.warn("This is a warning.", .{});
    core.log.err("This is an error.", .{});
    core.log.debug("This is a debug message.", .{});
}

fn shouldLoad() bool {
    return true;
}

fn onPaint() void {
    if (vkrk_debug_hud.getBool()) {
        const screen = vgui.imatsystem.getScreenSize();
        const cols = 8;
        const rows = 8;
        const padding: i32 = 10;

        const rect_width = @divFloor(screen.wide - padding * (cols + 1), cols);
        const rect_height = @divFloor(screen.tall - padding * (rows + 1), rows);

        const colors = [_]Color{
            .{ .r = 0, .g = 0, .b = 0 },
            .{ .r = 87, .g = 80, .b = 104 },
            .{ .r = 242, .g = 154, .b = 48 },
            .{ .r = 225, .g = 216, .b = 239 },
        };

        var row: i32 = 0;
        while (row < rows) : (row += 1) {
            var col: i32 = 0;
            while (col < cols) : (col += 1) {
                const x0 = padding + col * (rect_width + padding);
                const y0 = padding + row * (rect_height + padding);
                const x1 = x0 + rect_width;
                const y1 = y0 + rect_height;

                vgui.imatsystem.drawSetColor(colors[@as(u32, @intCast(row + col)) % colors.len]);
                vgui.imatsystem.drawFilledRect(x0, y0, x1, y1);
            }
        }
    }
}

fn init() bool {
    vkrk_debug_hud.register();
    vkrk_debug_cmd.register();

    event.paint.connect(onPaint);

    return true;
}

fn deinit() void {}
