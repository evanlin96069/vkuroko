const std = @import("std");

const core = @import("../core.zig");
const modules = @import("../modules.zig");
const tier1 = modules.tier1;
const ConCommand = tier1.ConCommand;

const Feature = @import("Feature.zig");

const zhook = @import("zhook");
const MatchedPattern = zhook.mem.MatchedPattern;

const DataMap = @import("sdk").DataMap;

const completion = @import("../utils/completion.zig");

pub var server_map: std.StringHashMap(std.StringHashMap(usize)) = undefined;
pub var client_map: std.StringHashMap(std.StringHashMap(usize)) = undefined;

// class names for datamap_walk completion
var class_names: ?[][]const u8 = null;

const DataMapInfo = struct {
    num_fields: c_int,
    map: *DataMap,

    fn fromPattern(pattern: MatchedPattern) DataMapInfo {
        const num_field_offset: usize = 6;
        const map_offset: usize = if (pattern.index == 2) 17 else 12;

        const num_fields: *align(1) const c_int = @ptrCast(pattern.ptr + num_field_offset);
        const map: *align(1) const *DataMap = @ptrCast(pattern.ptr + map_offset);
        return DataMapInfo{
            .num_fields = num_fields.*,
            .map = map.*,
        };
    }
};

fn isAddressLegal(addr: usize, start: usize, len: usize) bool {
    return addr >= start and addr <= start + len;
}

fn doesMapLooksValid(map: *const DataMap, start: usize, len: usize) bool {
    if (!isAddressLegal(@intFromPtr(map), start, len)) {
        return false;
    }

    if (!isAddressLegal(@intFromPtr(map.data_desc), start, len)) {
        return false;
    }

    if (!isAddressLegal(@intFromPtr(map.data_class_name), start, len)) {
        return false;
    }

    var i: u32 = 0;
    while (i < 64) : (i += 1) {
        if (map.data_class_name[i] == 0) {
            return i > 0;
        }
    }

    return false;
}

fn addFields(
    out_map: *std.StringHashMap(usize),
    datamap: *DataMap,
    base_offset: usize,
    prefix: []u8,
) !void {
    if (datamap.base_map) |base_map| {
        try addFields(out_map, base_map, base_offset, prefix);
    }

    var i: u32 = 0;
    while (i < datamap.data_num_fields) : (i += 1) {
        const desc = &datamap.data_desc[i];
        switch (desc.field_type) {
            .none,
            .function,
            .input,
            => {
                continue;
            },
            else => {},
        }

        // FTYPEDESC_INPUT | FTYPEDESC_OUTPUT
        if (desc.flags & (0x0008 | 0x0010) != 0) {
            continue;
        }

        const offset: usize = @intCast(desc.field_offset[0]);
        const name = std.mem.span(desc.field_name);

        if (desc.field_type == .embedded) {
            const field_prefix = try std.mem.concat(core.allocator, u8, &[_][]const u8{ name, "." });
            defer core.allocator.free(field_prefix);

            try addFields(out_map, desc.td, offset, field_prefix);
        } else {
            const key = try std.fmt.allocPrint(
                core.allocator,
                "{s}::{s}{s}",
                .{
                    datamap.data_class_name,
                    prefix,
                    name,
                },
            );
            errdefer core.allocator.free(key);

            if (out_map.get(key)) |v| {
                if (v != base_offset + offset) {
                    std.log.debug("Found a duplicated datamap field with a different offset:", .{});
                    std.log.debug("{s}: {d}/{d}", .{ key, v, base_offset + offset });
                }
                core.allocator.free(key);
            } else {
                try out_map.put(key, base_offset + offset);
            }
        }
    }
}

pub fn getField(comptime T: type, ptr: *anyopaque, offset: usize) *T {
    const base: [*]u8 = @ptrCast(ptr);
    const field: *T = @alignCast(@ptrCast(base + offset));
    return field;
}

fn addMap(datamap: *DataMap, dll_map: *std.StringHashMap(std.StringHashMap(usize))) !void {
    const key = std.mem.span(datamap.data_class_name);
    if (dll_map.contains(key)) {
        return error.DuplicatedClass;
    }

    var map = std.StringHashMap(usize).init(core.allocator);
    errdefer {
        var it = map.iterator();
        while (it.next()) |kv| {
            core.allocator.free(kv.key_ptr.*);
        }
        map.deinit();
    }

    try addFields(&map, datamap, 0, "");

    try dll_map.put(key, map);
}

const datamap_patterns = zhook.mem.makePatterns(.{
    "C7 05 ?? ?? ?? ?? ?? ?? ?? ?? C7 05 ?? ?? ?? ?? ?? ?? ?? ?? B8",
    "C7 05 ?? ?? ?? ?? ?? ?? ?? ?? C7 05 ?? ?? ?? ?? ?? ?? ?? ?? C3",
    "C7 05 ?? ?? ?? ?? ?? ?? ?? ?? B8 ?? ?? ?? ?? C7 05",
});

var vkrk_datamap_print = ConCommand.init(.{
    .name = "vkrk_datamap_print",
    .help_string = "Prints all datamaps.",
    .command_callback = datamap_print_Fn,
});

