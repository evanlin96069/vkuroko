const std = @import("std");
const builtin = @import("builtin");

const core = @import("../core.zig");
const modules = @import("../modules.zig");
const tier1 = modules.tier1;
const ConCommand = tier1.ConCommand;

const server = modules.server;
const client = modules.client;

const str_utils = @import("../utils/str_utils.zig");

const Feature = @import("Feature.zig");

const zhook = @import("zhook");
const MatchedPattern = zhook.mem.MatchedPattern;

const DataMap = @import("sdk").DataMap;

const completion = @import("../utils/completion.zig");

pub var server_map: std.StringHashMap(std.StringHashMap(usize)) = undefined;
pub var client_map: std.StringHashMap(std.StringHashMap(usize)) = undefined;

const datamap_patterns = zhook.mem.makePatterns(switch (builtin.os.tag) {
    .windows => .{
        "C7 05 ?? ?? ?? ?? ?? ?? ?? ?? C7 05 ?? ?? ?? ?? ?? ?? ?? ?? B8",
        "C7 05 ?? ?? ?? ?? ?? ?? ?? ?? C7 05 ?? ?? ?? ?? ?? ?? ?? ?? C3",
        "C7 05 ?? ?? ?? ?? ?? ?? ?? ?? B8 ?? ?? ?? ?? C7 05",
    },
    .linux => .{
        // These are untested. Hopefully work on old Linux builds that doesn't use PIC.
        "B8 ?? ?? ?? ?? C7 05 ?? ?? ?? ?? ?? ?? ?? ?? C7 05",
        "B8 ?? ?? ?? ?? C7 05 ?? ?? ?? ?? ?? ?? ?? ?? 89 E5 5D C7 05",
        "C7 05 ?? ?? ?? ?? ?? ?? ?? ?? B8 ?? ?? ?? ?? C7 05",
    },
    else => unreachable,
});

// Linux-only
const pic_datamap_patterns = zhook.mem.makePatterns(.{
    "C7 83 ?? ?? ?? ?? ?? ?? ?? ?? 8D 83 ?? ?? ?? ?? 89 83 ?? ?? ?? ?? 8D 83 ?? ?? ?? ?? C7 83",
    "74 35 C7 83 ?? ?? ?? ?? ?? ?? ?? ?? 8D 83 ?? ?? ?? ?? 89 83 ?? ?? ?? ?? 8D 83 ?? ?? ?? ?? 89 83",
    "C7 80 ?? ?? ?? ?? ?? ?? ?? ?? 8D 90 ?? ?? ?? ?? 89 90 ?? ?? ?? ?? 8D 80 ?? ?? ?? ?? C3",
    "C7 ?? ?? ?? ?? ?? ?? ?? ?? ?? 8D ?? ?? ?? ?? ?? 89 ?? ?? ?? ?? ?? 8D 65",
});

const DataMapInfo = struct {
    num_fields: c_int,
    map: u32,

    fn fromPattern(pattern: MatchedPattern) DataMapInfo {
        const num_field_offset: usize = switch (builtin.os.tag) {
            .windows => 6,
            .linux => switch (pattern.index) {
                0, 1 => 11,
                2 => 6,
                else => unreachable,
            },
            else => unreachable,
        };
        const map_offset: usize = switch (builtin.os.tag) {
            .windows => switch (pattern.index) {
                0, 1 => 12,
                2 => 17,
                else => unreachable,
            },
            .linux => switch (pattern.index) {
                0, 1 => 11,
                2 => 1,
                else => unreachable,
            },
            else => unreachable,
        };

        const num_fields = zhook.mem.loadValue(c_int, pattern.ptr + num_field_offset);
        const map: u32 = zhook.mem.loadValue(u32, pattern.ptr + map_offset);
        return DataMapInfo{
            .num_fields = num_fields,
            .map = map,
        };
    }

    fn fromPICPattern(pattern: MatchedPattern, GOT_addr: u32) DataMapInfo {
        const num_field_offset: usize = switch (pattern.index) {
            0 => 34,
            1 => 8,
            2, 3 => 6,
            else => unreachable,
        };
        const map_offset: usize = switch (pattern.index) {
            0 => 24,
            1 => 14,
            2, 3 => 18,
            else => unreachable,
        };

        const num_fields = zhook.mem.loadValue(c_int, pattern.ptr + num_field_offset);
        const map: u32 = GOT_addr +% zhook.mem.loadValue(u32, pattern.ptr + map_offset);
        return DataMapInfo{
            .num_fields = num_fields,
            .map = map,
        };
    }
};

