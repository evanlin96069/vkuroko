const std = @import("std");

const texthud = @import("../texthud.zig");

const kuroko = @import("kuroko");
const VM = kuroko.KrkVM;
const KrkValue = kuroko.KrkValue;
const KrkString = kuroko.KrkString;
const KrkInstance = kuroko.KrkInstance;

pub fn bindAttributes(module: *KrkInstance) void {
    if (!texthud.feature.loaded) {
        return;
    }

    module.bindFunction("draw_text_hud", draw_text_hud).setDoc(
        \\@brief Draws text HUD, should only be called in `on_tick` event.
    );
}

fn draw_text_hud(argc: c_int, argv: [*]const KrkValue, has_kw: c_int) callconv(.C) KrkValue {
    var string: [*:0]const u8 = undefined;
    if (!kuroko.parseArgs(
        "draw_text_hud",
        argc,
        argv,
        has_kw,
        "s",
        &.{"string"},
        .{&string},
    )) {
        return KrkValue.noneValue();
    }

    texthud.drawTextHUD("{s}", .{string});

    return KrkValue.noneValue();
}