fn datamap_print_Fn(args: *const tier1.CCommand) callconv(.C) void {
    _ = args;

    var server_it = server_map.iterator();
    std.log.info("Server datamaps:", .{});
    while (server_it.next()) |kv| {
        std.log.info("    {s}", .{kv.key_ptr.*});
    }

    var client_it = client_map.iterator();
    std.log.info("Client datamaps:", .{});
    while (client_it.next()) |kv| {
        std.log.info("    {s}", .{kv.key_ptr.*});
    }
}

var vkrk_datamap_walk = ConCommand.init(.{
    .name = "vkrk_datamap_walk",
    .help_string = "Walk through a datamap and print all offsets.",
    .command_callback = datamap_walk_Fn,
    .completion_callback = datamap_walk_completionFn,
});

fn printDatamap(map: *const std.StringHashMap(usize)) void {
    const Field = struct {
        name: []const u8,
        offset: usize,

        fn compareOffset(context: void, a: @This(), b: @This()) bool {
            _ = context;
            return a.offset < b.offset;
        }
    };

    var fields = core.allocator.alloc(Field, map.count()) catch return;
    defer core.allocator.free(fields);

    var i: u32 = 0;
    var it = map.iterator();
    while (it.next()) |kv| : (i += 1) {
        fields[i] = .{
            .name = kv.key_ptr.*,
            .offset = kv.value_ptr.*,
        };
    }
    std.mem.sort(Field, fields, {}, Field.compareOffset);

    for (fields) |field| {
        std.log.info("    {s}: {d}", .{ field.name, field.offset });
    }
}

fn datamap_walk_Fn(args: *const tier1.CCommand) callconv(.C) void {
    if (args.argc != 2) {
        std.log.info("Usage: vkrk_datamap_walk <class name>", .{});
        return;
    }

    if (server_map.get(args.args(1))) |map| {
        std.log.info("Server map:", .{});
        printDatamap(&map);
    }

    if (client_map.get(args.args(1))) |map| {
        std.log.info("Client map:", .{});
        printDatamap(&map);
    }
}

fn datamap_walk_completionFn(
    partial: [*:0]const u8,
    commands: *[ConCommand.completion_max_items][ConCommand.completion_item_length]u8,
) callconv(.C) c_int {
    if (class_names) |names| {
        return completion.simpleComplete(
            std.mem.span(vkrk_datamap_walk.base.name),
            names,
            partial,
            commands,
        );
    }
    return 0;
}

pub var feature: Feature = .{
    .name = "datamap",
    .shouldLoad = shouldLoad,
    .init = init,
    .deinit = deinit,
};

fn shouldLoad() bool {
    return true;
}

fn init() bool {
    const server_dll = zhook.mem.getModule("server") orelse return false;
    const client_dll = zhook.mem.getModule("client") orelse return false;

    var server_patterns = std.ArrayList(MatchedPattern).init(core.allocator);
    defer server_patterns.deinit();
    zhook.mem.scanAllPatterns(server_dll, datamap_patterns[0..], &server_patterns) catch {
        return false;
    };

    var client_patterns = std.ArrayList(MatchedPattern).init(core.allocator);
    defer client_patterns.deinit();
    zhook.mem.scanAllPatterns(client_dll, datamap_patterns[0..], &client_patterns) catch {
        return false;
    };

    server_map = std.StringHashMap(std.StringHashMap(usize)).init(core.allocator);
    client_map = std.StringHashMap(std.StringHashMap(usize)).init(core.allocator);

    var class_names_set = std.StringHashMap(void).init(core.allocator);
    defer class_names_set.deinit();

    for (server_patterns.items) |pattern| {
        const info = DataMapInfo.fromPattern(pattern);

        if (info.num_fields > 0 and doesMapLooksValid(info.map, @intFromPtr(server_dll.ptr), server_dll.len)) {
            addMap(info.map, &server_map) catch {
                continue;
            };
            class_names_set.put(std.mem.span(info.map.data_class_name), {}) catch {};
        }
    }

    for (client_patterns.items) |pattern| {
        const info = DataMapInfo.fromPattern(pattern);

        if (info.num_fields > 0 and doesMapLooksValid(info.map, @intFromPtr(client_dll.ptr), client_dll.len)) {
            addMap(info.map, &client_map) catch {
                continue;
            };
            class_names_set.put(std.mem.span(info.map.data_class_name), {}) catch {};
        }
    }

    class_names = core.allocator.alloc([]const u8, class_names_set.count()) catch null;
    if (class_names) |names| {
        var i: usize = 0;
        var it = class_names_set.iterator();
        while (it.next()) |entry| : (i += 1) {
            names[i] = entry.key_ptr.*;
        }
    }

    vkrk_datamap_print.register();
    vkrk_datamap_walk.register();

    return true;
}

fn deinit() void {
    if (class_names) |names| {
        core.allocator.free(names);
    }

    var it = server_map.iterator();
    while (it.next()) |kv| {
        var inner_it = kv.value_ptr.iterator();
        while (inner_it.next()) |inner_kv| {
            core.allocator.free(inner_kv.key_ptr.*);
        }
        kv.value_ptr.deinit();
    }
    server_map.deinit();

    it = client_map.iterator();
    while (it.next()) |kv| {
        var inner_it = kv.value_ptr.iterator();
        while (inner_it.next()) |inner_kv| {
            core.allocator.free(inner_kv.key_ptr.*);
        }
        kv.value_ptr.deinit();
    }
    client_map.deinit();
}