fn isAddressLegal(addr: usize, module: []const u8) bool {
    const start = @intFromPtr(module.ptr);
    return addr >= start and addr <= start + module.len;
}

fn doesMapLooksValid(map_addr: u32, module: []const u8) bool {
    if (!isAddressLegal(map_addr, module)) return false;

    // alignment check
    if (map_addr % @alignOf(DataMap) != 0) return false;

    const map: *DataMap = @ptrFromInt(map_addr);

    if (!isAddressLegal(@intFromPtr(map.data_desc), module)) return false;

    if (!isAddressLegal(@intFromPtr(map.data_class_name), module)) return false;

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
    // Add derived class fields first, so duplicated fields will be in base class.
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

        var offset: usize = base_offset;
        offset += @intCast(desc.field_offset[0]);

        const name = std.mem.span(desc.field_name);

        if (desc.field_type == .embedded) {
            const field_prefix = try std.fmt.allocPrint(
                core.allocator,
                "{s}{s}.",
                .{
                    prefix,
                    name,
                },
            );
            defer core.allocator.free(field_prefix);

            try addFields(out_map, desc.td, offset, field_prefix);
        } else {
            const key = try std.fmt.allocPrint(
                core.allocator,
                "{s}{s}",
                .{
                    prefix,
                    name,
                },
            );
            errdefer core.allocator.free(key);

            if (out_map.get(key)) |v| {
                if (v != offset) {
                    // Duplicated field, add class name.
                    const new_key = try std.fmt.allocPrint(
                        core.allocator,
                        "{s}{s}::{s}",
                        .{
                            prefix,
                            datamap.data_class_name,
                            name,
                        },
                    );
                    errdefer core.allocator.free(new_key);
                    try out_map.put(new_key, offset);
                }
                core.allocator.free(key);
            } else {
                try out_map.put(key, offset);
            }
        }
    }

    // Add base class fields
    if (datamap.base_map) |base_map| {
        try addFields(out_map, base_map, base_offset, prefix);
    }
}

pub fn getFieldOffset(map: []const u8, field: []const u8, is_server: bool) ?usize {
    const data_map = if (is_server) &server_map else &client_map;
    if (data_map.get(map)) |m| {
        return m.get(field);
    }
    return null;
}

pub fn getField(comptime T: type, ptr: *anyopaque, offset: usize) *T {
    const base: [*]u8 = @ptrCast(ptr);
    const field: *T = @ptrCast(@alignCast(base + offset));
    return field;
}

pub fn CachedField(comptime field: struct {
    T: type,
    map: []const u8,
    field: []const u8,
    is_server: bool,
    additional_offset: i32 = 0,
}) type {
    return struct {
        const Self = @This();

        offset: ?usize = null,

        pub fn get(self: *Self) ?usize {
            if (self.offset) |v| {
                return @intCast(@as(i32, @intCast(v)) + field.additional_offset);
            }
            const off = getFieldOffset(field.map, field.field, field.is_server);
            self.offset = off;
            return if (off) |v| @intCast(@as(i32, @intCast(v)) + field.additional_offset) else null;
        }

        pub fn exists(self: *Self) bool {
            return self.get() != null;
        }

        pub fn getPtr(self: *Self, ent: *anyopaque) ?*field.T {
            if (self.get()) |offset| {
                return getField(field.T, ent, offset);
            }
            return null;
        }
    };
}

