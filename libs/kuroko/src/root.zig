const std = @import("std");

extern fn krk_exec_module(src: [*:0]const u8, module_name: [*:0]const u8) c_int;

export fn krk_init_modules() void {
    _ = krk_exec_module(@embedFile("krk_modules/collections.krk"), "collections");
    _ = krk_exec_module(@embedFile("krk_modules/dataclasses.krk"), "dataclasses");
    _ = krk_exec_module(@embedFile("krk_modules/help.krk"), "help");
    _ = krk_exec_module(@embedFile("krk_modules/json.krk"), "json");
    _ = krk_exec_module(@embedFile("krk_modules/pheap.krk"), "pheap");
    _ = krk_exec_module(@embedFile("krk_modules/string.krk"), "string");
}
