const std = @import("std");
const DynLib = @import("utils/DynLib.zig");

pub const CreateInterfaceFn = *const fn (name: [*:0]const u8, ret: ?*c_int) callconv(.C) ?*align(@alignOf(*anyopaque)) anyopaque;

pub var engineFactory: CreateInterfaceFn = undefined;
pub var serverFactory: CreateInterfaceFn = undefined;

const InterfaceInfo = struct {
    version: u32,
    interface: *align(@alignOf(*anyopaque)) anyopaque,
};

fn getProcAddress(comptime module_name: []const u8, comptime name: [:0]const u8) !CreateInterfaceFn {
    var lib = try DynLib.open(module_name);
    defer lib.close();
    return lib.lookup(CreateInterfaceFn, name) orelse return error.SymbolNotFound;
}

pub fn getFactory(comptime module_name: []const u8) ?CreateInterfaceFn {
    return getProcAddress(module_name, "CreateInterface") catch return null;
}

pub fn create(factory: CreateInterfaceFn, comptime name: []const u8, comptime versions: anytype) ?InterfaceInfo {
    comptime var version_array: [versions.len]u32 = versions;

    // Sometimes the game will allow using older version, so always try the new one first.
    comptime std.mem.sort(u32, &version_array, {}, std.sort.desc(u32));

    inline for (version_array) |version| {
        if (version > 999) {
            @compileError("Version too high");
        }
        const version_string = comptime std.fmt.comptimePrint("{s}{d:0>3}", .{ name, version });
        if (factory(version_string, null)) |interface| {
            std.log.debug("Using {s}", .{version_string});
            return InterfaceInfo{
                .version = version,
                .interface = interface,
            };
        }
    }
    return null;
}

pub const IAppSystem = extern struct {
    _vt: *align(@alignOf(*anyopaque)) const anyopaque,

    pub const VTable = extern struct {
        connect: *const anyopaque,
        disconnect: *const anyopaque,
        queryInterface: *const anyopaque,
        init: *const anyopaque,
        shutdown: *const anyopaque,
    };
};