pub fn CachedFields(comptime field_infos: anytype) type {
    comptime var tuple_fields: [field_infos.len]std.builtin.Type.StructField = undefined;
    inline for (field_infos, &tuple_fields, 0..) |info, *field, field_idx| {
        const additional_offset = switch (info.len) {
            4 => 0,
            5 => info[4],
            else => @compileError("field info should have 4 or 5 elements"),
        };

        const FieldTy = CachedField(.{
            .T = info[0],
            .map = info[1],
            .field = info[2],
            .is_server = info[3],
            .additional_offset = additional_offset,
        });

        field.* = .{
            .name = std.fmt.comptimePrint("{d}", .{field_idx}),
            .type = FieldTy,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(FieldTy),
        };
    }

    const FieldTuple = @Type(.{ .@"struct" = .{
        .is_tuple = true,
        .layout = .auto,
        .decls = &.{},
        .fields = &tuple_fields,
    } });

    comptime var return_tuple_fields: [field_infos.len]std.builtin.Type.StructField = undefined;
    inline for (field_infos, &return_tuple_fields, 0..) |info, *field, field_idx| {
        const FieldTy = ?*info[0];
        field.* = .{
            .name = std.fmt.comptimePrint("{d}", .{field_idx}),
            .type = FieldTy,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(FieldTy),
        };
    }

    const ReturnTuple = @Type(.{ .@"struct" = .{
        .is_tuple = true,
        .layout = .auto,
        .decls = &.{},
        .fields = &return_tuple_fields,
    } });

    return struct {
        const Self = @This();

        fields: FieldTuple = default: {
            var x: FieldTuple = undefined;
            for (&x) |*f| f.* = .{};
            break :default x;
        },

        pub fn hasAll(self: *Self) bool {
            inline for (&self.fields) |*f| {
                if (!f.exists()) {
                    return false;
                }
            }
            return true;
        }

        pub fn getAllPtrs(self: *Self, ent: *anyopaque) ReturnTuple {
            var result: ReturnTuple = undefined;
            inline for (&result, &self.fields) |*res, *f| {
                res.* = f.getPtr(ent);
            }
            return result;
        }
    };
}

fn addMap(datamap: *DataMap, dll_map: *std.StringHashMap(std.StringHashMap(usize))) !void {
    const key = std.mem.span(datamap.data_class_name);
    if (dll_map.getPtr(key)) |p| {
        try addFields(p, datamap, 0, "");
    } else {
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
}

fn findMaps(
    module: []const u8,
    module_range: []const u8,
    dll_map: *std.StringHashMap(std.StringHashMap(usize)),
    class_names_set: *std.StringHashMap(void),
) !void {
    var patterns: std.ArrayList(MatchedPattern) = .empty;
    defer patterns.deinit(core.allocator);
    try zhook.mem.scanAllPatterns(module, datamap_patterns[0..], &patterns, core.allocator);

    for (patterns.items) |pattern| {
        const info = DataMapInfo.fromPattern(pattern);

        if (info.num_fields > 0 and doesMapLooksValid(info.map, module_range)) {
            const map: *DataMap = @ptrFromInt(info.map);
            addMap(map, dll_map) catch |err| {
                core.log.debug("Failed to add datamap {s}: {t}", .{ map.data_class_name, err });
                continue;
            };
            class_names_set.put(std.mem.span(map.data_class_name), {}) catch {};
        }
    }

    if (builtin.os.tag == .linux) {
        const GOT_addr = zhook.utils.findGOTAddr(module) orelse return;
        var pic_patterns: std.ArrayList(MatchedPattern) = .empty;
        defer pic_patterns.deinit(core.allocator);
        try zhook.mem.scanAllPatterns(module, pic_datamap_patterns[0..], &pic_patterns, core.allocator);

        for (pic_patterns.items) |pattern| {
            const info = DataMapInfo.fromPICPattern(pattern, GOT_addr);

            if (info.num_fields > 0 and doesMapLooksValid(info.map, module_range)) {
                const map: *DataMap = @ptrFromInt(info.map);
                addMap(map, dll_map) catch |err| {
                    core.log.debug("Failed to add datamap {s}: {t}", .{ map.data_class_name, err });
                    continue;
                };
                class_names_set.put(std.mem.span(map.data_class_name), {}) catch {};
            }
        }
    }
}

fn deinitMaps(dll_map: *std.StringHashMap(std.StringHashMap(usize))) void {
    var it = dll_map.iterator();
    while (it.next()) |kv| {
        var inner_it = kv.value_ptr.iterator();
        while (inner_it.next()) |inner_kv| {
            core.allocator.free(inner_kv.key_ptr.*);
        }
        kv.value_ptr.deinit();
    }
    dll_map.deinit();
}

var vkrk_datamap_print = ConCommand.init(.{
    .name = "vkrk_datamap_print",
    .help_string = "Prints all datamaps.",
    .command_callback = datamap_print_Fn,
});

fn datamap_print_Fn(args: *const tier1.CCommand) callconv(.c) void {
    _ = args;

    var server_classes = core.allocator.alloc([]const u8, server_map.count()) catch return;
    defer core.allocator.free(server_classes);

    var i: u32 = 0;
    var server_it = server_map.iterator();
    while (server_it.next()) |kv| : (i += 1) {
        server_classes[i] = kv.key_ptr.*;
    }

    std.mem.sort([]const u8, server_classes, {}, str_utils.stringLessThan);

    std.log.info("Server datamaps:", .{});
    for (server_classes) |class| {
        std.log.info("    {s}", .{class});
    }

    var client_classes = core.allocator.alloc([]const u8, client_map.count()) catch return;
    defer core.allocator.free(client_classes);

    i = 0;
    var client_it = client_map.iterator();
    while (client_it.next()) |kv| : (i += 1) {
        client_classes[i] = kv.key_ptr.*;
    }

    std.mem.sort([]const u8, client_classes, {}, str_utils.stringLessThan);

    std.log.info("Client datamaps:", .{});
    for (client_classes) |class| {
        std.log.info("    {s}", .{class});
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

fn datamap_walk_Fn(args: *const tier1.CCommand) callconv(.c) void {
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

var class_names: ?[][]const u8 = null;

fn datamap_walk_completionFn(
    partial: [*:0]const u8,
    commands: *[ConCommand.completion_max_items][ConCommand.completion_item_length]u8,
) callconv(.c) c_int {
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
    var server_dll_range = server.server_dll;
    var client_dll_range = client.client_dll;
    if (builtin.os.tag == .linux) {
        server_dll_range = zhook.utils.getEntireModule("server") orelse return false;
        client_dll_range = zhook.utils.getEntireModule("client") orelse return false;
    }

    server_map = std.StringHashMap(std.StringHashMap(usize)).init(core.allocator);
    client_map = std.StringHashMap(std.StringHashMap(usize)).init(core.allocator);

    var class_names_set = std.StringHashMap(void).init(core.allocator);
    defer class_names_set.deinit();

    findMaps(
        server.server_dll,
        server_dll_range,
        &server_map,
        &class_names_set,
    ) catch {
        return false;
    };
    findMaps(
        client.client_dll,
        client_dll_range,
        &client_map,
        &class_names_set,
    ) catch {
        deinitMaps(&server_map);
        return false;
    };

    class_names = core.allocator.alloc([]const u8, class_names_set.count()) catch null;
    if (class_names) |names| {
        var i: usize = 0;
        var it = class_names_set.iterator();
        while (it.next()) |entry| : (i += 1) {
            names[i] = entry.key_ptr.*;
        }
    }

    core.log.debug("Found {d} server datamaps and {d} client datamaps", .{ server_map.count(), client_map.count() });
    if (server_map.count() == 0 and client_map.count() == 0) {
        server_map.deinit();
        client_map.deinit();
        core.log.warn("Found no datamaps", .{});
        return false;
    }

    vkrk_datamap_print.register();
    vkrk_datamap_walk.register();

    return true;
}

fn deinit() void {
    if (class_names) |names| {
        core.allocator.free(names);
    }

    deinitMaps(&server_map);
    deinitMaps(&client_map);
}
